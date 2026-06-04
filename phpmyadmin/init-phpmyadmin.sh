#!/bin/bash

set -e

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║     phpMyAdmin Project Initializer       ║"
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
    PROJECT_NAME="pma-project"
  fi

  PMA_PORT_DEV="${PMA_PORT_DEV:-${PMA_PORT:-8081}}"
  PMA_PORT_PROD="${PMA_PORT_PROD:-80}"
  PMA_HOST="${PMA_HOST:-host.docker.internal}"
  PMA_DB_PORT="${PMA_DB_PORT:-3306}"
  PMA_ARBITRARY="${PMA_ARBITRARY:-1}"
  DB_NETWORK="${DB_NETWORK:-}"

else
  # --- Modo interactivo ---
  echo "Tip: podés crear un archivo .conf y correr: init-phpmyadmin.sh mi-proyecto.conf"
  echo ""

  read -p "Nombre del proyecto: " PROJECT_NAME
  if [[ -z "$PROJECT_NAME" ]]; then
    echo "Error: el nombre no puede estar vacío."; exit 1
  fi

  PMA_PORT_DEV=$(ask_input "Puerto local dev para acceder al panel web" "8081")
  PMA_PORT_PROD=$(ask_input "Puerto local prod para acceder al panel web" "80")
  PMA_HOST=$(ask_input "Host de la base de datos MySQL (ej: host.docker.internal o nombre-contenedor)" "host.docker.internal")
  PMA_DB_PORT=$(ask_input "Puerto de la base de datos MySQL" "3306")
  DB_NETWORK=$(ask_input "Red Docker externa a unirse (dejar vacío para usar host.docker.internal)" "")

  PMA_ARBITRARY=0
  ask_yn "Permitir ingresar cualquier Host en la pantalla de login?" "s" && PMA_ARBITRARY=1
fi

PROJECT_SLUG=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g')

# --- Crear estructura de directorios ---
step "Creando estructura de directorios"

mkdir -p "$PROJECT_SLUG"
cd "$PROJECT_SLUG"

mkdir -p aDespliegue/dev
mkdir -p aDespliegue/prod

# --- aDespliegue/dev/docker-compose.yml ---
step "Generando docker-compose.yml dev"

if [[ -n "$DB_NETWORK" ]]; then
  # Con red externa: phpMyAdmin se une a la red del contenedor MySQL
  cat > aDespliegue/dev/docker-compose.yml <<YAML
services:
  ${PROJECT_SLUG}_pma_dev:
    image: phpmyadmin:latest
    container_name: ${PROJECT_SLUG}_pma_dev
    restart: "no"
    environment:
      PMA_HOST: "\${PMA_HOST}"
      PMA_PORT: "\${PMA_DB_PORT}"
      PMA_ARBITRARY: "\${PMA_ARBITRARY}"
      PMA_ABSOLUTE_URI: "http://localhost:\${PMA_PORT_DEV}/"
    ports:
      - "\${PMA_PORT_DEV}:80"
    networks:
      - db_external

networks:
  db_external:
    name: ${DB_NETWORK}
    external: true
YAML
else
  # Sin red externa: usa host.docker.internal
  cat > aDespliegue/dev/docker-compose.yml <<YAML
services:
  ${PROJECT_SLUG}_pma_dev:
    image: phpmyadmin:latest
    container_name: ${PROJECT_SLUG}_pma_dev
    restart: "no"
    environment:
      PMA_HOST: "\${PMA_HOST}"
      PMA_PORT: "\${PMA_DB_PORT}"
      PMA_ARBITRARY: "\${PMA_ARBITRARY}"
      PMA_ABSOLUTE_URI: "http://localhost:\${PMA_PORT_DEV}/"
    ports:
      - "\${PMA_PORT_DEV}:80"
    extra_hosts:
      - "host.docker.internal:host-gateway"
    networks:
      - ${PROJECT_SLUG}_net

networks:
  ${PROJECT_SLUG}_net:
    name: ${PROJECT_SLUG}_net
YAML
fi

# --- aDespliegue/prod/docker-compose.yml ---
step "Generando docker-compose.yml prod"

if [[ -n "$DB_NETWORK" ]]; then
  # Con red externa: phpMyAdmin se une a la red del contenedor MySQL
  cat > aDespliegue/prod/docker-compose.yml <<YAML
