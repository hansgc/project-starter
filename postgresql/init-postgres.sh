#!/bin/bash

set -e

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║   PostgreSQL Docker Project Initializer  ║"
echo "╚══════════════════════════════════════════╝"
echo ""

step() {
  echo ""
  echo "$1"
}

verificar_red_docker() {
  local network_name=$1
  if docker network inspect "$network_name" >/dev/null 2>&1; then
    return 0
  else
    return 1
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
    PROJECT_NAME="postgres-project"
  fi

  PG_VERSION="${PG_VERSION:-17}"
  PG_PORT="${PG_PORT:-5432}"
  PROD_SERVER_IP="${PROD_SERVER_IP:-}"
  DB_NAME="${DB_NAME:-app_db}"
  DB_USER="${DB_USER:-app_user}"
  DB_PASSWORD="${DB_PASSWORD:-secret_password}"
  DB_ROOT_PASSWORD="${DB_ROOT_PASSWORD:-secret_root_password}"
  DB_NETWORK="${DB_NETWORK:-}"

PROJECT_SLUG=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g')
DB_NETWORK="${DB_NETWORK:-proyectos-net}"

# --- Verificar red Docker ---
step "Verificando red Docker"
if ! verificar_red_docker "$DB_NETWORK"; then
  echo "  ❌ La red Docker '$DB_NETWORK' no existe."
  echo "  Créala antes de ejecutar este script:"
  echo "     docker network create $DB_NETWORK"
  exit 1
else
  echo "  ✓ La red '$DB_NETWORK' existe."
fi

# --- Crear estructura de directorios ---
step "Creando estructura de directorios"

mkdir -p "$PROJECT_SLUG"
cd "$PROJECT_SLUG"

mkdir -p aDespliegue/initdb

# --- Script de inicialización de PostgreSQL ---
# Crea el usuario de aplicación separado del superusuario postgres
step "Generando script de inicialización de base de datos"

cat > aDespliegue/initdb/01-init-user.sql <<SQL
-- Crear usuario de aplicación si no existe
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${DB_USER}') THEN
    CREATE USER "${DB_USER}" WITH PASSWORD '${DB_PASSWORD}';
  END IF;
END
\$\$;

-- Otorgar privilegios sobre la base de datos al usuario de aplicación
GRANT ALL PRIVILEGES ON DATABASE "${DB_NAME}" TO "${DB_USER}";

-- Otorgar privilegios sobre el schema public
\c "${DB_NAME}"
GRANT ALL ON SCHEMA public TO "${DB_USER}";
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO "${DB_USER}";
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO "${DB_USER}";
SQL

# --- aDespliegue/docker-compose.yml ---
step "Generando docker-compose.yml"

cat > aDespliegue/docker-compose.yml <<YAML
services:
  ${PROJECT_SLUG}:
    image: postgres:\${PG_VERSION}
    container_name: ${PROJECT_SLUG}
    restart: unless-stopped
    env_file: .env
    environment:
      POSTGRES_DB: "\${DB_NAME}"
      POSTGRES_PASSWORD: "\${DB_ROOT_PASSWORD}"
    ports:
      - "\${PG_PORT}:5432"
    volumes:
      - ${PROJECT_SLUG}_data:/var/lib/postgresql
      - ./initdb:/docker-entrypoint-initdb.d:ro
    networks:
      - db_network
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres -d \${DB_NAME}"]
      interval: 10s
      timeout: 5s
      retries: 5

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
PG_VERSION=${PG_VERSION}
PG_PORT=${PG_PORT}
DB_NAME=${DB_NAME}
DB_USER=${DB_USER}
DB_PASSWORD=YOUR_DB_PASSWORD
DB_ROOT_PASSWORD=YOUR_ROOT_PASSWORD
DB_NETWORK=${DB_NETWORK}
ENV

cat > aDespliegue/.env <<ENV
PG_VERSION=${PG_VERSION}
PG_PORT=${PG_PORT}
DB_NAME=${DB_NAME}
DB_USER=${DB_USER}
DB_PASSWORD=${DB_PASSWORD}
DB_ROOT_PASSWORD=${DB_ROOT_PASSWORD}
DB_NETWORK=${DB_NETWORK}
ENV

# --- Generando Makefile ---
step "Generando Makefile"

cat > Makefile <<MAKE
.PHONY: help up down logs sh psql psql-root backup restore

PG_SERVICE = ${PROJECT_SLUG}

help:
	@echo "Comandos disponibles:"
	@echo "  make help       - Muestra esta ayuda"
	@echo "  make up         - Levanta el contenedor PostgreSQL"
	@echo "  make down       - Detiene el contenedor PostgreSQL"
	@echo "  make logs       - Muestra los logs en tiempo real"
	@echo "  make sh         - Accede al shell del contenedor"
	@echo "  make psql       - Accede a psql con usuario de aplicación"
	@echo "  make psql-root  - Accede a psql como superusuario postgres"
	@echo "  make backup     - Realiza un backup de la base de datos"
	@echo "  make restore    - Restaura un backup desde la carpeta backups/"

up:
	cd aDespliegue && docker compose up -d

down:
	cd aDespliegue && docker compose down

logs:
	cd aDespliegue && docker compose logs -f

sh:
	cd aDespliegue && docker compose exec \$(PG_SERVICE) bash

psql:
	cd aDespliegue && docker compose exec \$(PG_SERVICE) psql -U ${DB_USER} -d ${DB_NAME}

psql-root:
	cd aDespliegue && docker compose exec \$(PG_SERVICE) psql -U postgres -d ${DB_NAME}

backup:
	@mkdir -p backups
	@echo "Realizando copia de seguridad..."
	cd aDespliegue && docker compose exec -T \$(PG_SERVICE) pg_dump -U ${DB_USER} ${DB_NAME} > ../backups/backup_\$\$(date +%Y%m%d_%H%M%S).sql
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
		cd aDespliegue && docker compose exec -T \$(PG_SERVICE) psql -U ${DB_USER} -d ${DB_NAME} < ../"\$\$backup_file"; \\
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
    echo "Acceso PostgreSQL: ${PROD_SERVER_IP}:${PG_PORT}"
  else
    echo "Acceso PostgreSQL: localhost:${PG_PORT}"
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
echo "    ├── aDespliegue/initdb/01-init-user.sql"
echo "    ├── Makefile"
echo "    ├── leeme.txt"
echo "    └── .gitignore"
echo ""
echo "  Para levantar el contenedor:"
echo "    cd ${PROJECT_SLUG}"
echo "    make up"
echo ""
echo "  Datos de Acceso:"
echo "    Host:            localhost (desde tu máquina)"
echo "    Puerto:          ${PG_PORT}"
echo "    Database:        ${DB_NAME}"
echo "    Usuario app:     ${DB_USER}"
echo "    Contraseña app:  ${DB_PASSWORD}"
echo "    Superusuario:    postgres"
echo "    Password root:   ${DB_ROOT_PASSWORD}"
echo ""
echo "  Comandos:"
echo "    make up          → iniciar base de datos"
echo "    make down        → detener base de datos"
echo "    make psql        → consola interactiva (usuario app)"
echo "    make psql-root   → consola interactiva (superusuario postgres)"
echo "    make backup      → crear backup en backups/"
echo "    make restore     → restaurar backup desde backups/"
echo "    make logs        → ver logs en tiempo real"
echo ""

fi
