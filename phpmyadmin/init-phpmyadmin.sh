#!/bin/bash

set -e

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║     phpMyAdmin Project Initializer       ║"
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
    PROJECT_NAME="pma-project"
  fi

  PMA_PORT_DEV="${PMA_PORT_DEV:-${PMA_PORT:-8081}}"
  PMA_PORT_PROD="${PMA_PORT_PROD:-80}"
  PROD_SERVER_IP="${PROD_SERVER_IP:-}"
  PMA_HOST="${PMA_HOST:-host.docker.internal}"
  PMA_DB_PORT_DEV="${PMA_DB_PORT_DEV:-3306}"
  PMA_DB_PORT_PROD="${PMA_DB_PORT_PROD:-3306}"
  PMA_ARBITRARY="${PMA_ARBITRARY:-1}"
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
  ${PROJECT_SLUG}_pma_dev:
    image: phpmyadmin:latest
    container_name: ${PROJECT_SLUG}_pma_dev
    restart: "no"
    env_file: .env
    environment:
      PMA_HOST: "\${PMA_HOST}"
      PMA_PORT: "\${PMA_DB_PORT_DEV}"
      PMA_ARBITRARY: "\${PMA_ARBITRARY}"
      PMA_ABSOLUTE_URI: "http://localhost:\${PMA_PORT_DEV}/"
    ports:
      - "\${PMA_PORT_DEV}:80"
    extra_hosts:
      - "host.docker.internal:host-gateway"
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

networks:
  \${DB_NETWORK_DEV}:
    name: "\${DB_NETWORK_DEV}"
    external: true
YAML

# --- aDespliegue/prod/docker-compose.yml ---
step "Generando docker-compose.yml prod"

cat > aDespliegue/prod/docker-compose.yml <<YAML
services:
  ${PROJECT_SLUG}_pma_prod:
    image: phpmyadmin:latest
    container_name: ${PROJECT_SLUG}_pma_prod
    restart: unless-stopped
    env_file: .env
    environment:
      PMA_HOST: "\${PMA_HOST}"
      PMA_PORT: "\${PMA_DB_PORT_PROD}"
      PMA_ARBITRARY: "\${PMA_ARBITRARY}"
      PMA_ABSOLUTE_URI: "http://localhost:\${PMA_PORT_PROD}/"
    ports:
      - "\${PMA_PORT_PROD}:80"
    extra_hosts:
      - "host.docker.internal:host-gateway"
    networks:
      - "\${DB_NETWORK_PROD}"

networks:
  \${DB_NETWORK_PROD}:
    name: "\${DB_NETWORK_PROD}"
    external: true
YAML

# --- Generando .devcontainer ---
step "Generando .devcontainer"

cat > .devcontainer/devcontainer.json <<JSON
{
  "name": "${PROJECT_NAME} phpMyAdmin",
  "dockerComposeFile": ["../aDespliegue/dev/docker-compose.yml"],
  "service": "dev",
  "workspaceFolder": "/workspace",
  "shutdownAction": "stopCompose"
}
JSON

cat > aDespliegue/dev/.env.example <<ENV
PMA_PORT_DEV=${PMA_PORT_DEV}
PMA_HOST=${PMA_HOST}
PMA_DB_PORT_DEV=${PMA_DB_PORT_DEV}
PMA_ARBITRARY=${PMA_ARBITRARY}
DB_NETWORK_DEV=${DB_NETWORK_DEV}
ENV

cat > aDespliegue/dev/.env <<ENV
PMA_PORT_DEV=${PMA_PORT_DEV}
PMA_HOST=${PMA_HOST}
PMA_DB_PORT_DEV=${PMA_DB_PORT_DEV}
PMA_ARBITRARY=${PMA_ARBITRARY}
DB_NETWORK_DEV=${DB_NETWORK_DEV}
ENV

cat > aDespliegue/prod/.env.example <<ENV
PMA_PORT_PROD=${PMA_PORT_PROD}
PROD_SERVER_IP=
PMA_HOST=${PMA_HOST}
PMA_DB_PORT_PROD=${PMA_DB_PORT_PROD}
PMA_ARBITRARY=${PMA_ARBITRARY}
DB_NETWORK_PROD=${DB_NETWORK_PROD}
ENV

cat > aDespliegue/prod/.env <<ENV
PMA_PORT_PROD=${PMA_PORT_PROD}
PROD_SERVER_IP=${PROD_SERVER_IP}
PMA_HOST=${PMA_HOST}
PMA_DB_PORT_PROD=${PMA_DB_PORT_PROD}
PMA_ARBITRARY=${PMA_ARBITRARY}
DB_NETWORK_PROD=${DB_NETWORK_PROD}
ENV

# --- Generando Makefile ---
step "Generando Makefile"

cat > Makefile <<MAKE
.PHONY: help logs sh up-dev down-dev up-prod down-prod

PMA_SERVICE_dev = ${PROJECT_SLUG}_pma_dev
PMA_SERVICE_prod = ${PROJECT_SLUG}_pma_prod

help:
	@echo "Comandos disponibles:"
	@echo "  make help             - Muestra esta ayuda"
	@echo "  make up-{dev|prod}    - Levanta el ambiente de desarrollo/producción"
	@echo "  make down-{dev|prod}  - Detiene el ambiente de desarrollo/producción"
	@echo "  make logs-{dev|prod}  - Muestra los logs en tiempo real"
	@echo "  make sh-{dev|prod}    - Accede al shell del contenedor phpMyAdmin"

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
	cd aDespliegue/dev && docker compose exec \${PMA_SERVICE_dev} sh

sh-prod:
	cd aDespliegue/prod && docker compose exec \${PMA_SERVICE_prod} sh
MAKE

# --- Generando .gitignore ---
step "Generando .gitignore"

cat > .gitignore <<GIT
aDespliegue/dev/.env
aDespliegue/prod/.env
GIT

# --- Generando leeme.txt ---
step "Generando leeme.txt"

{
  echo "desarrollo:"
  echo "-----------"
  echo "make up"
  echo "http://localhost:${PMA_PORT_DEV}"
  echo ""
  echo "producción:"
  echo "-----------"
  if [[ -n "${PROD_SERVER_IP}" ]]; then
    echo "http://${PROD_SERVER_IP}:${PMA_PORT_PROD}"
  else
    echo "http://localhost:${PMA_PORT_PROD}"
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
echo "  Acceso Web:"
echo "    URL dev:     http://localhost:${PMA_PORT_DEV}"
echo "    URL prod:    http://localhost:${PMA_PORT_PROD}"
echo "    Host MySQL:  ${PMA_HOST}"
if [[ -n "$DB_NETWORK" ]]; then
  echo "    Red Docker:  ${DB_NETWORK} (externa)"
fi
echo "    Port MySQL dev:  ${PMA_DB_PORT_DEV}"
echo "    Port MySQL prod: ${PMA_DB_PORT_PROD}"
echo ""
echo "  Comandos:"
echo "    make up-{dev|prod}    → iniciar phpMyAdmin"
echo "    make down-{dev|prod}  → detener phpMyAdmin"
echo "    make logs-{dev|prod}  → ver logs en tiempo real"
echo ""

fi