services:
  ${PROJECT_SLUG}_pma_prod:
    image: phpmyadmin:latest
    container_name: ${PROJECT_SLUG}_pma_prod
    restart: unless-stopped
    environment:
      PMA_HOST: "\${PMA_HOST}"
      PMA_PORT: "\${PMA_DB_PORT}"
      PMA_ARBITRARY: "\${PMA_ARBITRARY}"
      PMA_ABSOLUTE_URI: "http://localhost:\${PMA_PORT_PROD}/"
    ports:
      - "\${PMA_PORT_PROD}:80"
    networks:
      - db_external

networks:
  db_external:
    name: ${DB_NETWORK}
    external: true
YAML
else
  # Sin red externa: usa host.docker.internal
  cat > aDespliegue/prod/docker-compose.yml <<YAML
services:
  ${PROJECT_SLUG}_pma_prod:
    image: phpmyadmin:latest
    container_name: ${PROJECT_SLUG}_pma_prod
    restart: unless-stopped
    environment:
      PMA_HOST: "\${PMA_HOST}"
      PMA_PORT: "\${PMA_DB_PORT}"
      PMA_ARBITRARY: "\${PMA_ARBITRARY}"
      PMA_ABSOLUTE_URI: "http://localhost:\${PMA_PORT_PROD}/"
    ports:
      - "\${PMA_PORT_PROD}:80"
    extra_hosts:
      - "host.docker.internal:host-gateway"
    networks:
      - ${PROJECT_SLUG}_prod_net

networks:
  ${PROJECT_SLUG}_prod_net:
    name: ${PROJECT_SLUG}_prod_net
YAML
fi

# --- Generando .env y .env.example ---
step "Generando variables de entorno (.env)"

cat > .env.example <<ENV
PMA_PORT_DEV=${PMA_PORT_DEV}
PMA_PORT_PROD=${PMA_PORT_PROD}
PMA_HOST=${PMA_HOST}
PMA_DB_PORT=${PMA_DB_PORT}
PMA_ARBITRARY=${PMA_ARBITRARY}
DB_NETWORK=${DB_NETWORK}
ENV

cat > .env <<ENV
PMA_PORT_DEV=${PMA_PORT_DEV}
PMA_PORT_PROD=${PMA_PORT_PROD}
PMA_HOST=${PMA_HOST}
PMA_DB_PORT=${PMA_DB_PORT}
PMA_ARBITRARY=${PMA_ARBITRARY}
DB_NETWORK=${DB_NETWORK}
ENV

# --- Generando Makefile ---
step "Generando Makefile"

cat > Makefile <<MAKE
.PHONY: up down start stop logs sh dev-up dev-down prod-up prod-down

ENV ?= dev
ENV_DIR = aDespliegue/\$(ENV)
PMA_SERVICE_dev = ${PROJECT_SLUG}_pma_dev
PMA_SERVICE_prod = ${PROJECT_SLUG}_pma_prod
PMA_SERVICE = \$(PMA_SERVICE_\$(ENV))
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
	docker compose --env-file .env -f \$(ENV_DIR)/docker-compose.yml exec \$(PMA_SERVICE) sh

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
GIT

# --- Levantando el contenedor ---
step "Levantando contenedor phpMyAdmin..."
docker compose --env-file .env -f aDespliegue/dev/docker-compose.yml up -d

# Esperar a que phpMyAdmin esté listo
echo "Esperando que el contenedor phpMyAdmin esté listo..."
sleep 2

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
echo "  Acceso Web:"
echo "    URL dev:     http://localhost:${PMA_PORT_DEV}"
echo "    URL prod:    http://localhost:${PMA_PORT_PROD}"
echo "    Host MySQL:  ${PMA_HOST}"
if [[ -n "$DB_NETWORK" ]]; then
  echo "    Red Docker:  ${DB_NETWORK} (externa)"
fi
echo "    Port MySQL:  ${PMA_DB_PORT}"
echo ""
echo "  Comandos:"
echo "    make start  → iniciar phpMyAdmin"
echo "    make stop   → detener phpMyAdmin"
echo "    make logs   → ver logs en tiempo real"
echo "    make prod-up → iniciar phpMyAdmin en prod"
echo ""
