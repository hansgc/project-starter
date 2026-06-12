#!/bin/bash

set -e

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║      MinIO Docker Project Initializer    ║"
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
    PROJECT_NAME="minio-project"
  fi

  MINIO_VERSION="${MINIO_VERSION:-latest}"
  MINIO_PORT_API="${MINIO_PORT_API:-9000}"
  MINIO_PORT_CONSOLE="${MINIO_PORT_CONSOLE:-9001}"
  PROD_SERVER_IP="${PROD_SERVER_IP:-}"
  MINIO_ROOT_USER="${MINIO_ROOT_USER:-minioadmin}"
  MINIO_ROOT_PASSWORD="${MINIO_ROOT_PASSWORD:-minioadmin123}"
  MINIO_DEFAULT_BUCKET="${MINIO_DEFAULT_BUCKET:-}"
  MINIO_NETWORK="${MINIO_NETWORK:-}"

PROJECT_SLUG=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g')
MINIO_NETWORK="${MINIO_NETWORK:-proyectos-net}"

# --- Verificar red Docker ---
step "Verificando red Docker"
if ! verificar_red_docker "$MINIO_NETWORK"; then
  echo "  ❌ La red Docker '$MINIO_NETWORK' no existe."
  echo "  Créala antes de ejecutar este script:"
  echo "     docker network create $MINIO_NETWORK"
  exit 1
else
  echo "  ✓ La red '$MINIO_NETWORK' existe."
fi

# --- Crear estructura de directorios ---
step "Creando estructura de directorios"

mkdir -p "$PROJECT_SLUG"
cd "$PROJECT_SLUG"

mkdir -p aDespliegue

# --- aDespliegue/docker-compose.yml ---
step "Generando docker-compose.yml"

# Determinar si se crea un bucket inicial automáticamente
if [[ -n "${MINIO_DEFAULT_BUCKET}" ]]; then
  CREATEBUCKETS_SERVICE="
  ${PROJECT_SLUG}-init:
    image: minio/mc
    container_name: ${PROJECT_SLUG}-init
    depends_on:
      ${PROJECT_SLUG}:
        condition: service_healthy
    entrypoint: >
      /bin/sh -c \"
        mc alias set local http://${PROJECT_SLUG}:\${MINIO_PORT_API} \${MINIO_ROOT_USER} \${MINIO_ROOT_PASSWORD} &&
        mc mb --ignore-existing local/\${MINIO_DEFAULT_BUCKET} &&
        echo 'Bucket \${MINIO_DEFAULT_BUCKET} listo.'
      \"
    networks:
      - minio_network"
else
  CREATEBUCKETS_SERVICE=""
fi

cat > aDespliegue/docker-compose.yml <<YAML
services:
  ${PROJECT_SLUG}:
    image: minio/minio:\${MINIO_VERSION}
    container_name: ${PROJECT_SLUG}
    restart: unless-stopped
    env_file: .env
    command: server /data --console-address ":\${MINIO_PORT_CONSOLE}"
    environment:
      MINIO_ROOT_USER: "\${MINIO_ROOT_USER}"
      MINIO_ROOT_PASSWORD: "\${MINIO_ROOT_PASSWORD}"
    ports:
      - "\${MINIO_PORT_API}:9000"
      - "\${MINIO_PORT_CONSOLE}:9001"
    volumes:
      - ${PROJECT_SLUG}_data:/data
    networks:
      - minio_network
    healthcheck:
      test: ["CMD", "mc", "ready", "local"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 10s
${CREATEBUCKETS_SERVICE}

volumes:
  ${PROJECT_SLUG}_data:
    name: ${PROJECT_SLUG}_data

networks:
  minio_network:
    name: "\${MINIO_NETWORK}"
    external: true
YAML

# --- Generando .env y .env.example ---
step "Generando variables de entorno (.env)"

cat > aDespliegue/.env.example <<ENV
MINIO_VERSION=${MINIO_VERSION}
MINIO_PORT_API=${MINIO_PORT_API}
MINIO_PORT_CONSOLE=${MINIO_PORT_CONSOLE}
MINIO_ROOT_USER=${MINIO_ROOT_USER}
MINIO_ROOT_PASSWORD=YOUR_ROOT_PASSWORD
MINIO_DEFAULT_BUCKET=${MINIO_DEFAULT_BUCKET}
MINIO_NETWORK=${MINIO_NETWORK}
ENV

cat > aDespliegue/.env <<ENV
MINIO_VERSION=${MINIO_VERSION}
MINIO_PORT_API=${MINIO_PORT_API}
MINIO_PORT_CONSOLE=${MINIO_PORT_CONSOLE}
MINIO_ROOT_USER=${MINIO_ROOT_USER}
MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD}
MINIO_DEFAULT_BUCKET=${MINIO_DEFAULT_BUCKET}
MINIO_NETWORK=${MINIO_NETWORK}
ENV

# --- Generando Makefile ---
step "Generando Makefile"

cat > Makefile <<MAKE
.PHONY: help up down logs sh mc

MINIO_SERVICE = ${PROJECT_SLUG}

help:
	@echo "Comandos disponibles:"
	@echo "  make help     - Muestra esta ayuda"
	@echo "  make up       - Levanta el contenedor MinIO"
	@echo "  make down     - Detiene el contenedor MinIO"
	@echo "  make logs     - Muestra los logs en tiempo real"
	@echo "  make sh       - Accede al shell del contenedor"
	@echo "  make mc       - Abre el cliente mc apuntando al servidor local"

up:
	cd aDespliegue && docker compose up -d

down:
	cd aDespliegue && docker compose down

logs:
	cd aDespliegue && docker compose logs -f

sh:
	cd aDespliegue && docker compose exec \$(MINIO_SERVICE) sh

mc:
	cd aDespliegue && docker compose exec \$(MINIO_SERVICE) mc alias set local http://localhost:9000 ${MINIO_ROOT_USER} ${MINIO_ROOT_PASSWORD} && docker compose exec \$(MINIO_SERVICE) mc ls local
MAKE

# --- Generando .gitignore ---
step "Generando .gitignore"

cat > .gitignore <<GIT
aDespliegue/.env
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
    echo "API S3:          http://${PROD_SERVER_IP}:${MINIO_PORT_API}"
    echo "Consola web:     http://${PROD_SERVER_IP}:${MINIO_PORT_CONSOLE}"
  else
    echo "API S3:          http://localhost:${MINIO_PORT_API}"
    echo "Consola web:     http://localhost:${MINIO_PORT_CONSOLE}"
  fi
  echo ""
  echo "Usuario:         ${MINIO_ROOT_USER}"
  echo "Contraseña:      ${MINIO_ROOT_PASSWORD}"
  if [[ -n "${MINIO_DEFAULT_BUCKET}" ]]; then
    echo "Bucket inicial:  ${MINIO_DEFAULT_BUCKET}"
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
echo "    API S3 (puerto):    ${MINIO_PORT_API}"
echo "    Consola web:        http://localhost:${MINIO_PORT_CONSOLE}"
echo "    Usuario:            ${MINIO_ROOT_USER}"
echo "    Contraseña:         ${MINIO_ROOT_PASSWORD}"
if [[ -n "${MINIO_DEFAULT_BUCKET}" ]]; then
echo "    Bucket inicial:     ${MINIO_DEFAULT_BUCKET}"
fi
echo ""
echo "  Comandos:"
echo "    make up      → iniciar MinIO"
echo "    make down    → detener MinIO"
echo "    make logs    → ver logs en tiempo real"
echo "    make sh      → shell del contenedor"
echo "    make mc      → cliente mc (listar buckets)"
echo ""

fi
