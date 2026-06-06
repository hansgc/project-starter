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

  PMA_PORT="${PMA_PORT:-8021}"
  PROD_SERVER_IP="${PROD_SERVER_IP:-}"
  DB_HOST="${DB_HOST:-host.docker.internal}"
  DB_PORT="${DB_PORT:-3306}"
  PMA_ARBITRARY="${PMA_ARBITRARY:-1}"
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
    image: phpmyadmin:latest
    container_name: ${PROJECT_SLUG}
    restart: unless-stopped
    env_file: .env
    environment:
      PMA_HOST: "\${DB_HOST}"
      PMA_PORT: "\${DB_PORT}"
      PMA_ARBITRARY: "\${PMA_ARBITRARY}"
      PMA_ABSOLUTE_URI: "http://localhost:\${PMA_PORT}/"
    ports:
      - "\${PMA_PORT}:80"
    extra_hosts:
      - "host.docker.internal:host-gateway"
    networks:
      - db_network

networks:
  db_network:
    name: "\${DB_NETWORK}"
    external: true
YAML

cat > aDespliegue/.env.example <<ENV
PMA_PORT=${PMA_PORT}
DB_HOST=${DB_HOST}
DB_PORT=${DB_PORT}
PMA_ARBITRARY=${PMA_ARBITRARY}
DB_NETWORK=${DB_NETWORK}
ENV

cat > aDespliegue/.env <<ENV
PMA_PORT=${PMA_PORT}
DB_HOST=${DB_HOST}
DB_PORT=${DB_PORT}
PMA_ARBITRARY=${PMA_ARBITRARY}
DB_NETWORK=${DB_NETWORK}
ENV

# --- Generando Makefile ---
step "Generando Makefile"

cat > Makefile <<MAKE
.PHONY: help logs sh up down

PMA_SERVICE = ${PROJECT_SLUG}

help:
	@echo "Comandos disponibles:"
	@echo "  make help  - Muestra esta ayuda"
	@echo "  make up    - Levanta phpMyAdmin"
	@echo "  make down  - Detiene phpMyAdmin"
	@echo "  make logs  - Muestra los logs en tiempo real"
	@echo "  make sh    - Accede al shell del contenedor phpMyAdmin"

up:
	cd aDespliegue && docker compose up -d

down:
	cd aDespliegue && docker compose down

logs:
	cd aDespliegue && docker compose logs -f

sh:
	cd aDespliegue && docker compose exec \${PMA_SERVICE} sh
MAKE

# --- Generando .gitignore ---
step "Generando .gitignore"

cat > .gitignore <<GIT
aDespliegue/.env
GIT

# --- Generando leeme.txt ---
step "Generando leeme.txt"

{
  echo "Para levantar phpMyAdmin:"
  echo "  make up"
  echo ""
  echo "Para detener phpMyAdmin:"
  echo "  make down"
  echo ""
  echo "Para ver logs:"
  echo "  make logs"
  echo ""
  if [[ -n "${PROD_SERVER_IP}" ]]; then
    echo "Acceso: http://${PROD_SERVER_IP}:${PMA_PORT}"
  else
    echo "Acceso: http://localhost:${PMA_PORT}"
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
echo "  Acceso Web:"
echo "    URL:         http://localhost:${PMA_PORT}"
echo "    Host MySQL:  ${DB_HOST}"
if [[ -n "$DB_NETWORK" ]]; then
  echo "    Red Docker:  ${DB_NETWORK} (externa)"
fi
echo "    Port MySQL:  ${DB_PORT}"
echo ""
echo "  Comandos:"
echo "    make up    → iniciar phpMyAdmin"
echo "    make down  → detener phpMyAdmin"
echo "    make logs  → ver logs en tiempo real"
echo ""

fi
