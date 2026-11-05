#!/usr/bin/env bash
#
# check_api.sh — проверка доступности API по HTTP-коду ответа.
#
# Использование:
#   ./check_api.sh <URL> [ожидаемый_код]
#
# Примеры:
#   ./check_api.sh https://httpbin.org/status/200
#   ./check_api.sh http://localhost:80
#   ./check_api.sh https://httpbin.org/status/201 201
#
# Коды возврата:
#   0 — API доступен (код ответа совпал с ожидаемым)
#   1 — API недоступен / неверный код ответа / ошибка аргументов

set -u

TIMEOUT="${CHECK_API_TIMEOUT:-10}"

usage() {
    echo "Использование: $(basename "$0") <URL> [ожидаемый_код]" >&2
    echo "Пример:        $(basename "$0") https://httpbin.org/status/200" >&2
}

# --- обработка аргументов ---------------------------------------------------
if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo "Ошибка: неверное количество аргументов." >&2
    usage
    exit 1
fi

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    usage
    exit 0
fi

URL="$1"
EXPECTED="${2:-200}"

# URL должен начинаться с http:// или https://
if [[ ! "$URL" =~ ^https?://[^[:space:]]+$ ]]; then
    echo "Ошибка: '$URL' не похож на URL (ожидается http:// или https://)." >&2
    exit 1
fi

# Ожидаемый код — трёхзначное число
if [[ ! "$EXPECTED" =~ ^[1-5][0-9]{2}$ ]]; then
    echo "Ошибка: ожидаемый код '$EXPECTED' должен быть трёхзначным HTTP-кодом." >&2
    exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
    echo "Ошибка: curl не установлен." >&2
    exit 1
fi

# --- запрос -----------------------------------------------------------------
# -s  : без прогресс-бара
# -o  : тело ответа не нужно
# -w  : вывести только HTTP-код
# -L  : следовать редиректам
HTTP_CODE=$(curl -s -L -o /dev/null -w '%{http_code}' \
    --connect-timeout "$TIMEOUT" --max-time "$TIMEOUT" "$URL")
CURL_EXIT=$?

# Если соединение не установилось, curl отдаёт код 000
if [[ $CURL_EXIT -ne 0 && "$HTTP_CODE" == "000" ]]; then
    echo "API недоступен, код ответа: 000 (ошибка curl: $CURL_EXIT)"
    exit 1
fi

if [[ "$HTTP_CODE" == "$EXPECTED" ]]; then
    echo "API доступен"
    exit 0
else
    echo "API недоступен, код ответа: $HTTP_CODE"
    exit 1
fi
