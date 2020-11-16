#!/bin/sh
#
# Примитивный клиент API "Яндекс.Почта для домена", едва способный:
# * выдать список всех записей домена;
# * найти и показать записи по ID или поддомену;
# * добавить, изменить, удалить записи.
#
# Подробнее об API см. [официальную документацию](https://yandex.ru/dev/pdd/doc/about-docpage/).
#
# Не работает без [curl](https://curl.haxx.se/) и [jq](https://stedolan.github.io/jq/)!
# Для работы с национальными доменами требует [idn](http://www.gnu.org/software/libidn).
#
# (C) 2020 Sergey Kolchin, me@ksa242.name, ksa242@gmail.com.
# 0BSD license.

_err () {
	echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $*" >&2
}

command -v curl >/dev/null 2>&1 || { _err 'Нужен curl'; exit 127; }
command -v jq >/dev/null 2>&1 || { _err 'Нужен jq'; exit 127; }

# Флаг отладочного режима.
VERBOSE="${VERBOSE:-0}"

# Токен для доступа к API:
# https://yandex.ru/dev/pdd/doc/concepts/access.html
# https://pddimp.yandex.ru/api2/admin/get_token
PDD_TOKEN="${PDD_TOKEN:-}"

# Домен, с записями которого работаем.
PDD_DOMAIN="${PDD_DOMAIN:-}"

# TTL по умолчанию согласно документации:
# https://yandex.ru/dev/pdd/doc/reference/dns-add.html
PDD_DEFAULT_TTL=21600

_show_usage () {
	cat >&2 << EOF
$0 -h

	Выведет эту справку.

[PDD_TOKEN="токен"] [PDD_DOMAIN="домен"] $0 [-t токен] [-d домен] [--] команда [аргументы...]

	Выполнит команду:

	list
		Вывести все записи домена в формате, подобном zone-файлу:
		id  name  ttl  type  data

	show запись [запись...]
		Вывести указанные записи домена (укажите ID или поддомены) в формате:
		id  name  ttl  type  data

	add
		Добавить записи построчно из stdin в формате, подобном zone-файлам:
		name  ttl  type  data

		TTL необязателен и по умолчанию равен ${PDD_DEFAULT_TTL}.

	edit
		Изменить записи построчно из stdin в формате, подобном zone-файлам:
		id  name  ttl  type  data

		TTL необязателен и по умолчанию равен ${PDD_DEFAULT_TTL}.

	delete запись [запись...]
		Удалить указанные записи (укажите ID).
EOF
}

while getopts vht:d: opt; do
	case "${opt}" in
	v)  VERBOSE=1;;
	t)  PDD_TOKEN="${OPTARG:-${PDD_TOKEN}}";;
	d)  PDD_DOMAIN="${OPTARG:-${PDD_DOMAIN}}";;
	h)  _show_usage; exit 0;;
	\?) _show_usage; exit 1;;
	esac
done
shift $((OPTIND - 1))

[ -n "${PDD_TOKEN}" ] || {
	_show_usage
	_err 'Дайте токен для доступа к API "Яндекс.Почта для домена" через опцию "-t" или переменную PDD_TOKEN'
	exit 1
}
[ -n "${PDD_DOMAIN}" ] || {
	_show_usage
	_err 'Выберите домен через опцию "-d" или переменную PDD_DOMAIN'
	exit 1
}

