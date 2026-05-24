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
  while IFS='=' read -r key value; do
    [[ "$key" =~ ^#.*$ || -z "$key" ]] && continue
    key=$(echo "$key" | tr -d ' ')
    value=$(echo "$value" | tr -d '"' | tr -d "'" | sed 's/[[:space:]]*#.*//' | xargs)
    declare "$key=$value"
  done < "$CONFIG_FILE"

  CONFIG_BASENAME=$(basename "$CONFIG_FILE" .conf)
  PROJECT_NAME=${CONFIG_BASENAME#project_}
  if [[ -z "${PROJECT_NAME:-}" ]]; then
    PROJECT_NAME="mysql-project"
  fi

  MYSQL_VERSION="${MYSQL_VERSION:-8.0}"
  MYSQL_PORT="${MYSQL_PORT:-3306}"
  DB_NAME="${DB_NAME:-app_db}"
  DB_USER="${DB_USER:-app_user}"
  DB_PASSWORD="${DB_PASSWORD:-secret_password}"
  DB_ROOT_PASSWORD="${DB_ROOT_PASSWORD:-secret_root_password}"
  MYSQL_NETWORK="${MYSQL_NETWORK:-}"

else
  # --- Modo interactivo ---
  echo "Tip: podés crear un archivo .conf y correr: init-mysql.sh mi-proyecto.conf"
  echo ""

  read -p "Nombre del proyecto: " PROJECT_NAME
  if [[ -z "$PROJECT_NAME" ]]; then
    echo "Error: el nombre no puede estar vacío."; exit 1
  fi

  MYSQL_VERSION=$(ask_input "Versión de MySQL (imagen oficial)" "8.0")
  MYSQL_PORT=$(ask_input "Puerto local mapeado en el host" "3306")
  DB_NAME=$(ask_input "Nombre de la base de datos" "app_db")
  DB_USER=$(ask_input "Usuario inicial" "app_user")
  DB_PASSWORD=$(ask_input "Contraseña del usuario inicial" "secret_password")
  DB_ROOT_PASSWORD=$(ask_input "Contraseña de ROOT" "secret_root_password")
  MYSQL_NETWORK=$(ask_input "Red Docker compartida" "")
fi

PROJECT_SLUG=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g')
MYSQL_NETWORK="${MYSQL_NETWORK:-${PROJECT_SLUG}_net}"

# --- Crear estructura de directorios ---
step "Creando estructura de directorios"

mkdir -p "$PROJECT_SLUG"
cd "$PROJECT_SLUG"

mkdir -p aDespliegue/dev

# --- aDespliegue/dev/docker-compose.yml ---
step "Generando docker-compose.yml"

cat > aDespliegue/dev/docker-compose.yml <<YAML
services:
  ${PROJECT_SLUG}_db:
    image: mysql:${MYSQL_VERSION}
    container_name: ${PROJECT_SLUG}_db
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: "\${DB_ROOT_PASSWORD}"
      MYSQL_DATABASE: "\${DB_NAME}"
      MYSQL_USER: "\${DB_USER}"
      MYSQL_PASSWORD: "\${DB_PASSWORD}"
    ports:
      - "\${MYSQL_PORT}:3306"
    volumes:
      - ${PROJECT_SLUG}_db_data:/var/lib/mysql
    networks:
      - ${MYSQL_NETWORK}

volumes:
  ${PROJECT_SLUG}_db_data:
    name: ${PROJECT_SLUG}_db_data

networks:
  ${MYSQL_NETWORK}:
    name: ${MYSQL_NETWORK}
YAML

# --- Generando .env y .env.example ---
step "Generando variables de entorno (.env)"

cat > .env.example <<ENV
MYSQL_VERSION=${MYSQL_VERSION}
MYSQL_PORT=${MYSQL_PORT}
DB_NAME=${DB_NAME}
DB_USER=${DB_USER}
DB_PASSWORD=YOUR_DB_PASSWORD
DB_ROOT_PASSWORD=YOUR_ROOT_PASSWORD
MYSQL_NETWORK=${MYSQL_NETWORK}
ENV

cat > .env <<ENV
MYSQL_VERSION=${MYSQL_VERSION}
MYSQL_PORT=${MYSQL_PORT}
DB_NAME=${DB_NAME}
DB_USER=${DB_USER}
DB_PASSWORD=${DB_PASSWORD}
DB_ROOT_PASSWORD=${DB_ROOT_PASSWORD}
MYSQL_NETWORK=${MYSQL_NETWORK}
ENV

# --- Generando Makefile ---
step "Generando Makefile"

cat > Makefile <<MAKE
.PHONY: up down start stop logs sh mysql mysql-root backup restore

ENV_DIR = aDespliegue/dev
include .env
export

up:
	docker compose --env-file .env -f \$(ENV_DIR)/docker-compose.yml up -d

down:
	docker compose --env-file .env -f \$(ENV_DIR)/docker-compose.yml down

start: up

stop: down

logs:
	docker compose --env-file .env -f \$(ENV_DIR)/docker-compose.yml logs -f

sh:
	docker compose --env-file .env -f \$(ENV_DIR)/docker-compose.yml exec ${PROJECT_SLUG}_db bash

mysql:
	docker compose --env-file .env -f \$(ENV_DIR)/docker-compose.yml exec ${PROJECT_SLUG}_db mysql -u\$(DB_USER) -p\$(DB_PASSWORD) \$(DB_NAME)

mysql-root:
	docker compose --env-file .env -f \$(ENV_DIR)/docker-compose.yml exec ${PROJECT_SLUG}_db mysql -uroot -p\$(DB_ROOT_PASSWORD) \$(DB_NAME)

backup:
	@mkdir -p backups
	@echo "Realizando copia de seguridad..."
	docker compose --env-file .env -f \$(ENV_DIR)/docker-compose.yml exec -T ${PROJECT_SLUG}_db mysqldump -u\$(DB_USER) -p\$(DB_PASSWORD) \$(DB_NAME) > backups/backup_\$\$(date +%Y%m%d_%H%M%S).sql
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
		docker compose --env-file .env -f \$(ENV_DIR)/docker-compose.yml exec -T ${PROJECT_SLUG}_db mysql -u\$(DB_USER) -p\$(DB_PASSWORD) \$(DB_NAME) < "\$\$backup_file"; \\
		echo "Restauración completada con éxito."; \\
	else \\
		echo "El archivo '\$\$backup_file' no existe."; \\
		exit 1; \\
	fi
MAKE

# --- Generando .gitignore ---
step "Generando .gitignore"

cat > .gitignore <<GIT
.env
backups/
GIT

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
echo "    ├── Makefile"
echo "    ├── .env"
echo "    └── .gitignore"
echo ""
echo "  Datos de Acceso:"
echo "    Host:        localhost (desde tu máquina)"
echo "    Puerto:      ${MYSQL_PORT}"
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
echo ""
