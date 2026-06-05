#!/bin/bash

set -e

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║      MySQL Docker Project Initializer    ║"
echo "╚══════════════════════════════════════════╝"
echo ""

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

if [[ -n "$CONFIG_FILE" ]]; then
  # --- Modo archivo ---
  if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Error: no se encontró el archivo '$CONFIG_FILE'"; exit 1
  fi

  echo "Leyendo configuración desde: $CONFIG_FILE"

  # Cargar variables ignorando comentarios y líneas vacías
  echo ""
  while IFS='=' read -r key value; do
    [[ "$key" =~ ^#.*$ || -z "$key" ]] && continue
    key=$(echo "$key" | tr -d ' ')
    value=$(echo "$value" | tr -d '"' | tr -d "'" | sed 's/[[:space:]]*#.*//' | xargs)
    declare "$key=$value"
    printf "  %s=%s\n" "$key" "$value"
  done < "$CONFIG_FILE"
  echo ""

  CONFIG_BASENAME=$(basename "$CONFIG_FILE" .conf)
  PROJECT_NAME=${CONFIG_BASENAME#project_}
  if [[ -z "${PROJECT_NAME:-}" ]]; then
    PROJECT_NAME="mysql-project"
  fi

  MYSQL_VERSION="${MYSQL_VERSION:-8.0}"
  MYSQL_PORT_DEV="${MYSQL_PORT_DEV:-${MYSQL_PORT:-3306}}"
  MYSQL_PORT_PROD="${MYSQL_PORT_PROD:-3306}"
  PROD_SERVER_IP="${PROD_SERVER_IP:-}"
  DB_NAME="${DB_NAME:-app_db}"
  DB_USER="${DB_USER:-app_user}"
  DB_PASSWORD="${DB_PASSWORD:-secret_password}"
  DB_ROOT_PASSWORD="${DB_ROOT_PASSWORD:-secret_root_password}"
  DB_NETWORK="${DB_NETWORK:-}"

PROJECT_SLUG=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g')
DB_NETWORK="${DB_NETWORK:-${PROJECT_SLUG}_net}"
DB_NETWORK_DEV="${DB_NETWORK}_dev"
DB_NETWORK_PROD="${DB_NETWORK}_prod"

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

# --- Crear estructura de directorios ---
step "Creando estructura de directorios"

mkdir -p "$PROJECT_SLUG"
cd "$PROJECT_SLUG"

mkdir -p .devcontainer
mkdir -p aDespliegue/dev
mkdir -p aDespliegue/prod

# --- aDespliegue/dev/docker-compose.yml ---
step "Generando docker-compose.yml dev"

cat > aDespliegue/dev/docker-compose.yml <<YAML
services:
  ${PROJECT_SLUG}_db_dev:
    image: mysql:${MYSQL_VERSION}
    container_name: ${PROJECT_SLUG}_db_dev
    restart: "no"
    env_file: .env
    environment:
      MYSQL_ROOT_PASSWORD: "\${DB_ROOT_PASSWORD}"
      MYSQL_DATABASE: "\${DB_NAME}"
      MYSQL_USER: "\${DB_USER}"
      MYSQL_PASSWORD: "\${DB_PASSWORD}"
    ports:
      - "\${MYSQL_PORT_DEV}:3306"
    volumes:
      - ${PROJECT_SLUG}_db_data:/var/lib/mysql
    networks:
      - "\${DB_NETWORK_DEV}"

  dev:
    image: mcr.microsoft.com/devcontainers/base:debian
    container_name: ${PROJECT_SLUG}_dev
    command: sleep infinity
    volumes:
      - ../../:/workspace:cached
    networks:
      - "\${DB_NETWORK_DEV}"

volumes:
  ${PROJECT_SLUG}_db_data:
    name: ${PROJECT_SLUG}_db_data

networks:
  \${DB_NETWORK_DEV}:
    name: "\${DB_NETWORK_DEV}"
    external: true
YAML

# --- aDespliegue/prod/docker-compose.yml ---
step "Generando docker-compose.yml prod"

cat > aDespliegue/prod/docker-compose.yml <<YAML
services:
  ${PROJECT_SLUG}_db_prod:
    image: mysql:${MYSQL_VERSION}
    container_name: ${PROJECT_SLUG}_db_prod
    restart: unless-stopped
    env_file: .env
    environment:
      MYSQL_ROOT_PASSWORD: "\${DB_ROOT_PASSWORD}"
      MYSQL_DATABASE: "\${DB_NAME}"
      MYSQL_USER: "\${DB_USER}"
      MYSQL_PASSWORD: "\${DB_PASSWORD}"
    ports:
      - "\${MYSQL_PORT_PROD}:3306"
    volumes:
      - ${PROJECT_SLUG}_db_data_prod:/var/lib/mysql
    networks:
      - "\${DB_NETWORK_PROD}"

volumes:
  ${PROJECT_SLUG}_db_data_prod:
    name: ${PROJECT_SLUG}_db_data_prod

networks:
  \${DB_NETWORK_PROD}:
    name: "\${DB_NETWORK_PROD}"
    external: true
YAML

# --- Generando .devcontainer ---
step "Generando .devcontainer"

cat > .devcontainer/devcontainer.json <<JSON
{
  "name": "${PROJECT_NAME} MySQL",
  "dockerComposeFile": ["../aDespliegue/dev/docker-compose.yml"],
  "service": "dev",
  "workspaceFolder": "/workspace",
  "shutdownAction": "stopCompose",
  "customizations": {
    "vscode": {
      "extensions": [
        "mtxr.sqltools",
        "mtxr.sqltools-driver-mysql"
      ]
    }
  }
}
JSON

# --- Generando .env y .env.example ---
step "Generando variables de entorno (.env)"

cat > aDespliegue/dev/.env.example <<ENV
MYSQL_VERSION=${MYSQL_VERSION}
MYSQL_PORT_DEV=${MYSQL_PORT_DEV}
DB_NAME=${DB_NAME}
DB_USER=${DB_USER}
DB_PASSWORD=YOUR_DB_PASSWORD
DB_ROOT_PASSWORD=YOUR_ROOT_PASSWORD
DB_NETWORK_DEV=${DB_NETWORK_DEV}
ENV

cat > aDespliegue/dev/.env <<ENV
MYSQL_VERSION=${MYSQL_VERSION}
MYSQL_PORT_DEV=${MYSQL_PORT_DEV}
DB_NAME=${DB_NAME}
DB_USER=${DB_USER}
DB_PASSWORD=${DB_PASSWORD}
DB_ROOT_PASSWORD=${DB_ROOT_PASSWORD}
DB_NETWORK_DEV=${DB_NETWORK_DEV}
ENV

cat > aDespliegue/prod/.env.example <<ENV
MYSQL_VERSION=${MYSQL_VERSION}
MYSQL_PORT_PROD=${MYSQL_PORT_PROD}
PROD_SERVER_IP=
DB_NAME=${DB_NAME}
DB_USER=${DB_USER}
DB_PASSWORD=YOUR_DB_PASSWORD
DB_ROOT_PASSWORD=YOUR_ROOT_PASSWORD
DB_NETWORK_PROD=${DB_NETWORK_PROD}
ENV

cat > aDespliegue/prod/.env <<ENV
MYSQL_VERSION=${MYSQL_VERSION}
MYSQL_PORT_PROD=${MYSQL_PORT_PROD}
PROD_SERVER_IP=${PROD_SERVER_IP}
DB_NAME=${DB_NAME}
DB_USER=${DB_USER}
DB_PASSWORD=${DB_PASSWORD}
DB_ROOT_PASSWORD=${DB_ROOT_PASSWORD}
DB_NETWORK_PROD=${DB_NETWORK_PROD}
ENV

# --- Generando Makefile ---
step "Generando Makefile"

cat > Makefile <<MAKE
.PHONY: help start stop logs sh mysql mysql-root backup restore up-dev down-dev up-prod down-prod

MYSQL_SERVICE_dev = ${PROJECT_SLUG}_db_dev
MYSQL_SERVICE_prod = ${PROJECT_SLUG}_db_prod

help:
	@echo "Comandos disponibles:"
	@echo "  make help             - Muestra esta ayuda"
	@echo "  make up-{dev|prod}    - Levanta el ambiente de desarrollo/producción"
	@echo "  make down-{dev|prod}  - Detiene el ambiente de desarrollo/producción"
	@echo "  make logs-{dev|prod}  - Muestra los logs en tiempo real"
	@echo "  make sh-{dev|prod}    - Accede al shell del contenedor MySQL"
	@echo "  make mysql-{dev|prod} - Accede a MySQL con usuario normal"
	@echo "  make mysql-root-{dev|prod} - Accede a MySQL como root"
	@echo "  make backup-{dev|prod} - Realiza un backup de la base de datos"
	@echo "  make restore-{dev|prod} - Restaura un backup desde la carpeta backups/"

up-dev:
	cd aDespliegue/dev && docker compose up -d

down-dev:
	cd aDespliegue/dev && docker compose down

up-prod:
	cd aDespliegue/prod && docker compose up -d

down-prod:
	cd aDespliegue/prod && docker compose down

logs-dev:
	cd aDespliegue/dev && docker compose logs -f

logs-prod:
	cd aDespliegue/prod && docker compose logs -f

sh-dev:
	cd aDespliegue/dev && docker compose exec ${MYSQL_SERVICE_dev} bash

sh-prod:
	cd aDespliegue/prod && docker compose exec ${MYSQL_SERVICE_prod} bash

mysql-dev:
	cd aDespliegue/dev && docker compose exec ${MYSQL_SERVICE_dev} sh -c 'mysql -u\$\$MYSQL_USER -p\$\$MYSQL_PASSWORD \$\$MYSQL_DATABASE'

mysql-prod:
	cd aDespliegue/prod && docker compose exec ${MYSQL_SERVICE_prod} sh -c 'mysql -u\$\$MYSQL_USER -p\$\$MYSQL_PASSWORD \$\$MYSQL_DATABASE'

mysql-root-dev:
	cd aDespliegue/dev && docker compose exec ${MYSQL_SERVICE_dev} sh -c 'mysql -uroot -p\$\$MYSQL_ROOT_PASSWORD \$\$MYSQL_DATABASE'

mysql-root-prod:
	cd aDespliegue/prod && docker compose exec ${MYSQL_SERVICE_prod} sh -c 'mysql -uroot -p\$\$MYSQL_ROOT_PASSWORD \$\$MYSQL_DATABASE'

backup-dev:
	@mkdir -p backups
	@echo "Realizando copia de seguridad..."
	cd aDespliegue/dev && docker compose exec -T ${MYSQL_SERVICE_dev} sh -c 'mysqldump -u\$\$MYSQL_USER -p\$\$MYSQL_PASSWORD \$\$MYSQL_DATABASE' > ../../backups/backup_\$\$(date +%Y%m%d_%H%M%S).sql
	@echo "Copia de seguridad guardada en backups/"

backup-prod:
	@mkdir -p backups
	@echo "Realizando copia de seguridad..."
	cd aDespliegue/prod && docker compose exec -T ${MYSQL_SERVICE_prod} sh -c 'mysqldump -u\$\$MYSQL_USER -p\$\$MYSQL_PASSWORD \$\$MYSQL_DATABASE' > ../../backups/backup_\$\$(date +%Y%m%d_%H%M%S).sql
	@echo "Copia de seguridad guardada en backups/"

restore-dev:
	@if [ ! -d backups ] || [ -z "\$\$(ls backups/*.sql 2>/dev/null)" ]; then \\
		echo "No hay archivos de backup (.sql) en la carpeta backups/"; \\
		exit 1; \\
	fi
	@echo "Archivos disponibles:"
	@ls -1 backups/*.sql
	@read -p "Ingresa el nombre del archivo de backup a restaurar (ej: backups/backup_xxx.sql): " backup_file; \\
	if [ -f "\$\$backup_file" ]; then \\
		echo "Restaurando \$\$backup_file..."; \\
		cd aDespliegue/dev && docker compose exec -T ${MYSQL_SERVICE_dev} sh -c 'mysql -u\$\$MYSQL_USER -p\$\$MYSQL_PASSWORD \$\$MYSQL_DATABASE' < ../../"\$\$backup_file"; \\
		echo "Restauración completada con éxito."; \\
	else \\
		echo "El archivo '\$\$backup_file' no existe."; \\
		exit 1; \\
	fi

restore-prod:
	@if [ ! -d backups ] || [ -z "\$\$(ls backups/*.sql 2>/dev/null)" ]; then \\
		echo "No hay archivos de backup (.sql) en la carpeta backups/"; \\
		exit 1; \\
	fi
	@echo "Archivos disponibles:"
	@ls -1 backups/*.sql
	@read -p "Ingresa el nombre del archivo de backup a restaurar (ej: backups/backup_xxx.sql): " backup_file; \\
	if [ -f "\$\$backup_file" ]; then \\
		echo "Restaurando \$\$backup_file..."; \\
		cd aDespliegue/prod && docker compose exec -T ${MYSQL_SERVICE_prod} sh -c 'mysql -u\$\$MYSQL_USER -p\$\$MYSQL_PASSWORD \$\$MYSQL_DATABASE' < ../../"\$\$backup_file"; \\
		echo "Restauración completada con éxito."; \\
	else \\
		echo "El archivo '\$\$backup_file' no existe."; \\
		exit 1; \\
	fi
MAKE

# --- Generando .gitignore ---
step "Generando .gitignore"

cat > .gitignore <<GIT
aDespliegue/dev/.env
aDespliegue/prod/.env
backups/
GIT

# --- Generando leeme.txt ---
step "Generando leeme.txt"

{
  echo "desarrollo:"
  echo "-----------"
  echo "make up"
  echo "localhost:${MYSQL_PORT_DEV}"
  echo ""
  echo "producción:"
  echo "-----------"
  if [[ -n "${PROD_SERVER_IP}" ]]; then
    echo "${PROD_SERVER_IP}:${MYSQL_PORT_PROD}"
  else
    echo "localhost:${MYSQL_PORT_PROD}"
  fi
} > leeme.txt

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║   ✅  ${PROJECT_NAME} listo!              "
echo "╚══════════════════════════════════════════╝"
echo ""
echo "  Estructura creada:"
echo "    ${PROJECT_SLUG}/"
echo "    ├── .devcontainer/"
echo "    ├── aDespliegue/dev/docker-compose.yml"
echo "    ├── aDespliegue/dev/.env"
echo "    ├── aDespliegue/prod/docker-compose.yml"
echo "    ├── aDespliegue/prod/.env"
echo "    ├── Makefile"
echo "    ├── leeme.txt"
echo "    └── .gitignore"
echo ""
echo "  Para levantar el contenedor:"
echo "    cd ${PROJECT_SLUG}"
echo "    make up"
echo ""
echo "  Datos de Acceso:"
echo "    Host:        localhost (desde tu máquina)"
echo "    Puerto dev:  ${MYSQL_PORT_DEV}"
echo "    Puerto prod: ${MYSQL_PORT_PROD}"
echo "    Database:    ${DB_NAME}"
echo "    Usuario:     ${DB_USER}"
echo "    Contraseña:  ${DB_PASSWORD}"
echo "    ROOT Pass:   ${DB_ROOT_PASSWORD}"
echo ""
echo "  Comandos:"
echo "    make up-{dev|prod}    → iniciar base de datos"
echo "    make down-{dev|prod}  → detener base de datos"
echo "    make mysql-{dev|prod} → consola interactiva MySQL"
echo "    make backup-{dev|prod} → crear backup en backups/"
echo "    make logs-{dev|prod}  → ver logs en tiempo real"
echo ""

fi