# Перевести домен IDN в ASCII; например, из xn--d1acpjx3f.xn--p1ai получим яндекс.рф.
# Аргументы: домен...
# Вывод: те же домены в ASCII
_idn2ascii () {
	[ $# -gt 0 ] || return 0

	# shellcheck disable=SC2039
	local idn domain
	idn="$(command -v idn 2>/dev/null)"
	if [ -n "${idn}" ]; then
		for domain; do ${idn} -a "${domain}"; done
	else
		for domain; do printf '%s\n' "${domain}"; done
	fi
}

# Вывести все записи доменов в формате, подобном zone-файлам.
# Аргументы: домен...
# Вывод: записи в формате "id name ttl type data" (разделитель: \t).
yandex_pdd_list () {
	[ $# -gt 0 ] || return 0

	# shellcheck disable=SC2039
	local domain
	for domain; do
		[ -n "${domain}" ] || { _err 'Не указан домен (зона)'; continue; }

		curl -sL -H "PddToken: ${PDD_TOKEN}" \
			--data-raw "domain=$(_idn2ascii "${domain}")" \
			--get 'https://pddimp.yandex.ru/api2/admin/dns/list' \
		| jq -r '.records[] | [.record_id, .subdomain, .ttl, .type, .content] | @tsv'
	done
}

# Найти записи домена по ID или поддомену и вывести их в JSON.
# Аргументы: домен запись...
# Вывод: записи в JSON.
yandex_pdd_show () {
	[ $# -ge 2 ] || return 0

	# shellcheck disable=SC2039
	local domain
	domain="$1"; shift;
	[ -n "${domain}" ] || { _err 'Не указан домен (зона)'; return 0; }

	# shellcheck disable=SC2039
	local record
	for record; do
		[ -n "${record}" ] || { _err 'Не указан ID записи'; continue; }

		curl -sL -H "PddToken: ${PDD_TOKEN}" \
			--data-raw "domain=$(_idn2ascii "${domain}")" \
			--get 'https://pddimp.yandex.ru/api2/admin/dns/list' \
		| jq -S '.records[] | select("\(.record_id)" == "'"${record}"'" or .subdomain == "'"${record}"'")'
	done
}

# Добавить записи домена.
# Аргументы: домен
# Ввод: записи в формате "name ttl type data" (ttl необязателен), по одной на строку.
# Вывод: добавленные записи в JSON.
yandex_pdd_add () {
	[ $# -gt 0 ] || return 0

	# shellcheck disable=SC2039
	local domain
	domain="$1"; shift;
	[ -n "${domain}" ] || { _err 'Не указан домен (зона)'; return 0; }

	# shellcheck disable=SC2039
	local name ttl type data
	while read -r name ttl type data; do
		[ -n "${name}" ] || { _err 'Не указано имя записи'; continue; }

		if [ 0 -eq "${ttl}" ]; then
			# Вместо нулевого TTL возьмём значение по умолчанию.
			ttl="${PDD_DEFAULT_TTL}"
		elif ! printf '%s' "${ttl}" | grep -E '^[0-9]+$' >/dev/null; then
			# Необязательный TTL не указан, сдвинем тип и содержание записи.
			data="${type} ${data}"
			data="${data% }"
			type="${ttl}"
			ttl="${PDD_DEFAULT_TTL}"
		fi
		[ -n "${data}" ] || { _err 'Не указано значение записи'; continue; }

		curl -sL -H "PddToken: ${PDD_TOKEN}" \
			--data-raw "domain=$(_idn2ascii "${domain}")" \
			--data-raw "subdomain=${name}" \
			--data-raw "ttl=${ttl}" \
			--data-raw "type=${type}" \
			--data-raw "content=${data}" \
			'https://pddimp.yandex.ru/api2/admin/dns/add' \
		| jq -S '.record'
	done
}

# Изменить записи домена.
# Аргументы: домен
# Ввод: записи в формате "id name ttl type data" (ttl необязателен), по одной на строку.
# Вывод: изменённые записи в JSON.
yandex_pdd_edit () {
	[ $# -gt 0 ] || return 0

	# shellcheck disable=SC2039
	local domain
	domain="$1"; shift;
	[ -n "${domain}" ] || { _err 'Не указан домен (зона)'; return 0; }

	# shellcheck disable=SC2039
	local record name ttl type data
	while read -r record name ttl type data; do
		[ -n "${record}" ] || { _err 'Не указан ID записи'; continue; }
		[ -n "${name}" ] || { _err 'Не указано имя записи'; continue; }

		if [ 0 -eq "${ttl}" ]; then
			# Вместо нулевого TTL возьмём значение по умолчанию.
			ttl="${PDD_DEFAULT_TTL}"
		elif ! printf '%s' "${ttl}" | grep '^[0-9]\+$' >/dev/null; then
			# Необязательный TTL не указан, исправим тип и содержание записи.
			data="${type} ${data}"
			data="${data% }"
			type="${ttl}"
			ttl="${PDD_DEFAULT_TTL}"
		fi
		[ -n "${data}" ] || { _err 'Не указано значение записи'; continue; }

		curl -sL -H "PddToken: ${PDD_TOKEN}" \
			--data-raw "domain=$(_idn2ascii "${domain}")" \
			--data-raw "record_id=${record}" \
			--data-raw "subdomain=${name}" \
			--data-raw "ttl=${ttl}" \
			--data-raw "type=${type}" \
			--data-raw "content=${data}" \
			'https://pddimp.yandex.ru/api2/admin/dns/edit' \
		| jq -S '.record'
	done
}

# Удалить записи домена.
# Аргументы: домен id...
# Вывод: строка успешного ответа.
yandex_pdd_delete () {
	[ $# -ge 2 ] || return 0

	# shellcheck disable=SC2039
	local domain
	domain="$1"; shift;
	[ -n "${domain}" ] || { _err 'Не указан домен (зона)'; return 0; }

	# shellcheck disable=SC2039
	local record
	for record; do
		[ -n "${record}" ] || { _err 'Не указан ID записи'; continue; }

		curl -sL -H "PddToken: ${PDD_TOKEN}" \
			--data-raw "domain=$(_idn2ascii "${domain}")" \
			--data-raw "record_id=${record}" \
			'https://pddimp.yandex.ru/api2/admin/dns/del' \
		| jq -r '.success'
	done
}

# По умолчанию показываем список записей домена.
cmd='list'

# Первым аргументом всегда должна быть команда.
[ $# -gt 0 ] && { cmd="$1"; shift; }

case "${cmd}" in
list)   yandex_pdd_list   "${PDD_DOMAIN}";;
show)   yandex_pdd_show   "${PDD_DOMAIN}" "$@";;
add)    yandex_pdd_add    "${PDD_DOMAIN}";;
edit)   yandex_pdd_edit   "${PDD_DOMAIN}";;
delete) yandex_pdd_delete "${PDD_DOMAIN}" "$@";;
*)      _show_usage; _err "Не знаю команду ${cmd}"; exit 1;;
esac
