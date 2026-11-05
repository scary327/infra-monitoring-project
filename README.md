# infra-monitoring-project

Мониторинг доступности echo-API, анализ логов доступа и контейнеризированная
среда развёртывания (nginx → http-echo).

## Структура проекта

```
.
├── .github/workflows/ci.yml   # CI: проверка скриптов и docker-стека
├── nginx/nginx.conf           # конфиг reverse-proxy
├── analyze_logs.sh            # генерация и анализ access.log
├── check_api.sh               # проверка доступности API
├── docker-compose.yml         # стек api + proxy
└── README.md
```

## Требования

- bash 4+, curl, grep, awk, sed, sort, uniq
- Docker и Docker Compose v2
- (для анализа трафика) Wireshark

## Быстрый старт

```bash
git clone https://github.com/<username>/infra-monitoring-project.git
cd infra-monitoring-project
chmod +x check_api.sh analyze_logs.sh

docker compose up -d
curl http://localhost:80            # -> Monitoring Service Active
./check_api.sh http://localhost:80  # -> API доступен
```

## check_api.sh — мониторинг API

```bash
./check_api.sh <URL> [ожидаемый_код]
```

- делает запрос через `curl` и сравнивает HTTP-код с ожидаемым (по умолчанию `200`);
- выводит `API доступен` или `API недоступен, код ответа: XXX`;
- код возврата `0` — успех, `1` — ошибка (в т.ч. неверные аргументы);
- таймаут задаётся переменной `CHECK_API_TIMEOUT` (по умолчанию 10 с).

```bash
$ ./check_api.sh https://httpbin.org/status/200
API доступен
$ echo $?
0

$ ./check_api.sh https://httpbin.org/status/404
API недоступен, код ответа: 404
$ echo $?
1

$ ./check_api.sh http://nonexistent.invalid
API недоступен, код ответа: 000 (ошибка curl: 6)
```

## analyze_logs.sh — анализ логов

```bash
./analyze_logs.sh [-f файл] [-n кол-во_строк] [-s]
```

| Опция | Описание |
|-------|----------|
| `-f FILE` | путь к лог-файлу (по умолчанию `access.log`) |
| `-n N` | сколько строк сгенерировать (по умолчанию 500, минимум 300) |
| `-s` | не генерировать, а анализировать существующий файл |

Скрипт генерирует `access.log` в формате

```
192.168.1.10 - - [15/Aug/2026:10:15:32] "GET /api/users HTTP/1.1" 200
```

и с помощью `grep -E`, `awk`, `sed`, `sort`, `uniq` выводит:

- общее количество запросов;
- топ-3 IP-адресов (IP извлекаются регулярным выражением `^([0-9]{1,3}\.){3}[0-9]{1,3}`);
- количество ответов 4xx и 5xx;
- распределение по HTTP-методам.

## Docker Compose

| Сервис | Образ | Назначение |
|--------|-------|-----------|
| `api` | `hashicorp/http-echo` | отвечает `Monitoring Service Active` на порту 8080 (только внутри сети) |
| `proxy` | `nginx:alpine` | слушает порт 80 хоста и проксирует на `api:8080` |

Контейнеры общаются через пользовательскую bridge-сеть `monitoring-net`;
nginx находит сервис `api` по имени через встроенный DNS Docker.

```bash
docker compose up -d      # запуск
docker compose ps         # статус контейнеров
docker compose logs -f    # логи
docker compose down       # остановка
```

## CI/CD

Workflow `.github/workflows/ci.yml` запускается на Pull Request в `main`
(а также на push в `feature/monitoring`) и выполняет:

1. `bash -n` для обоих скриптов + ShellCheck;
2. `check_api.sh https://httpbin.org/status/200` — ожидается код возврата 0;
3. негативные тесты `check_api.sh` (несуществующий хост, невалидный URL) — ожидается 1;
4. генерацию и анализ лога `analyze_logs.sh`;
5. валидацию `docker-compose.yml`, запуск стека и smoke-тест через прокси.

## Git workflow

- `main` — защищённая ветка (изменения только через Pull Request);
- `feature/monitoring` — рабочая ветка, из неё открывается PR в `main`.

## Деплой на удалённый сервер (SSH / SCP)

### 1. Генерация SSH-ключа

```bash
ssh-keygen -t ed25519 -C "deploy@infra-monitoring" -f ~/.ssh/infra_deploy
```

Создаются приватный ключ `~/.ssh/infra_deploy` (никому не передаётся) и
публичный `~/.ssh/infra_deploy.pub`. Рекомендуется задать passphrase.

### 2. Копирование публичного ключа на сервер

```bash
ssh-copy-id -i ~/.ssh/infra_deploy.pub deploy@203.0.113.10
```

Если `ssh-copy-id` недоступен (например, на Windows):

```bash
cat ~/.ssh/infra_deploy.pub | ssh deploy@203.0.113.10 \
  "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

Проверка входа по ключу:

```bash
ssh -i ~/.ssh/infra_deploy deploy@203.0.113.10
```

Удобно прописать хост в `~/.ssh/config`:

```
Host infra
    HostName 203.0.113.10
    User deploy
    IdentityFile ~/.ssh/infra_deploy
```

После этого на сервере стоит отключить вход по паролю
(`PasswordAuthentication no` в `/etc/ssh/sshd_config`).

### 3. Передача проекта

**Вариант А — архив + scp:**

```bash
tar -czf infra-monitoring.tar.gz --exclude=.git --exclude='*.log' .
scp infra-monitoring.tar.gz infra:/opt/
ssh infra "mkdir -p /opt/infra-monitoring && tar -xzf /opt/infra-monitoring.tar.gz -C /opt/infra-monitoring && rm /opt/infra-monitoring.tar.gz"
```

**Вариант Б — tar + ssh одним потоком (без временного файла):**

```bash
tar -czf - --exclude=.git --exclude='*.log' . \
  | ssh infra "mkdir -p /opt/infra-monitoring && tar -xzf - -C /opt/infra-monitoring"
```

**Вариант В — копирование каталога целиком:**

```bash
scp -r docker-compose.yml nginx check_api.sh infra:/opt/infra-monitoring/
```

### 4. Запуск на сервере

```bash
ssh infra "cd /opt/infra-monitoring && docker compose pull && docker compose up -d && docker compose ps"
ssh infra "/opt/infra-monitoring/check_api.sh http://localhost:80"
```
