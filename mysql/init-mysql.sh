#!/bin/bash

set -e

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║      MySQL Docker Project Initializer    ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# Helper to ask Y/N questions
ask_yn() {
  local label=$1
  local default=${2:-n}
  local hint=$([ "$default" = "s" ] && echo "[S/n]" || echo "[s/N]")
  read -p "  $label $hint: " ans
  ans=${ans:-$default}
  [[ "$ans" =~ ^[sS]$ ]]
}

# Helper to ask text input
ask_input() {
  local label=$1
  local default=$2
  read -p "$label [default: $default]: " val
  echo "${val:-$default}"
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

else
  # --- Modo interactivo ---
  echo "Tip: podés crear un archivo .conf y correr: init-mysql.sh mi-proyecto.conf"
  echo ""

  read -p "Nombre del proyecto: " PROJECT_NAME
  if [[ -z "$PROJECT_NAME" ]]; then
    echo "Error: el nombre no puede estar vacío."; exit 1
  fi

  MYSQL_VERSION=$(ask_input "Versión de MySQL (imagen oficial)" "8.0")
  MYSQL_PORT_DEV=$(ask_input "Puerto local dev mapeado en el host" "3306")
  MYSQL_PORT_PROD=$(ask_input "Puerto local prod mapeado en el host" "3306")
  PROD_SERVER_IP=$(ask_input "IP servidor producción" "")
  DB_NAME=$(ask_input "Nombre de la base de datos" "app_db")
  DB_USER=$(ask_input "Usuario inicial" "app_user")
  DB_PASSWORD=$(ask_input "Contraseña del usuario inicial" "secret_password")
  DB_ROOT_PASSWORD=$(ask_input "Contraseña de ROOT" "secret_root_password")
  DB_NETWORK=$(ask_input "Red Docker compartida" "")
fi

PROJECT_SLUG=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g')
DB_NETWORK="${DB_NETWORK:-${PROJECT_SLUG}_net}"
DB_NETWORK_DEV="${DB_NETWORK}_dev"
DB_NETWORK_PROD="${DB_NETWORK}_prod"

# --- Verificar redes Docker ---
step "Verificando redes Docker"
for network in "$DB_NETWORK_DEV" "$DB_NETWORK_PROD"; do
  if ! verificar_red_docker "$network"; then
    echo "  ⚠ La red Docker '$network' no existe."
    if [[ -n "$CONFIG_FILE" ]]; then
      # Modo archivo: crear automáticamente
      echo "  Creando red automáticamente (modo archivo)..."
      if crear_red_docker "$network"; then
        echo "  ✓ Red '$network' creada."
      else
        echo "  ❌ No se pudo crear la red '$network'. Por favor, créala manualmente con:"
        echo "     docker network create $network"
        exit 1
      fi
    else
      # Modo interactivo: preguntar
      if ask_yn "¿Deseas crear la red '$network' ahora?" "s"; then
        if crear_red_docker "$network"; then
          echo "  ✓ Red '$network' creada."
        else
          echo "  ❌ No se pudo crear la red '$network'. Por favor, créala manualmente con:"
          echo "     docker network create $network"
          exit 1
        fi
      else
        echo "  ℹ Debes crear la red manualmente antes de continuar:"
        echo "     docker network create $network"
        exit 1
      fi
    fi
  else
    echo "  ✓ La red '$network' existe."
  fi
done

# --- Crear estructura de directorios ---
step "Creando estructura de directorios"

mkdir -p "$PROJECT_SLUG"
cd "$PROJECT_SLUG"

mkdir -p aDespliegue/dev
mkdir -p aDespliegue/prod

# --- aDespliegue/dev/docker-compose.yml ---
step "Generando docker-compose.yml dev"

cat > aDespliegue/dev/docker-compose.yml <<YAML
services:
  ${PROJECT_SLUG}_db:
    image: mysql:${MYSQL_VERSION}
    container_name: ${PROJECT_SLUG}_db
    restart: "no"
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
      - ${DB_NETWORK_DEV}

volumes:
  ${PROJECT_SLUG}_db_data:
    name: ${PROJECT_SLUG}_db_data

networks:
  ${DB_NETWORK_DEV}:
    name: ${DB_NETWORK_DEV}
YAML

# --- aDespliegue/prod/docker-compose.yml ---
step "Generando docker-compose.yml prod"

cat > aDespliegue/prod/docker-compose.yml <<YAML
services:
  ${PROJECT_SLUG}_db_prod:
    image: mysql:${MYSQL_VERSION}
    container_name: ${PROJECT_SLUG}_db_prod
    restart: unless-stopped
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
      - ${DB_NETWORK_PROD}

volumes:
  ${PROJECT_SLUG}_db_data_prod:
    name: ${PROJECT_SLUG}_db_data_prod

networks:
  ${DB_NETWORK_PROD}:
    name: ${DB_NETWORK_PROD}
YAML

# --- Generando .env y .env.example ---
step "Generando variables de entorno (.env)"

cat > .env.example <<ENV
MYSQL_VERSION=${MYSQL_VERSION}
MYSQL_PORT_DEV=${MYSQL_PORT_DEV}
MYSQL_PORT_PROD=${MYSQL_PORT_PROD}
PROD_SERVER_IP=
DB_NAME=${DB_NAME}
DB_USER=${DB_USER}
DB_PASSWORD=YOUR_DB_PASSWORD
DB_ROOT_PASSWORD=YOUR_ROOT_PASSWORD
DB_NETWORK=${DB_NETWORK}
ENV

cat > .env <<ENV
MYSQL_VERSION=${MYSQL_VERSION}
MYSQL_PORT_DEV=${MYSQL_PORT_DEV}
MYSQL_PORT_PROD=${MYSQL_PORT_PROD}
PROD_SERVER_IP=${PROD_SERVER_IP}
DB_NAME=${DB_NAME}
DB_USER=${DB_USER}
DB_PASSWORD=${DB_PASSWORD}
DB_ROOT_PASSWORD=${DB_ROOT_PASSWORD}
DB_NETWORK=${DB_NETWORK}
ENV

# --- Generando Makefile ---
step "Generando Makefile"

cat > Makefile <<MAKE
.PHONY: help up down start stop logs sh mysql mysql-root backup restore dev-up dev-down prod-up prod-down

ENV ?= dev
ENV_DIR = aDespliegue/\$(ENV)
MYSQL_SERVICE_dev = ${PROJECT_SLUG}_db
MYSQL_SERVICE_prod = ${PROJECT_SLUG}_db_prod
MYSQL_SERVICE = \$(MYSQL_SERVICE_\$(ENV))
include .env
export

help:
	@echo "Comandos disponibles:"
	@echo "  make help          - Muestra esta ayuda"
	@echo "  make up            - Levanta los contenedores (ENV=dev por defecto)"
	@echo "  make down          - Detiene y elimina los contenedores"
	@echo "  make start         - Levanta los contenedores (alias de up)"
	@echo "  make stop          - Detiene los contenedores (alias de down)"
	@echo "  make logs          - Muestra los logs en tiempo real"
	@echo "  make sh            - Accede al shell del contenedor MySQL"
	@echo "  make mysql         - Accede a MySQL con usuario normal"
	@echo "  make mysql-root    - Accede a MySQL como root"
	@echo "  make backup        - Realiza un backup de la base de datos"
	@echo "  make restore       - Restaura un backup desde la carpeta backups/"
	@echo "  make dev-up        - Levanta el ambiente de desarrollo"
	@echo "  make dev-down      - Detiene el ambiente de desarrollo"
	@echo "  make prod-up       - Levanta el ambiente de producción"
	@echo "  make prod-down     - Detiene el ambiente de producción"

up:
	docker compose --env-file .env -f \$(ENV_DIR)/docker-compose.yml up -d

down:
	docker compose --env-file .env -f \$(ENV_DIR)/docker-compose.yml down

start: up

stop: down

logs:
	docker compose --env-file .env -f \$(ENV_DIR)/docker-compose.yml logs -f

sh:
	docker compose --env-file .env -f \$(ENV_DIR)/docker-compose.yml exec \$(MYSQL_SERVICE) bash

mysql:
	docker compose --env-file .env -f \$(ENV_DIR)/docker-compose.yml exec \$(MYSQL_SERVICE) mysql -u\$(DB_USER) -p\$(DB_PASSWORD) \$(DB_NAME)

mysql-root:
	docker compose --env-file .env -f \$(ENV_DIR)/docker-compose.yml exec \$(MYSQL_SERVICE) mysql -uroot -p\$(DB_ROOT_PASSWORD) \$(DB_NAME)

backup:
	@mkdir -p backups
	@echo "Realizando copia de seguridad..."
	docker compose --env-file .env -f \$(ENV_DIR)/docker-compose.yml exec -T \$(MYSQL_SERVICE) mysqldump -u\$(DB_USER) -p\$(DB_PASSWORD) \$(DB_NAME) > backups/backup_\$\$(date +%Y%m%d_%H%M%S).sql
	@echo "Copia de seguridad guardada en backups/"

restore:
	@if [ ! -d backups ] || [ -z "\$\$(ls backups/*.sql 2>/dev/null)" ]; then \\
		echo "No hay archivos de backup (.sql) en la carpeta backups/"; \\
		exit 1; \\
	fi
	@echo "Archivos disponibles:"
	@ls -1 backups/*.sql
	@read -p "Ingresa el nombre del archivo de backup a restaurar (ej: backups/backup_xxx.sql): " backup_file; \\
	if [ -f "\$\$backup_file" ]; then \\
		echo "Restaurando \$\$backup_file..."; \\
		docker compose --env-file .env -f \$(ENV_DIR)/docker-compose.yml exec -T \$(MYSQL_SERVICE) mysql -u\$(DB_USER) -p\$(DB_PASSWORD) \$(DB_NAME) < "\$\$backup_file"; \\
		echo "Restauración completada con éxito."; \\
	else \\
		echo "El archivo '\$\$backup_file' no existe."; \\
		exit 1; \\
	fi

dev-up:
	\$(MAKE) up ENV=dev

dev-down:
	\$(MAKE) down ENV=dev

prod-up:
	\$(MAKE) up ENV=prod

prod-down:
	\$(MAKE) down ENV=prod
MAKE

# --- Generando .gitignore ---
step "Generando .gitignore"

cat > .gitignore <<GIT
.env
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

# --- Levantando el contenedor ---
step "Levantando contenedor MySQL..."
docker compose --env-file .env -f aDespliegue/dev/docker-compose.yml up -d

# Esperar a que MySQL esté listo
echo "Esperando que el contenedor de base de datos esté listo..."
sleep 3

# Verificación de conexión a la base de datos
step "Verificando conexión al contenedor MySQL"
maxAttempts=5
for i in $(seq 1 $maxAttempts); do
  if docker compose --env-file .env -f aDespliegue/dev/docker-compose.yml exec -T ${PROJECT_SLUG}_db mysqladmin ping -h localhost -u"${DB_USER}" -p"${DB_PASSWORD}" --silent >/dev/null; then
    echo "  Conexión exitosa al contenedor MySQL (${PROJECT_SLUG}_db)"
    break
  else
    if [ $i -eq $maxAttempts ]; then
      echo "❌ Error crítico: No se pudo establecer conexión con el contenedor MySQL."
      echo "   Por favor, verifica los logs con: make logs"
      exit 1
    fi
    echo "  [$i/$maxAttempts] Esperando al contenedor MySQL..."
    sleep 2
  fi
done

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║   ✅  ${PROJECT_NAME} listo!              "
echo "╚══════════════════════════════════════════╝"
echo ""
echo "  Estructura creada:"
echo "    ${PROJECT_SLUG}/"
echo "    ├── aDespliegue/dev/docker-compose.yml"
echo "    ├── aDespliegue/prod/docker-compose.yml"
echo "    ├── Makefile"
echo "    ├── .env"
echo "    └── .gitignore"
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
echo "    make start  → iniciar base de datos"
echo "    make stop   → detener base de datos"
echo "    make mysql  → consola interactiva MySQL"
echo "    make backup → crear backup en backups/"
echo "    make logs   → ver logs en tiempo real"
echo "    make prod-up → iniciar base de datos en prod"
echo ""
