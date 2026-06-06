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
  MYSQL_PORT="${MYSQL_PORT:-3322}"
  PROD_SERVER_IP="${PROD_SERVER_IP:-}"
  DB_NAME="${DB_NAME:-app_db}"
  DB_USER="${DB_USER:-app_user}"
  DB_PASSWORD="${DB_PASSWORD:-secret_password}"
  DB_ROOT_PASSWORD="${DB_ROOT_PASSWORD:-secret_root_password}"
  DB_NETWORK="${DB_NETWORK:-}"

PROJECT_SLUG=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g')
# Si no se definió directamente, calcularla desde DB_NETWORK
DB_NETWORK="${DB_NETWORK:-${PROJECT_SLUG}_net}"

# --- Verificar red Docker ---
step "Verificando red Docker"
if ! verificar_red_docker "$DB_NETWORK"; then
  echo "  ⚠ La red Docker '$DB_NETWORK' no existe."
  echo "  Creando red automáticamente..."
  if crear_red_docker "$DB_NETWORK"; then
    echo "  ✓ Red '$DB_NETWORK' creada."
  else
    echo "  ❌ No se pudo crear la red '$DB_NETWORK'. Por favor, créala manualmente con:"
    echo "     docker network create $DB_NETWORK"
    exit 1
  fi
else
  echo "  ✓ La red '$DB_NETWORK' existe."
fi

# --- Crear estructura de directorios ---
step "Creando estructura de directorios"

mkdir -p "$PROJECT_SLUG"
cd "$PROJECT_SLUG"

mkdir -p aDespliegue

# --- aDespliegue/docker-compose.yml ---
step "Generando docker-compose.yml"

cat > aDespliegue/docker-compose.yml <<YAML
services:
  ${PROJECT_SLUG}:
    image: mysql:${MYSQL_VERSION}
    container_name: ${PROJECT_SLUG}
    restart: unless-stopped
    env_file: .env
    environment:
      MYSQL_ROOT_PASSWORD: "\${DB_ROOT_PASSWORD}"
      MYSQL_DATABASE: "\${DB_NAME}"
      MYSQL_USER: "\${DB_USER}"
      MYSQL_PASSWORD: "\${DB_PASSWORD}"
    ports:
      - "\${MYSQL_PORT}:3306"
    volumes:
      - ${PROJECT_SLUG}_data:/var/lib/mysql
    networks:
      - db_network

volumes:
  ${PROJECT_SLUG}_data:
    name: ${PROJECT_SLUG}_data

networks:
  db_network:
    name: "\${DB_NETWORK}"
    external: true
YAML


# --- Generando .env y .env.example ---
step "Generando variables de entorno (.env)"

cat > aDespliegue/.env.example <<ENV
MYSQL_VERSION=${MYSQL_VERSION}
MYSQL_PORT=${MYSQL_PORT}
DB_NAME=${DB_NAME}
DB_USER=${DB_USER}
DB_PASSWORD=YOUR_DB_PASSWORD
DB_ROOT_PASSWORD=YOUR_ROOT_PASSWORD
DB_NETWORK=${DB_NETWORK}
ENV

cat > aDespliegue/.env <<ENV
MYSQL_VERSION=${MYSQL_VERSION}
MYSQL_PORT=${MYSQL_PORT}
DB_NAME=${DB_NAME}
DB_USER=${DB_USER}
DB_PASSWORD=${DB_PASSWORD}
DB_ROOT_PASSWORD=${DB_ROOT_PASSWORD}
DB_NETWORK=${DB_NETWORK}
ENV

# --- Generando Makefile ---
step "Generando Makefile"

cat > Makefile <<MAKE
.PHONY: help up down logs sh mysql mysql-root backup restore

MYSQL_SERVICE = ${PROJECT_SLUG}

