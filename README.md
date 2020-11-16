yandex-pdd-cli.sh
=================

Примитивный клиент API «Яндекс.Почта для домена», едва способный:
* выдать список всех записей домена;
* найти и показать записи по ID или поддомену;
* добавить, изменить, удалить записи.

Подробнее об API см. [официальную документацию](https://yandex.ru/dev/pdd/doc/about-docpage/).

Не работает без [curl](https://curl.haxx.se/) и [jq](https://stedolan.github.io/jq/)!
Для работы с национальными доменами требует [idn](http://www.gnu.org/software/libidn).

Общая форма запуска скрипта такова:

    [PDD_TOKEN="токен"] [PDD_DOMAIN="домен"] yandex-pdd-cli.sh [-t токен] [-d домен] [--] команда [аргументы...]

[Токен доступа к API](https://yandex.ru/dev/pdd/doc/concepts/access.html)
можно указать как через переменную окружения `PDD_TOKEN`, так и через
опцию `-t`.

Домен (зону), с которой хотите работать, можно указать как через переменную
окружения `PDD_DOMAIN`, так и через опцию `-d`.

Команды могут быть такими:

help: выведет краткую справку по использованию скрипта. Ту же справку можно
получить так:

    yandex-pdd-cli.sh -h

list: выведет список записей домена в формате, подобном [zone-файлам](https://en.wikipedia.org/wiki/Zone_file):

    id  name  ttl  type  data

show: выведет перечисленные в аргументах команды записи домена (укажите ID
или поддомены) в формате, подобном zone-файлам:

    id  name  ttl  type  data

add: добавит записи построчно из stdin в формате, подобном zone-файлам
(TTL необязателен и по умолчанию равен 21600):

    name  ttl  type  data

edit: изменит записи построчно из stdin в формате, подобном zone-файлам
(TTL необязателен и по умолчанию равен 21600):

    id  name  ttl  type  data

delete: удалит перечисленные в аргументах команды записи домена (укажите ID)
и выведет ответ API.

(C) 2020 Sergey Kolchin, me@ksa242.name, ksa242@gmail.com.
0BSD license.