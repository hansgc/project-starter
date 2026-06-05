#!/bin/bash

set -e

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║    Backup Docker Project Initializer     ║"
echo "╚══════════════════════════════════════════╝"
echo ""

mostrar_config_valores() {
  echo ""
  while IFS='=' read -r key value; do
    [[ "$key" =~ ^#.*$ || -z "$key" ]] && continue
    [[ "$key" == "PROJECT_NAME" ]] && continue
    key=$(echo "$key" | tr -d ' ')
    value=$(echo "$value" | tr -d '"' | tr -d "'" | sed 's/[[:space:]]*#.*//' | xargs)
    printf "  %s=%s\n" "$key" "$value"
  done < "$CONFIG_FILE"
  echo ""
}

step() {
  echo ""
  echo "$1"
}

verificar_red_docker() {
  local network_name=$1
  if docker network inspect "$network_name" >/dev/null 2>&1; then
    return 0  # La red existe
  else
    return 1  # La red NO existe
  fi
}

crear_red_docker() {
  local network_name=$1
  echo "Creando red Docker: $network_name"
  if docker network create "$network_name" >/dev/null 2>&1; then
    echo "  ✓ Red '$network_name' creada exitosamente."
    return 0
  else
    echo "  ❌ Error al crear la red '$network_name'."
    return 1
  fi
}

CONFIG_FILE="${1:-}"

bool() {
  [[ "${1,,}" =~ ^(true|si|sí|yes|1)$ ]]
}

probar_backblaze_b2() {
  if [[ -z "$B2_KEY_ID" || -z "$B2_APP_KEY" ]]; then
    echo "ERROR: No se proporcionaron las credenciales de Backblaze B2. Revisá B2_KEY_ID y B2_APP_KEY."
    return 1
  fi

  if ! command -v curl >/dev/null 2>&1; then
    echo "ERROR: curl no está instalado en este host. No se puede verificar Backblaze B2."
    return 1
  fi

  local temp_file
  temp_file=$(mktemp)
  local http_code
  http_code=$(curl -s -o "$temp_file" -w '%{http_code}' -u "$B2_KEY_ID:$B2_APP_KEY" https://api.backblazeb2.com/b2api/v2/b2_authorize_account)

  if [[ "$http_code" != "200" ]]; then
    echo "ERROR: No se pudo conectar a Backblaze B2 (código HTTP: $http_code)."
    echo "Revisá la red y las credenciales B2_KEY_ID/B2_APP_KEY."
    rm -f "$temp_file"
    return 1
  fi

  if ! grep -q '"authorizationToken"' "$temp_file"; then
    echo "ERROR: Respuesta inválida de Backblaze B2. Revisá las credenciales."
    rm -f "$temp_file"
    return 1
  fi

  rm -f "$temp_file"
  echo "Conexión a Backblaze B2 verificada correctamente."
  return 0
}

probar_mysql_network() {
  if [[ -z "$DB_NETWORK_DEV" ]]; then
    echo "ERROR: DB_NETWORK_DEV no está definido. No se puede verificar la red Docker de MySQL de desarrollo."
    return 1
  fi

  if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: Docker no está instalado en este host. No se puede verificar la red Docker."
    return 1
  fi

  if ! docker network inspect "$DB_NETWORK_DEV" >/dev/null 2>&1; then
    echo "ERROR: La red Docker de desarrollo '$DB_NETWORK_DEV' no existe."
    echo "Verificá que el contenedor MySQL esté en esa red."
    return 1
  fi

  echo "Verificando conexión a MySQL desde la red Docker '$DB_NETWORK_DEV'..."
  if ! docker run --rm --network "$DB_NETWORK_DEV" --entrypoint mysqladmin mysql:8.0 \
      ping -h"$DB_HOST_DEV" -P"$DB_PORT_DEV" -u"$DB_USER_DEV" -p"$DB_PASS_DEV" --silent >/dev/null 2>&1; then
    echo "ERROR: No se pudo conectar a MySQL desde la red Docker '$DB_NETWORK_DEV'."
    echo "Revisá que el contenedor MySQL esté levantado y que DB_HOST_DEV/DB_PORT_DEV sean correctos."
    return 1
  fi

  echo "Conexión a MySQL verificada en la red Docker '$DB_NETWORK_DEV'."
  return 0
}

if [[ -n "$CONFIG_FILE" ]]; then
  if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Error: no se encontró el archivo '$CONFIG_FILE'"
    exit 1
  fi

  echo "Leyendo configuración desde: $CONFIG_FILE"

  CONFIG_BASENAME=$(basename "$CONFIG_FILE" .conf)
  PROJECT_NAME=${CONFIG_BASENAME#project_}
  PROJECT_NAME=${PROJECT_NAME#backup_}
  if [[ -z "${PROJECT_NAME:-}" ]]; then
    echo "Error: PROJECT_NAME es obligatorio en el archivo de config.";
    exit 1
  fi

  while IFS='=' read -r key value; do
    [[ "$key" =~ ^#.*$ || -z "$key" ]] && continue
    [[ "$key" == "PROJECT_NAME" ]] && continue
    key=$(echo "$key" | tr -d ' ')
    value=$(echo "$value" | tr -d '"' | tr -d "'" | sed 's/[[:space:]]*#.*//' | xargs)
    declare "$key=$value"
    printf "  %s=%s\n" "$key" "$value"
  done < "$CONFIG_FILE"
  echo ""

  DB_HOST="${DB_HOST:-mysql}"
  DB_HOST_DEV="${DB_HOST_DEV:-${DB_HOST}}"
  DB_HOST_PROD="${DB_HOST_PROD:-${DB_HOST}}"
  DB_PORT_DEV="${DB_PORT_DEV:-3306}"
  DB_PORT_PROD="${DB_PORT_PROD:-3306}"
  DB_NAME="${DB_NAME:-app_db}"
  DB_NAME_DEV="${DB_NAME_DEV:-${DB_NAME}}"
  DB_NAME_PROD="${DB_NAME_PROD:-${DB_NAME}}"
  DB_USER="${DB_USER:-app_user}"
  DB_USER_DEV="${DB_USER_DEV:-${DB_USER}}"
  DB_USER_PROD="${DB_USER_PROD:-${DB_USER}}"
  DB_PASS="${DB_PASS:-secret_password}"
  DB_PASS_DEV="${DB_PASS_DEV:-${DB_PASS}}"
  DB_PASS_PROD="${DB_PASS_PROD:-${DB_PASS}}"
  CLIENTE_ID="${CLIENTE_ID:-mi-cliente}"
  DB_NETWORK="${DB_NETWORK:-app_network}"
  DB_NETWORK_DEV="${DB_NETWORK_DEV:-}"
  DB_NETWORK_PROD="${DB_NETWORK_PROD:-}"

  PROJECT_SLUG=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g')
  PROJECT_FOLDER="${PROJECT_SLUG}-backup"

  # Si no se definieron directamente, calcularlas desde DB_NETWORK
  DB_NETWORK="${DB_NETWORK:-app_network}"
  DB_NETWORK_DEV="${DB_NETWORK_DEV:-${DB_NETWORK}_dev}"
  DB_NETWORK_PROD="${DB_NETWORK_PROD:-${DB_NETWORK}_prod}"

  B2_KEY_ID="${B2_KEY_ID:-}"
  B2_APP_KEY="${B2_APP_KEY:-}"
  B2_BUCKET="${B2_BUCKET:-backup-cliente}"
  BACKUP_SCHEDULE="${BACKUP_SCHEDULE:-0 * * * *}"
  PORT_DEV="${PORT_DEV:-8080}"
  PORT_PROD="${PORT_PROD:-80}"
  PROD_SERVER_IP="${PROD_SERVER_IP:-}"

  mostrar_config_valores

step "Verificando red y conexión a MySQL"
if ! probar_mysql_network; then
  echo "ERROR: No se puede continuar sin una conexión funcional a MySQL en la red Docker especificada."
  exit 1
fi

step "Verificando conexión a Backblaze B2"
if ! probar_backblaze_b2; then
  echo "ERROR: No se puede continuar sin una conexión funcional a Backblaze B2."
  exit 1
fi

# --- Verificar redes Docker ---
step "Verificando redes Docker"
for network in "$DB_NETWORK_DEV" "$DB_NETWORK_PROD"; do
  if ! verificar_red_docker "$network"; then
    echo "  ⚠ La red Docker '$network' no existe."
    echo "  Creando red automáticamente..."
    if crear_red_docker "$network"; then
      echo "  ✓ Red '$network' creada."
    else
      echo "  ❌ No se pudo crear la red '$network'. Por favor, créala manualmente con:"
      echo "     docker network create $network"
      exit 1
    fi
  else
    echo "  ✓ La red '$network' existe."
  fi
done

step "Creando estructura de directorios"

mkdir -p "$PROJECT_FOLDER"
cd "$PROJECT_FOLDER"

mkdir -p .devcontainer
mkdir -p aDespliegue/dev
mkdir -p aDespliegue/prod
mkdir -p app

step "Generando Dockerfile dev"

cat > aDespliegue/dev/Dockerfile <<'DOCKERFILE'
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    default-mysql-client \
    cron \
    curl \
    gzip \
    python3 \
    python3-pip \
    && pip3 install b2 --break-system-packages \
    && rm -rf /var/lib/apt/lists/*

COPY app/backup.sh /usr/local/bin/backup.sh
COPY app/crontab /etc/cron.d/backup-cron
COPY app/entrypoint.sh /entrypoint.sh

RUN chmod +x /usr/local/bin/backup.sh \
    && chmod +x /entrypoint.sh \
    && chmod 0644 /etc/cron.d/backup-cron \
    && crontab /etc/cron.d/backup-cron

RUN mkdir -p /backups/pendientes /backups/enviados

ENTRYPOINT ["/entrypoint.sh"]
DOCKERFILE

step "Generando docker-compose.yml dev"

cat > aDespliegue/dev/docker-compose.yml <<YAML
services:
  backup:
    build:
      context: ../..
      dockerfile: aDespliegue/dev/Dockerfile
    container_name: ${PROJECT_SLUG}-backup-dev
    image: ${PROJECT_SLUG}-backup-dev
    restart: "no"
    env_file: .env
    ports:
      - "${PORT_DEV}:${PORT_DEV}"
    volumes:
      - ../../:/workspace:cached
      - backup_data:/backups
    networks:
      - "\${DB_NETWORK_DEV}"

volumes:
  backup_data:

networks:
  \${DB_NETWORK_DEV}:
    name: "\${DB_NETWORK_DEV}"
    external: true
YAML

step "Generando Dockerfile prod"

cat > aDespliegue/prod/Dockerfile <<'DOCKERFILE'
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    default-mysql-client \
    cron \
    curl \
    gzip \
    python3 \
    python3-pip \
    && pip3 install b2 --break-system-packages \
    && rm -rf /var/lib/apt/lists/*

COPY app/backup.sh /usr/local/bin/backup.sh
COPY app/crontab /etc/cron.d/backup-cron
COPY app/entrypoint.sh /entrypoint.sh

RUN chmod +x /usr/local/bin/backup.sh \
    && chmod +x /entrypoint.sh \
    && chmod 0644 /etc/cron.d/backup-cron \
    && crontab /etc/cron.d/backup-cron

RUN mkdir -p /backups/pendientes /backups/enviados

ENTRYPOINT ["/entrypoint.sh"]
DOCKERFILE

step "Generando docker-compose.yml prod"

cat > aDespliegue/prod/docker-compose.yml <<YAML
services:
  backup:
    build:
      context: ../..
      dockerfile: aDespliegue/prod/Dockerfile
    container_name: ${PROJECT_SLUG}-backup-prod
    image: ${PROJECT_SLUG}-backup-prod
    restart: unless-stopped
    env_file: .env
    volumes:
      - backup_data_prod:/backups
    networks:
      - "\${DB_NETWORK_PROD}"

volumes:
  backup_data_prod:

networks:
  \${DB_NETWORK_PROD}:
    name: "\${DB_NETWORK_PROD}"
    external: true
YAML

step "Generando .devcontainer"

cat > .devcontainer/devcontainer.json <<JSON
{
  "name": "${PROJECT_NAME} Backup",
  "dockerComposeFile": ["../aDespliegue/dev/docker-compose.yml"],
  "service": "backup",
  "workspaceFolder": "/workspace",
  "remoteUser": "root",
  "shutdownAction": "stopCompose",
  "customizations": {
    "vscode": {
      "extensions": [
        "ms-azuretools.vscode-docker"
      ]
    }
  }
}
JSON

step "Generando variables de entorno (.env)"

cat > aDespliegue/dev/.env.example <<ENV
# Configuración de MySQL
# Aquí puedes usar el nombre del contenedor MySQL dentro de la red Docker compartida.
DB_HOST=${DB_HOST_DEV}
DB_PORT_DEV=${DB_PORT_DEV}
DB_NAME=${DB_NAME_DEV}
DB_USER=${DB_USER_DEV}
DB_PASS=YOUR_DB_PASSWORD

# Red Docker donde está el contenedor MySQL
DB_NETWORK_DEV=${DB_NETWORK_DEV}

# Identificación del cliente
CLIENTE_ID=${CLIENTE_ID}

# Backblaze B2
B2_KEY_ID=YOUR_B2_KEY_ID
B2_APP_KEY=YOUR_B2_APP_KEY
B2_BUCKET=${B2_BUCKET}

# Puertos
PORT_DEV=8080

# Schedule de Cron (expresión cron)
BACKUP_SCHEDULE=${BACKUP_SCHEDULE}
ENV

cat > aDespliegue/dev/.env <<ENV
# Configuración de MySQL
DB_HOST=${DB_HOST_DEV}
DB_PORT_DEV=${DB_PORT_DEV}
DB_NAME=${DB_NAME_DEV}
DB_USER=${DB_USER_DEV}
DB_PASS=${DB_PASS_DEV}

# Red Docker donde está el contenedor MySQL
DB_NETWORK_DEV=${DB_NETWORK_DEV}

# Identificación del cliente
CLIENTE_ID=${CLIENTE_ID}

# Backblaze B2
B2_KEY_ID=${B2_KEY_ID}
B2_APP_KEY=${B2_APP_KEY}
B2_BUCKET=${B2_BUCKET}

# Puertos
PORT_DEV=${PORT_DEV}

# Schedule de Cron (expresión cron)
BACKUP_SCHEDULE=${BACKUP_SCHEDULE}
ENV

cat > aDespliegue/prod/.env.example <<ENV
# Configuración de MySQL
# Aquí puedes usar el nombre del contenedor MySQL dentro de la red Docker compartida.
DB_HOST=${DB_HOST_PROD}
DB_PORT_PROD=${DB_PORT_PROD}
DB_NAME=${DB_NAME_PROD}
DB_USER=${DB_USER_PROD}
DB_PASS=YOUR_DB_PASSWORD

# Red Docker donde está el contenedor MySQL
DB_NETWORK_PROD=${DB_NETWORK_PROD}

# Identificación del cliente
CLIENTE_ID=${CLIENTE_ID}

# Backblaze B2
B2_KEY_ID=YOUR_B2_KEY_ID
B2_APP_KEY=YOUR_B2_APP_KEY
B2_BUCKET=${B2_BUCKET}

# Puertos
PORT_PROD=80

# Servidor de producción (opcional)
PROD_SERVER_IP=

# Schedule de Cron (expresión cron)
BACKUP_SCHEDULE=${BACKUP_SCHEDULE}
ENV

cat > aDespliegue/prod/.env <<ENV
# Configuración de MySQL
DB_HOST=${DB_HOST_PROD}
DB_PORT_PROD=${DB_PORT_PROD}
DB_NAME=${DB_NAME_PROD}
DB_USER=${DB_USER_PROD}
DB_PASS=${DB_PASS_PROD}

# Red Docker donde está el contenedor MySQL
DB_NETWORK_PROD=${DB_NETWORK_PROD}

# Identificación del cliente
CLIENTE_ID=${CLIENTE_ID}

# Backblaze B2
B2_KEY_ID=${B2_KEY_ID}
B2_APP_KEY=${B2_APP_KEY}
B2_BUCKET=${B2_BUCKET}

# Puertos
PORT_PROD=${PORT_PROD}

# Servidor de producción (opcional)
PROD_SERVER_IP=${PROD_SERVER_IP}

# Schedule de Cron (expresión cron)
BACKUP_SCHEDULE=${BACKUP_SCHEDULE}
ENV

step "Generando entrypoint.sh"

cat > app/entrypoint.sh <<'ENTRYPOINT'
#!/bin/bash
set -e

echo "[ENTRYPOINT] Contenedor de backup iniciado."

echo "[ENTRYPOINT] Autenticando con Backblaze B2..."
b2 authorize-account "$B2_KEY_ID" "$B2_APP_KEY"

if [ $? -ne 0 ]; then
    echo "[ENTRYPOINT] ERROR: No se pudo autenticar con Backblaze B2."
    echo "[ENTRYPOINT] Verifica B2_KEY_ID y B2_APP_KEY en el .env"
    exit 1
fi

echo "[ENTRYPOINT] Ejecutando backup inicial..."
/usr/local/bin/backup.sh

echo "[ENTRYPOINT] Iniciando cron..."
cron -f
ENTRYPOINT

chmod +x app/entrypoint.sh

step "Generando crontab"

cat > app/crontab <<CRONTAB
${BACKUP_SCHEDULE} root /usr/local/bin/backup.sh >> /var/log/backup.log 2>&1
CRONTAB

step "Generando backup.sh"

cat > app/backup.sh <<'BACKUP'
#!/bin/bash

LOG="/var/log/backup.log"
DIR_PENDIENTES="/backups/pendientes"
DIR_ENVIADOS="/backups/enviados"

mkdir -p "$DIR_PENDIENTES" "$DIR_ENVIADOS"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG"
}

hubo_cambios() {
    RESULTADO=$(mysql \
        --host="$DB_HOST" \
        --port="$DB_PORT_DEV" \
        --user="$DB_USER" \
        --password="$DB_PASS" \
        --silent --skip-column-names \
        -e "SELECT CASE WHEN ultimo_backup IS NULL THEN 'SI' WHEN ultima_transaccion > ultimo_backup THEN 'SI' ELSE 'NO' END FROM backup_auditoria LIMIT 1;" 2>/dev/null)

    if [ "$RESULTADO" = "SI" ]; then
        return 0
    fi
    return 1
}

generar_backup() {
    FECHA=$(date +%Y%m%d_%H%M%S)
    ARCHIVO="${DIR_PENDIENTES}/backup_${DB_NAME}_${FECHA}.sql.gz"

    log "Generando backup: $(basename "$ARCHIVO")"

    if ! mysqldump \
        --host="$DB_HOST" \
        --port="$DB_PORT_DEV" \
        --user="$DB_USER" \
        --password="$DB_PASS" \
        --single-transaction \
        --routines \
        --triggers \
        "$DB_NAME" | gzip > "$ARCHIVO"; then
        log "ERROR: Falló el mysqldump. Se elimina archivo corrupto."
        rm -f "$ARCHIVO"
        return 1
    fi

    TAMANIO=$(du -sh "$ARCHIVO" | cut -f1)
    log "Backup generado. Tamaño: $TAMANIO"

    if ! mysql \
        --host="$DB_HOST" \
        --port="$DB_PORT_DEV" \
        --user="$DB_USER" \
        --password="$DB_PASS" \
        -e "UPDATE backup_auditoria SET ultimo_backup = NOW() LIMIT 1;" 2>/dev/null; then
        log "WARNING: No se pudo actualizar backup_auditoria."
    fi

    return 0
}

hay_conexion() {
    curl -s --max-time 10 https://www.backblaze.com > /dev/null 2>&1
    return $?
}

enviar_pendientes() {
    mapfile -t PENDIENTES < <(find "$DIR_PENDIENTES" -maxdepth 1 -name 'backup_*.sql.gz' -print)

    if [ ${#PENDIENTES[@]} -eq 0 ]; then
        log "No hay backups pendientes de envío."
        return 0
    fi

    if ! hay_conexion; then
        log "Sin internet. ${#PENDIENTES[@]} backup(s) pendiente(s) en cola."
        return 1
    fi

    b2 authorize-account "$B2_KEY_ID" "$B2_APP_KEY" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        log "ERROR: No se pudo reautenticar con Backblaze B2."
        return 1
    fi

    log "Enviando ${#PENDIENTES[@]} backup(s) a Backblaze B2..."

    for ARCHIVO in "${PENDIENTES[@]}"; do
        NOMBRE=$(basename "$ARCHIVO")
        log "Enviando: $NOMBRE"

        if b2 upload-file "$B2_BUCKET" "$ARCHIVO" "$NOMBRE"; then
            log "OK enviado: $NOMBRE"
            mv "$ARCHIVO" "$DIR_ENVIADOS/"
            echo "$(date '+%Y-%m-%d %H:%M:%S') - $NOMBRE" >> "$DIR_ENVIADOS/enviados.log"
        else
            log "ERROR al enviar: $NOMBRE. Se reintentará en el próximo ciclo."
        fi
    done
}

limpiar_antiguos() {
    ELIMINADOS=$(find "$DIR_ENVIADOS" -maxdepth 1 -name 'backup_*.sql.gz' -mtime +30 -print | wc -l)
    if [ "$ELIMINADOS" -gt 0 ]; then
        find "$DIR_ENVIADOS" -maxdepth 1 -name 'backup_*.sql.gz' -mtime +30 -delete
        log "Limpieza local: $ELIMINADOS archivo(s) eliminado(s)."
    fi

    if ! b2 authorize-account "$B2_KEY_ID" "$B2_APP_KEY" > /dev/null 2>&1; then
        log "WARNING: No se pudo reautenticar con Backblaze B2 para limpieza remota."
        return
    fi

    HACE30=$(date -d '30 days ago' +%Y%m%d)
    b2 ls "$B2_BUCKET" 2>/dev/null | while read -r NOMBRE_REMOTO FILE_ID; do
        FECHA=$(echo "$NOMBRE_REMOTO" | grep -oP '\\d{8}' | head -1)
        if [ -n "$FECHA" ] && [ "$FECHA" -lt "$HACE30" ]; then
            if b2 delete-file-version "$NOMBRE_REMOTO" "$FILE_ID" > /dev/null 2>&1; then
                log "Eliminado de B2: $NOMBRE_REMOTO"
            else
                log "ERROR al eliminar de B2: $NOMBRE_REMOTO"
            fi
        fi
    done
}

log "===== Iniciando ciclo de backup ====="

log "Verificando conexión a MySQL..."
if ! mysql --host="$DB_HOST" --port="$DB_PORT_DEV" --user="$DB_USER" --password="$DB_PASS" -e "SELECT 1;" > /dev/null 2>&1; then
    log "ERROR: No hay conexión a MySQL."
    exit 1
fi

if hubo_cambios; then
    log "Cambios detectados en la base de datos."
    generar_backup
else
    log "Sin cambios desde el último backup. No se genera archivo."
fi

enviar_pendientes
limpiar_antiguos

log "===== Ciclo finalizado ====="
BACKUP

chmod +x app/backup.sh

step "Generando Makefile"

cat > Makefile <<'MAKE'
.PHONY: help logs logs-backup sh backup-now backup-logs up-dev down-dev up-prod down-prod build-dev build-prod

help:
	@echo "Comandos disponibles:"
	@echo "  make help                - Muestra esta ayuda"
	@echo "  make up-{dev|prod}       - Levanta el ambiente de desarrollo/producción"
	@echo "  make down-{dev|prod}     - Detiene el ambiente de desarrollo/producción"
	@echo "  make build-{dev|prod}    - Reconstruye el ambiente de desarrollo/producción"
	@echo "  make logs-{dev|prod}     - Muestra los logs en tiempo real"
	@echo "  make logs-backup-{dev|prod} - Muestra los logs del servicio backup"
	@echo "  make sh-{dev|prod}       - Accede al shell del contenedor backup"
	@echo "  make backup-now-{dev|prod} - Ejecuta un backup inmediato"
	@echo "  make backup-logs-{dev|prod} - Muestra los logs de backup del contenedor"

up-dev:
	cd aDespliegue/dev && docker compose up -d

down-dev:
	cd aDespliegue/dev && docker compose down

build-dev:
	cd aDespliegue/dev && docker compose build --no-cache

up-prod:
	cd aDespliegue/prod && docker compose up -d

down-prod:
	cd aDespliegue/prod && docker compose down

build-prod:
	cd aDespliegue/prod && docker compose build --no-cache

logs-dev:
	cd aDespliegue/dev && docker compose logs -f

logs-prod:
	cd aDespliegue/prod && docker compose logs -f

logs-backup-dev:
	cd aDespliegue/dev && docker compose logs -f backup

logs-backup-prod:
	cd aDespliegue/prod && docker compose logs -f backup

sh-dev:
	cd aDespliegue/dev && docker compose exec backup bash

sh-prod:
	cd aDespliegue/prod && docker compose exec backup bash

backup-now-dev:
	cd aDespliegue/dev && docker compose exec backup /usr/local/bin/backup.sh

backup-now-prod:
	cd aDespliegue/prod && docker compose exec backup /usr/local/bin/backup.sh

backup-logs-dev:
	cd aDespliegue/dev && docker compose exec backup tail -f /var/log/backup.log

backup-logs-prod:
	cd aDespliegue/prod && docker compose exec backup tail -f /var/log/backup.log
MAKE

step "Generando README.md"

cat > README.md <<'README'
# Proyecto Backup Automático con Backblaze B2

Sistema automático de backup de base de datos MySQL con envío directo a Backblaze B2.

## Estructura

```
${PROJECT_FOLDER}/
├── .devcontainer/
├── aDespliegue/dev/
│   ├── docker-compose.yml
│   ├── Dockerfile
│   ├── .env
│   └── .env.example
├── aDespliegue/prod/
│   ├── docker-compose.yml
│   ├── Dockerfile
│   ├── .env
│   └── .env.example
├── app/
│   ├── backup.sh
│   ├── entrypoint.sh
│   └── crontab
├── Makefile
├── README.md
└── .gitignore
```

## Uso

1. Si no lo hiciste, edita `.env` con tus credenciales reales.
2. Genera el bucket Backblaze B2 y confirma su nombre en `B2_BUCKET`.
3. Asegúrate de que el contenedor MySQL ya existe y está conectado a la red Docker configurada en `DB_NETWORK`.
   Usa el nombre del contenedor MySQL como `DB_HOST`.
4. Ejecuta:

```bash
make up
```

Para producción:

```bash
make up-prod
```

5. Verifica logs:

```bash
make logs-backup
```

## Variables de entorno necesarias

- `DB_HOST`
- `DB_PORT_DEV`
- `DB_PORT_PROD`
- `DB_NAME`
- `DB_USER`
- `DB_PASS`
- `DB_NETWORK`
- `CLIENTE_ID`
- `B2_KEY_ID`
- `B2_APP_KEY`
- `B2_BUCKET`
- `BACKUP_SCHEDULE`

## Funcionamiento

- Detecta cambios en `backup_auditoria`
- Genera backup comprimido solo si hay cambios
- Guarda pendientes en `/backups/pendientes`
- Envía a Backblaze B2 cuando hay conexión
- Mueve enviados a `/backups/enviados`
- Limpia backups locales y remotos de más de 30 días
README

step "Generando .gitignore"

cat > .gitignore <<'GITIGNORE'
aDespliegue/dev/.env
aDespliegue/prod/.env
backups/
/var/log/backup.log
*.sql.gz
GITIGNORE

step "Generando leeme.txt"

{
  echo "desarrollo:"
  echo "-----------"
  echo "make up"
  echo "http://localhost:${PORT_DEV}"
  echo ""
  echo "producción:"
  echo "-----------"
  if [[ -n \"${PROD_SERVER_IP}\" ]]; then
    echo "http://${PROD_SERVER_IP}:${PORT_PROD}"
  else
    echo "http://localhost:${PORT_PROD}"
  fi
} > leeme.txt

step "Finalizado"

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║   ✅  ${PROJECT_NAME} listo!              "
echo "╚══════════════════════════════════════════╝"
echo ""
echo "  Estructura creada:"
echo "    ${PROJECT_FOLDER}/"
echo "    ├── aDespliegue/dev/
    │   ├── docker-compose.yml
    │   ├── .env
    │   └── Dockerfile
    ├── aDespliegue/prod/
    │   ├── docker-compose.yml
    │   ├── .env
    │   └── Dockerfile
    ├── app/
    ├── Makefile
    ├── leeme.txt
    └── README.md"
echo ""
echo "  Configuración:"
echo "    MySQL Host:       ${DB_HOST}"
echo "    MySQL Port dev:   ${DB_PORT_DEV}"
echo "    MySQL Port prod:  ${DB_PORT_PROD}"
echo "    Database:         ${DB_NAME}"
echo "    Usuario:          ${DB_USER}"
echo "    DB Network:       ${DB_NETWORK}"
echo "    Cliente ID:       ${CLIENTE_ID}"
echo "    Backblaze Bucket: ${B2_BUCKET}"
echo "    Cron Schedule:    ${BACKUP_SCHEDULE}"
echo "    Carpeta creada:   ${PROJECT_FOLDER}"
echo ""
echo "  Próximos pasos:"
echo "    1. Ejecuta: make up"
echo "    2. Revisa logs: make logs-backup"
echo ""

fi