help:
	@echo "Comandos disponibles:"
	@echo "  make help        - Muestra esta ayuda"
	@echo "  make up          - Levanta el contenedor MySQL"
	@echo "  make down        - Detiene el contenedor MySQL"
	@echo "  make logs        - Muestra los logs en tiempo real"
	@echo "  make sh          - Accede al shell del contenedor MySQL"
	@echo "  make mysql       - Accede a MySQL con usuario normal"
	@echo "  make mysql-root  - Accede a MySQL como root"
	@echo "  make backup      - Realiza un backup de la base de datos"
	@echo "  make restore     - Restaura un backup desde la carpeta backups/"

up:
	cd aDespliegue && docker compose up -d

down:
	cd aDespliegue && docker compose down

logs:
	cd aDespliegue && docker compose logs -f

sh:
	cd aDespliegue && docker compose exec ${MYSQL_SERVICE} bash

mysql:
	cd aDespliegue && docker compose exec ${MYSQL_SERVICE} sh -c 'mysql -u\$\$MYSQL_USER -p\$\$MYSQL_PASSWORD \$\$MYSQL_DATABASE'

mysql-root:
	cd aDespliegue && docker compose exec ${MYSQL_SERVICE} sh -c 'mysql -uroot -p\$\$MYSQL_ROOT_PASSWORD \$\$MYSQL_DATABASE'

backup:
	@mkdir -p backups
	@echo "Realizando copia de seguridad..."
	cd aDespliegue && docker compose exec -T ${MYSQL_SERVICE} sh -c 'mysqldump -u\$\$MYSQL_USER -p\$\$MYSQL_PASSWORD \$\$MYSQL_DATABASE' > ../../backups/backup_\$\$(date +%Y%m%d_%H%M%S).sql
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
		cd aDespliegue && docker compose exec -T ${MYSQL_SERVICE} sh -c 'mysql -u\$\$MYSQL_USER -p\$\$MYSQL_PASSWORD \$\$MYSQL_DATABASE' < ../../"\$\$backup_file"; \\
		echo "Restauración completada con éxito."; \\
	else \\
		echo "El archivo '\$\$backup_file' no existe."; \\
		exit 1; \\
	fi
MAKE

# --- Generando .gitignore ---
step "Generando .gitignore"

cat > .gitignore <<GIT
aDespliegue/.env
backups/
GIT

# --- Generando leeme.txt ---
step "Generando leeme.txt"

{
  echo "Para levantar el contenedor:"
  echo "  make up"
  echo ""
  echo "Para detener el contenedor:"
  echo "  make down"
  echo ""
  echo "Para ver logs:"
  echo "  make logs"
  echo ""
  if [[ -n "${PROD_SERVER_IP}" ]]; then
    echo "Acceso MySQL: ${PROD_SERVER_IP}:${MYSQL_PORT}"
  else
    echo "Acceso MySQL: localhost:${MYSQL_PORT}"
  fi
} > leeme.txt

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║   ✅  ${PROJECT_NAME} listo!              "
echo "╚══════════════════════════════════════════╝"
echo ""
echo "  Estructura creada:"
echo "    ${PROJECT_SLUG}/"
echo "    ├── aDespliegue/docker-compose.yml"
echo "    ├── aDespliegue/.env"
echo "    ├── aDespliegue/.env.example"
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
echo "    Puerto:      ${MYSQL_PORT}"
echo "    Database:    ${DB_NAME}"
echo "    Usuario:     ${DB_USER}"
echo "    Contraseña:  ${DB_PASSWORD}"
echo "    ROOT Pass:   ${DB_ROOT_PASSWORD}"
echo ""
echo "  Comandos:"
echo "    make up          → iniciar base de datos"
echo "    make down        → detener base de datos"
echo "    make mysql       → consola interactiva MySQL"
echo "    make mysql-root  → consola interactiva MySQL como root"
echo "    make backup      → crear backup en backups/"
echo "    make restore     → restaurar backup desde backups/"
echo "    make logs        → ver logs en tiempo real"
echo ""

fi
