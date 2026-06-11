#!/bin/bash

set -e

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║      pgAdmin4 Project Initializer        ║"
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
    PROJECT_NAME="pgadmin-project"
  fi

  PGADMIN_PORT="${PGADMIN_PORT:-8022}"
  PGADMIN_EMAIL="${PGADMIN_EMAIL:-admin@admin.com}"
  PGADMIN_PASSWORD="${PGADMIN_PASSWORD:-admin123}"
  PROD_SERVER_IP="${PROD_SERVER_IP:-}"
  DB_HOST="${DB_HOST:-host.docker.internal}"
  DB_PORT="${DB_PORT:-5432}"
  DB_SERVER_NAME="${DB_SERVER_NAME:-PostgreSQL}"
  DB_NETWORK="${DB_NETWORK:-}"

PROJECT_SLUG=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g')
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

# --- servers.json: preconfigurar la conexión al servidor PostgreSQL ---
# pgAdmin carga este archivo al iniciar y registra el servidor automáticamente.
# El usuario solo necesita ingresar la contraseña la primera vez.
step "Generando configuración de servidor (servers.json)"

cat > aDespliegue/servers.json <<JSON
{
  "Servers": {
    "1": {
      "Name": "${DB_SERVER_NAME}",
      "Group": "Servers",
      "Host": "${DB_HOST}",
      "Port": ${DB_PORT},
      "MaintenanceDB": "postgres",
      "Username": "postgres",
      "SSLMode": "prefer",
      "PassFile": "/pgpass"
    }
  }
}
JSON

# --- aDespliegue/docker-compose.yml ---
step "Generando docker-compose.yml"

cat > aDespliegue/docker-compose.yml <<YAML
services:
  ${PROJECT_SLUG}:
    image: dpage/pgadmin4:latest
    container_name: ${PROJECT_SLUG}
    restart: unless-stopped
    env_file: .env
    environment:
      PGADMIN_DEFAULT_EMAIL: "\${PGADMIN_EMAIL}"
      PGADMIN_DEFAULT_PASSWORD: "\${PGADMIN_PASSWORD}"
      PGADMIN_LISTEN_PORT: "80"
    ports:
      - "\${PGADMIN_PORT}:80"
    volumes:
      - ${PROJECT_SLUG}_data:/var/lib/pgadmin
      - ./servers.json:/pgadmin4/servers.json:ro
    extra_hosts:
      - "host.docker.internal:host-gateway"
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
PGADMIN_PORT=${PGADMIN_PORT}
PGADMIN_EMAIL=${PGADMIN_EMAIL}
PGADMIN_PASSWORD=YOUR_PGADMIN_PASSWORD
DB_HOST=${DB_HOST}
DB_PORT=${DB_PORT}
DB_NETWORK=${DB_NETWORK}
ENV

cat > aDespliegue/.env <<ENV
PGADMIN_PORT=${PGADMIN_PORT}
PGADMIN_EMAIL=${PGADMIN_EMAIL}
PGADMIN_PASSWORD=${PGADMIN_PASSWORD}
DB_HOST=${DB_HOST}
DB_PORT=${DB_PORT}
DB_NETWORK=${DB_NETWORK}
ENV

# --- Generando Makefile ---
step "Generando Makefile"

cat > Makefile <<MAKE
.PHONY: help up down logs sh

PGADMIN_SERVICE = ${PROJECT_SLUG}

help:
	@echo "Comandos disponibles:"
	@echo "  make help  - Muestra esta ayuda"
	@echo "  make up    - Levanta pgAdmin4"
	@echo "  make down  - Detiene pgAdmin4"
	@echo "  make logs  - Muestra los logs en tiempo real"
	@echo "  make sh    - Accede al shell del contenedor pgAdmin4"

up:
	cd aDespliegue && docker compose up -d

down:
	cd aDespliegue && docker compose down

logs:
	cd aDespliegue && docker compose logs -f

sh:
	cd aDespliegue && docker compose exec \${PGADMIN_SERVICE} sh
MAKE

# --- Generando .gitignore ---
step "Generando .gitignore"

cat > .gitignore <<GIT
aDespliegue/.env
GIT

# --- Generando leeme.txt ---
step "Generando leeme.txt"

{
  echo "Para levantar pgAdmin4:"
  echo "  make up"
  echo ""
  echo "Para detener pgAdmin4:"
  echo "  make down"
  echo ""
  echo "Para ver logs:"
  echo "  make logs"
  echo ""
  if [[ -n "${PROD_SERVER_IP}" ]]; then
    echo "Acceso: http://${PROD_SERVER_IP}:${PGADMIN_PORT}"
  else
    echo "Acceso: http://localhost:${PGADMIN_PORT}"
  fi
  echo ""
  echo "Credenciales pgAdmin:"
  echo "  Email:      ${PGADMIN_EMAIL}"
  echo "  Contraseña: ${PGADMIN_PASSWORD}"
  echo ""
  echo "El servidor '${DB_SERVER_NAME}' aparece preconfigurado en pgAdmin."
  echo "Solo deberás ingresar la contraseña de PostgreSQL al conectarte."
} > leeme.txt

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║   ✅  ${PROJECT_NAME} listo!              "
echo "╚══════════════════════════════════════════╝"
echo ""
echo "  Estructura creada:"
echo "    ${PROJECT_SLUG}/"
echo "    ├── aDespliegue/docker-compose.yml"
echo "    ├── aDespliegue/servers.json"
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
echo "  Acceso Web:"
echo "    URL:        http://localhost:${PGADMIN_PORT}"
echo "    Email:      ${PGADMIN_EMAIL}"
echo "    Contraseña: ${PGADMIN_PASSWORD}"
echo ""
echo "  Servidor preconfigurado: '${DB_SERVER_NAME}'"
echo "    Host: ${DB_HOST}:${DB_PORT}"
echo "    (ingresar contraseña de postgres al conectarte)"
echo ""
echo "  Comandos:"
echo "    make up    → iniciar pgAdmin4"
echo "    make down  → detener pgAdmin4"
echo "    make logs  → ver logs en tiempo real"
echo ""

fi
