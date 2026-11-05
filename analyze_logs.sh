#!/usr/bin/env bash
#
# analyze_logs.sh — генерация тестового access.log и его анализ.
#
# Использование:
#   ./analyze_logs.sh [-f файл] [-n кол-во_строк] [-s]
#
#   -f FILE  путь к лог-файлу (по умолчанию: access.log)
#   -n N     сколько строк сгенерировать (по умолчанию: 500, минимум 300)
#   -s       не генерировать лог, анализировать существующий файл
#   -h       справка
#
# Формат строки лога:
#   192.168.1.10 - - [15/Aug/2026:10:15:32] "GET /api/users HTTP/1.1" 200

set -euo pipefail

LOG_FILE="access.log"
LINES=500
SKIP_GENERATE=0

usage() {
    sed -n '3,13p' "$0" | sed 's/^# \{0,1\}//'
}

while getopts ":f:n:sh" opt; do
    case "$opt" in
        f) LOG_FILE="$OPTARG" ;;
        n) LINES="$OPTARG" ;;
        s) SKIP_GENERATE=1 ;;
        h) usage; exit 0 ;;
        :) echo "Ошибка: опция -$OPTARG требует значение." >&2; exit 1 ;;
        \?) echo "Ошибка: неизвестная опция -$OPTARG." >&2; usage >&2; exit 1 ;;
    esac
done

if [[ ! "$LINES" =~ ^[0-9]+$ ]] || (( LINES < 300 )); then
    echo "Ошибка: -n должно быть числом не меньше 300." >&2
    exit 1
fi

# --- генерация --------------------------------------------------------------
generate_log() {
    local file="$1" count="$2"

    local ips=(192.168.1.10 192.168.1.11 192.168.1.25 10.0.0.5 10.0.0.7
               172.16.0.3 172.16.0.14 203.0.113.42 198.51.100.7 8.8.8.8)
    local methods=(GET GET GET GET POST POST PUT DELETE)
    local paths=(/api/users /api/users/42 /api/login /api/logout /api/orders
                 /api/products /api/health /static/app.js /index.html)
    # 200 встречается чаще — как в реальной жизни
    local codes=(200 200 200 200 200 200 201 204 301 304
                 400 401 403 404 404 500 502 503)

    local start_ts=1786788000   # 15/Aug/2026 10:00:00 UTC
    local i ts ip method path code

    : > "$file"
    for (( i = 0; i < count; i++ )); do
        # Часть IP делаем «горячими», чтобы топ был заметнее
        if (( RANDOM % 3 == 0 )); then
            ip=${ips[RANDOM % 3]}
        else
            ip=${ips[RANDOM % ${#ips[@]}]}
        fi
        method=${methods[RANDOM % ${#methods[@]}]}
        path=${paths[RANDOM % ${#paths[@]}]}
        code=${codes[RANDOM % ${#codes[@]}]}
        ts=$(( start_ts + i * 2 + RANDOM % 2 ))

        printf '%s - - [%s] "%s %s HTTP/1.1" %s\n' \
            "$ip" "$(date -u -d "@$ts" '+%d/%b/%Y:%H:%M:%S' 2>/dev/null \
                     || date -u -r "$ts" '+%d/%b/%Y:%H:%M:%S')" \
            "$method" "$path" "$code" >> "$file"
    done
}

if (( SKIP_GENERATE == 0 )); then
    echo "Генерация $LINES строк в $LOG_FILE ..."
    generate_log "$LOG_FILE" "$LINES"
fi

if [[ ! -s "$LOG_FILE" ]]; then
    echo "Ошибка: файл '$LOG_FILE' не найден или пуст." >&2
    exit 1
fi

# --- анализ -----------------------------------------------------------------
# Регулярное выражение для IPv4 в начале строки
IP_REGEX='^([0-9]{1,3}\.){3}[0-9]{1,3}'

echo
echo "===== Анализ $LOG_FILE ====="

# 1. Общее количество запросов: строки, начинающиеся с IP-адреса
TOTAL=$(grep -cE "$IP_REGEX" "$LOG_FILE")
echo "Общее количество запросов: $TOTAL"

# 2. Топ-3 IP: вытаскиваем IP регэкспом -> считаем -> сортируем
echo
echo "Топ-3 IP-адреса по числу запросов:"
grep -oE "$IP_REGEX" "$LOG_FILE" \
    | sort \
    | uniq -c \
    | sort -rn \
    | head -n 3 \
    | awk '{ printf "  %d. %-15s %s запросов\n", NR, $2, $1 }'

# 3. Ошибки 4xx и 5xx: код ответа — последнее поле строки
echo
read -r C4XX C5XX < <(awk '
    $NF ~ /^4[0-9][0-9]$/ { c4++ }
    $NF ~ /^5[0-9][0-9]$/ { c5++ }
    END { print c4+0, c5+0 }
' "$LOG_FILE")
echo "Запросов с кодами 4xx: $C4XX"
echo "Запросов с кодами 5xx: $C5XX"
echo "Всего ошибок (4xx+5xx): $(( C4XX + C5XX ))"

# Бонус: распределение по HTTP-методам (sed вырезает метод из кавычек)
echo
echo "Распределение по HTTP-методам:"
sed -nE 's/.*"([A-Z]+) [^ ]+ HTTP\/[0-9.]+".*/\1/p' "$LOG_FILE" \
    | sort | uniq -c | sort -rn \
    | awk '{ printf "  %-7s %s\n", $2, $1 }'
