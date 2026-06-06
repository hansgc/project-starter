#!/bin/bash

# =============================================================================
# Symfony Project Initializer
# Estructura: proyecto/
#   ├── .devcontainer/
#   ├── aDespliegue/
#   │   ├── dev/
#   │   └── prod/
#   └── app/   ← symfony new
# =============================================================================

set -e
echo ""
echo "╔══════════════════════════════════════════╗"
echo "║      PHP Docker Project Initializer      ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
urlencode() {
  local string="${1}"
  local strlen=${#string}
  local encoded=""
  local pos c o
  for (( pos=0 ; pos<strlen ; pos++ )); do
     c=${string:$pos:1}
     case "$c" in
        [-_.~a-zA-Z0-9] ) o="${c}" ;;
        * )               printf -v o '%%%02X' "'$c"
     esac
     encoded+="${o}"
  done
  echo "${encoded}"
}

escape_symfony_env_percents() {
  echo "${1//%/%%}"
}

step() {
  echo ""
  echo "$1"
}

# ── Verificar si un contenedor Docker está levantado ────────────
verificar_contenedor_docker() {
  local container_name=$1
  if docker ps --format "table {{.Names}}" 2>/dev/null | grep -q "^${container_name}$"; then
    return 0  # Contenedor está levantado
  else
    return 1  # Contenedor NO está levantado
  fi
}

# ── Verificar contenedores requeridos ──────────────────────────
verificar_contenedores_requeridos() {
  local db_container=$1
  local backup_container=$2

  # Verificar base de datos
  if ! verificar_contenedor_docker "$db_container"; then
    echo ""
    echo "❌ Error crítico: El contenedor de base de datos '$db_container' no está levantado."
    echo "   Por favor, levanta el contenedor de MySQL y luego vuelve a ejecutar este script."
    echo "   Comando: docker-compose up -d (en tu proyecto de MySQL)"
    echo ""
    exit 1
  fi
  echo "  ✓ Contenedor de MySQL '$db_container' está levantado."

  # Verificar backup si se definió BACKUP_CONTAINER_NAME
  if [[ -n "$backup_container" ]]; then
    if ! verificar_contenedor_docker "$backup_container"; then
      echo ""
      echo "❌ Error crítico: El contenedor de backup '$backup_container' no está levantado."
      echo "   Se configuró BACKUP_CONTAINER_NAME='$backup_container', pero el contenedor no está disponible."
      echo "   Por favor, levanta el contenedor de backup y luego vuelve a ejecutar este script."
      echo "   Comando: docker-compose up -d <servicio-de-backup> (en tu proyecto de backup)"
      echo ""
      exit 1
    fi
    echo "  ✓ Contenedor de backup '$backup_container' está levantado."
  fi
}

# -----------------------------------------------------------------------------
# 1. Fuente de configuración: archivo o modo interactivo
# -----------------------------------------------------------------------------
CONFIG_FILE="${1:-}"

bool() {
  # Normaliza "true/false/si/no/1/0/yes/no" a true/false bash
  [[ "${1,,}" =~ ^(true|si|sí|yes|1)$ ]]
}

bool_default_true() {
  # Solo desactiva si el valor es explícitamente falso.
  [[ ! "${1,,}" =~ ^(false|no|0)$ ]]
}

if [[ -n "$CONFIG_FILE" ]]; then
  # ── Modo archivo ────────────────────────────────────────────────────────────
  if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Error: no se encontró el archivo '$CONFIG_FILE'"; exit 1
  fi

  echo "Leyendo configuración desde: $CONFIG_FILE"

  # Cargar variables ignorando comentarios y líneas vacías
  while IFS='=' read -r key value; do
    [[ "$key" =~ ^#.*$ || -z "$key" ]] && continue
    key=$(echo "$key" | tr -d ' ')
    value=$(echo "$value" | tr -d '"' | tr -d "'" | sed 's/[[:space:]][[:space:]]*#.*//' | xargs)
    declare "$key=$value"
  done < "$CONFIG_FILE"

  # Derivar PROJECT_NAME del nombre del archivo de configuración
  CONFIG_BASENAME=$(basename "$CONFIG_FILE" .conf)
  PROJECT_NAME=${CONFIG_BASENAME#project_}
  PROJECT_NAME=${PROJECT_NAME#php_}
  if [[ -z "${PROJECT_NAME:-}" ]]; then
    echo "Error: PROJECT_NAME es obligatorio en el archivo de config."; exit 1
  fi

  # Aplicar defaults para campos opcionales
  PHP_VERSION="${PHP_VERSION:-8.4}"
  PORT_DEV="${PORT_DEV:-${HTTP_PORT:-8080}}"
  PORT_PROD="${PORT_PROD:-${PROD_HTTP_PORT:-80}}"
  PROD_SERVER_IP="${PROD_SERVER_IP:-${PROD_SERVER_IPS:-}}"
  PROD_URLS="${PROD_URLS:-}"

  echo ""
  while IFS='=' read -r key value; do
    [[ "$key" =~ ^#.*$ || -z "$key" ]] && continue
    key=$(echo "$key" | tr -d ' ')
    value=$(echo "$value" | tr -d '"' | tr -d "'" | sed 's/[[:space:]]*#.*//' | xargs)
    printf "  %s=%s\n" "$key" "$value"
  done < "$CONFIG_FILE"
  echo ""
  HTTP_PORT="${PORT_DEV}"
  PROD_HTTP_PORT="${PORT_PROD}"
  DB_NETWORK="${DB_NETWORK:-}"
  SYMFONY_INSTALL="${SYMFONY_INSTALL:-minimal}"

  BACKUP_CONTAINER_NAME="${BACKUP_CONTAINER_NAME:-}"

  bool_default_true "${USE_SYMFONY:-true}" && USE_SYMFONY=true || USE_SYMFONY=false
  bool "${USE_AUTH:-false}"         && USE_AUTH=true         || USE_AUTH=false
  bool "${USE_JWT:-false}"          && USE_JWT=true          || USE_JWT=false
  bool "${USE_ADMIN:-false}"        && USE_ADMIN=true        || USE_ADMIN=false
  




else
  # ── Modo interactivo ────────────────────────────────────────────────────────
  echo "Tip: podés crear un archivo .conf y correr: init-php.sh mi-proyecto.conf"
  echo ""

  read -p "Nombre del proyecto: " PROJECT_NAME
  if [[ -z "$PROJECT_NAME" ]]; then
    echo "Error: el nombre no puede estar vacío."; exit 1
  fi

  PHP_VERSION=$(ask_input "Versión de PHP" "8.3")
  PORT_DEV=$(ask_input "Puerto HTTP desarrollo" "8080")
  PORT_PROD=$(ask_input "Puerto HTTP producción" "80")
  PROD_SERVER_IP=$(ask_input "IP servidor producción" "")
  PROD_URLS=""
  HTTP_PORT="${PORT_DEV}"
  PROD_HTTP_PORT="${PORT_PROD}"
  SYMFONY_INSTALL="minimal"
  DB_NETWORK=""

  echo ""
  DB_HOST=$(ask_input "Host de base de datos (vacío para omitir DB)" "host.docker.internal")

  echo ""
  echo "Módulos a incluir:"

  USE_SYMFONY=false;      ask_yn "Framework Symfony" "s"                        && USE_SYMFONY=true
  USE_AUTH=false
  USE_JWT=false
  USE_ADMIN=false
  if $USE_SYMFONY; then
    ask_yn "Autenticación (Symfony Security)" "n"                                && USE_AUTH=true
    if $USE_AUTH; then
      ask_yn "  ↳ JWT (LexikJWTAuthenticationBundle)" "n" && USE_JWT=true
    fi
    ask_yn "Panel de administración (EasyAdmin)" "n"                             && USE_ADMIN=true
  fi
  # API Platform, Messenger, Mailer are disabled and not prompted
fi

# Los módulos actuales de framework son específicos de Symfony.
if ! $USE_SYMFONY; then
  USE_AUTH=false
  USE_JWT=false
  USE_ADMIN=false
fi

# EasyAdmin necesita Doctrine (aplica en ambos modos)
if $USE_ADMIN && [[ -z "${DB_HOST:-}" ]] && [[ -z "${DB_HOST_DEV:-}" ]]; then
  echo ""
  echo "⚠ EasyAdmin requiere base de datos. Se activará DB_HOST_DEV por defecto."
  DB_HOST_DEV="host.docker.internal"
fi

# Backup necesita Doctrine (aplica en ambos modos)
if [[ -n "$BACKUP_CONTAINER_NAME" ]] && [[ -z "${DB_HOST:-}" ]] && [[ -z "${DB_HOST_DEV:-}" ]]; then
  echo ""
  echo "⚠ Backup requiere base de datos. Se activará DB_HOST_DEV por defecto."
  DB_HOST_DEV="host.docker.internal"
fi

PROJECT_SLUG=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g')

# Inicializar y resolver variables de base de datos de DEV y PROD con fallbacks
DB_HOST="${DB_HOST:-}"
DB_HOST_DEV="${DB_HOST_DEV:-${DB_HOST:-host.docker.internal}}"
DB_HOST_PROD="${DB_HOST_PROD:-${DB_HOST:-host.docker.internal}}"

DB_NAME="${DB_NAME:-}"
DB_NAME_DEV="${DB_NAME_DEV:-${DB_NAME:-${PROJECT_SLUG}}}"
DB_NAME_PROD="${DB_NAME_PROD:-${DB_NAME:-${PROJECT_SLUG}}}"

DB_USER="${DB_USER:-}"
DB_USER_DEV="${DB_USER_DEV:-${DB_USER:-app}}"
DB_USER_PROD="${DB_USER_PROD:-${DB_USER:-app}}"

DB_PASSWORD="${DB_PASSWORD:-}"
DB_PASSWORD_DEV="${DB_PASSWORD_DEV:-${DB_PASSWORD:-secret}}"
DB_PASSWORD_PROD="${DB_PASSWORD_PROD:-${DB_PASSWORD:-secret}}"

DB_PORT_DEV="${DB_PORT_DEV:-3306}"
DB_PORT_PROD="${DB_PORT_PROD:-3306}"

DB_NETWORK="${DB_NETWORK:-}"
DB_NETWORK_DEV="${DB_NETWORK_DEV:-${DB_NETWORK}}"
DB_NETWORK_PROD="${DB_NETWORK_PROD:-${DB_NETWORK}}"

# -----------------------------------------------------------------------------
# Verificar contenedores Docker requeridos antes de continuar
# -----------------------------------------------------------------------------
if [[ -n "${DB_HOST_DEV:-}" ]]; then
  step "Verificando contenedores Docker requeridos"
  DB_CONTAINER="${DB_HOST_DEV:-mysql}"
  verificar_contenedores_requeridos "$DB_CONTAINER" "$BACKUP_CONTAINER_NAME"
fi
DEV_PHP_SERVICE="${PROJECT_SLUG}-php-dev"
DEV_PHP_NAME="${PROJECT_SLUG}-php-dev"
PROD_PHP_SERVICE="${PROJECT_SLUG}-php-prod"
PROD_PHP_NAME="${PROJECT_SLUG}-php-prod"
PROD_NGINX_SERVICE="${PROJECT_SLUG}-nginx-prod"
PROD_NGINX_NAME="${PROJECT_SLUG}-nginx-prod"
DEV_NETWORK_NAME="${PROJECT_SLUG}-php-dev_net"
PROD_NETWORK_NAME="${PROJECT_SLUG}-php-prod_net"

# -----------------------------------------------------------------------------
# 3. Validar base de datos antes de crear directorios
# -----------------------------------------------------------------------------
if [[ -n "${DB_HOST_DEV:-}" ]]; then
  # Cargar defaults si existen
  if [[ -f "$HOME/.symfony-defaults" ]]; then
    while IFS="=" read -r key value; do
      [[ "$key" =~ ^#.*$ || -z "$key" ]] && continue
      key=$(echo "$key" | tr -d " ")
      value=$(echo "$value" | tr -d "\"" | tr -d "\047" | xargs)
      declare "DEFAULT_${key}=$value"
    done < "$HOME/.symfony-defaults"
  fi
  CHECK_DB_USER="${DB_USER_DEV:-${DEFAULT_DB_USER:-app}}"
  CHECK_DB_PASSWORD="${DB_PASSWORD_DEV:-${DEFAULT_DB_PASSWORD:-secret}}"
  CHECK_DB_HOST="${DB_HOST_DEV:-${DEFAULT_DB_HOST:-host.docker.internal}}"
  CHECK_DB_PORT="${DB_PORT_DEV:-${DEFAULT_DB_PORT_DEV:-3306}}"
  CHECK_DB_NAME="${DB_NAME_DEV:-${PROJECT_SLUG}}"

  echo "Verificando base de datos antes de iniciar..."

  DB_EXISTS=false
  VERIFIED=false

  # Método 1: Si el host de la base de datos es un contenedor Docker corriendo localmente
  if docker ps --format '{{.Names}}' | grep -Eq "^${CHECK_DB_HOST}$"; then
    if docker exec "${CHECK_DB_HOST}" mysql -u"${CHECK_DB_USER}" -p"${CHECK_DB_PASSWORD}" -e "USE \`${CHECK_DB_NAME}\`;" &>/dev/null; then
      DB_EXISTS=true
    fi
    VERIFIED=true
  fi

  # Método 2: Si el host tiene instalado el cliente mysql
  if ! $VERIFIED && command -v mysql &>/dev/null; then
    if mysql -h"${CHECK_DB_HOST}" -P"${CHECK_DB_PORT}" -u"${CHECK_DB_USER}" -p"${CHECK_DB_PASSWORD}" -e "USE \`${CHECK_DB_NAME}\`;" &>/dev/null; then
      DB_EXISTS=true
    fi
    VERIFIED=true
  fi

  # Método 3: Si el host tiene php con pdo_mysql
  if ! $VERIFIED && command -v php &>/dev/null && php -m | grep -q "pdo_mysql"; then
    if php -r "new PDO('mysql:host=${CHECK_DB_HOST};port=${CHECK_DB_PORT};dbname=${CHECK_DB_NAME}', '${CHECK_DB_USER}', '${CHECK_DB_PASSWORD}');" &>/dev/null; then
      DB_EXISTS=true
    fi
    VERIFIED=true
  fi

  if $VERIFIED; then
    if ! $DB_EXISTS; then
      echo ""
      echo "❌ Error crítico: La base de datos '${CHECK_DB_NAME}' no existe en el servidor '${CHECK_DB_HOST}:${CHECK_DB_PORT}'."
      echo "   Por favor, crea la base de datos en tu MySQL y otorga los privilegios al usuario '${CHECK_DB_USER}'."
      echo "   Puedes crearla ejecutando el siguiente código SQL (como root):"
      echo ""
      echo "     CREATE DATABASE \`${CHECK_DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
      echo "     GRANT ALL PRIVILEGES ON \`${CHECK_DB_NAME}\`.* TO '${CHECK_DB_USER}'@'%';"
      echo "     FLUSH PRIVILEGES;"
      echo ""
      exit 1
    else
      echo "  ✓ Conexión exitosa. La base de datos '${CHECK_DB_NAME}' existe y es accesible."
    fi
  else
    echo ""
    echo "❌ Error crítico: No se encontró ningún método para verificar la existencia de la base de datos desde el host."
    echo "   Para poder continuar, el script necesita verificar si la base de datos '${CHECK_DB_NAME}' existe."
    echo "   Por favor, asegúrate de cumplir con al menos una de las siguientes opciones:"
    echo "     1. Tener el contenedor de base de datos '${CHECK_DB_HOST}' iniciado y en ejecución (si usas Docker)."
    echo "     2. Instalar el cliente de MySQL en tu sistema host (ej. 'sudo apt install mysql-client' o similar)."
    echo "     3. Instalar PHP con el driver PDO MySQL en tu sistema host (ej. 'sudo apt install php-mysql' o similar)."
    echo ""
    exit 1
  fi
fi

# -----------------------------------------------------------------------------
# 4. Crear estructura de directorios
# -----------------------------------------------------------------------------
step "Creando estructura de directorios"

# Capturar ruta del script ANTES del cd (BASH_SOURCE[0] es relativo al CWD actual)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STUBS_DIR="$SCRIPT_DIR/stubs"

mkdir -p "$PROJECT_SLUG"
cd "$PROJECT_SLUG"

mkdir -p .devcontainer
mkdir -p aDespliegue/dev
mkdir -p aDespliegue/prod
mkdir -p app

# -----------------------------------------------------------------------------
# 5. aDespliegue/dev/Dockerfile
# -----------------------------------------------------------------------------
step "Generando Dockerfile dev"

if $USE_SYMFONY; then
  DEV_EXTENSIONS="intl opcache zip"
  DEV_APT="wget git curl unzip libicu-dev libonig-dev libxml2-dev libzip-dev procps"
else
  DEV_EXTENSIONS=""
  DEV_APT="wget curl procps"
fi
[[ -n "${DB_HOST:-}" ]] && DEV_APT+=" default-libmysqlclient-dev"         && DEV_EXTENSIONS+=" pdo pdo_mysql"

DEV_INSTALL_EXTENSIONS="&& true"
if [[ -n "$DEV_EXTENSIONS" ]]; then
  DEV_INSTALL_EXTENSIONS="&& docker-php-ext-install ${DEV_EXTENSIONS}"
fi

if $USE_SYMFONY; then
  cat > aDespliegue/dev/Dockerfile <<DOCKERFILE
FROM php:${PHP_VERSION}-fpm

RUN apt-get update && apt-get install -y \\
    ${DEV_APT} \\
    ${DEV_INSTALL_EXTENSIONS} \\
    && apt-get clean && rm -rf /var/lib/apt/lists/*

COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# Symfony CLI
RUN curl -sS https://get.symfony.com/cli/installer | bash \\
 && mv /root/.symfony*/bin/symfony /usr/local/bin/symfony \\
 && mkdir -p /root/.config \\
 && (mv /root/.symfony5 /root/.config/symfony-cli 2>/dev/null || true)

WORKDIR /workspace/app

EXPOSE 8000

CMD ["bash", "-c", "rm -f /root/.config/symfony-cli/var/*.pid /root/.config/symfony-cli/var/*.port && exec symfony server:start --no-tls --port=8000 --allow-all-ip"]
DOCKERFILE
else
  cat > aDespliegue/dev/Dockerfile <<DOCKERFILE
FROM php:${PHP_VERSION}-fpm

RUN apt-get update && apt-get install -y \\
    ${DEV_APT} \\
    ${DEV_INSTALL_EXTENSIONS} \\
    && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace/app

EXPOSE 8000

CMD ["php", "-S", "0.0.0.0:8000", "-t", "/workspace/app/public"]
DOCKERFILE
fi

# -----------------------------------------------------------------------------
# 6. aDespliegue/dev/docker-compose.yml
# -----------------------------------------------------------------------------
step "Generando docker-compose.yml dev"

DEV_DB_NETWORK=""
DEV_EXTERNAL_NETWORK=""
if [[ -n "${DB_HOST_DEV:-}" ]] && [[ -n "$DB_NETWORK_DEV" && "$DB_NETWORK_DEV" != "${DEV_NETWORK_NAME}" ]]; then
  DEV_DB_NETWORK="      - ${DB_NETWORK_DEV}"
  DEV_EXTERNAL_NETWORK=$(printf '  %s:\n    external: true' "$DB_NETWORK_DEV")
fi

cat > aDespliegue/dev/docker-compose.yml <<YAML
services:
  ${DEV_PHP_SERVICE}:
    image: ${DEV_PHP_NAME}
    build:
      context: ../..
      dockerfile: aDespliegue/dev/Dockerfile
    container_name: ${DEV_PHP_NAME}
    restart: "no"
    env_file: .env
    ports:
      - "\${PORT_DEV}:8000"
    volumes:
      - ../../:/workspace
    environment:
      APP_ENV: dev
      APP_DEBUG: "1"
      DATABASE_URL: "\${DATABASE_URL}"
    networks:
      - ${DEV_NETWORK_NAME}
${DEV_DB_NETWORK}
YAML

[[ -n "${DB_HOST_DEV:-}" ]] && cat >> aDespliegue/dev/docker-compose.yml <<YAML
    extra_hosts:
      - "host.docker.internal:host-gateway"
YAML

cat >> aDespliegue/dev/docker-compose.yml <<YAML

networks:
  ${DEV_NETWORK_NAME}:
    name: ${DEV_NETWORK_NAME}
${DEV_EXTERNAL_NETWORK}
YAML

# -----------------------------------------------------------------------------
# 8. aDespliegue/prod/Dockerfile
# -----------------------------------------------------------------------------
step "Generando Dockerfile prod"

if $USE_SYMFONY; then
  PROD_EXTENSIONS="intl opcache zip"
  PROD_APT="git curl unzip libicu-dev libonig-dev libxml2-dev libzip-dev"
  [[ -n "${DB_HOST:-}" ]] && PROD_APT+=" default-libmysqlclient-dev" && PROD_EXTENSIONS+=" pdo pdo_mysql"

  cat > aDespliegue/prod/Dockerfile <<DOCKERFILE
FROM php:${PHP_VERSION}-fpm AS builder

RUN apt-get update && apt-get install -y \\
    ${PROD_APT} \\
    && docker-php-ext-install ${PROD_EXTENSIONS} \\
    && apt-get clean && rm -rf /var/lib/apt/lists/*

COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

WORKDIR /workspace
COPY app/ .

RUN composer install --no-dev --optimize-autoloader --no-interaction

# --- Runtime image ---
FROM php:${PHP_VERSION}-fpm

RUN apt-get update && apt-get install -y \\
    ${PROD_APT} \\
    && docker-php-ext-install ${PROD_EXTENSIONS} \\
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Opcache tuning para producción
RUN echo "opcache.enable=1" >> /usr/local/etc/php/conf.d/opcache.ini \\
 && echo "opcache.memory_consumption=256" >> /usr/local/etc/php/conf.d/opcache.ini \\
 && echo "opcache.max_accelerated_files=20000" >> /usr/local/etc/php/conf.d/opcache.ini \\
 && echo "opcache.validate_timestamps=0" >> /usr/local/etc/php/conf.d/opcache.ini

WORKDIR /workspace
COPY --from=builder /workspace .

EXPOSE 9000
DOCKERFILE
else
  cat > aDespliegue/prod/Dockerfile <<DOCKERFILE
FROM php:${PHP_VERSION}-fpm

# Opcache tuning para producción
RUN docker-php-ext-install opcache \\
 && echo "opcache.enable=1" >> /usr/local/etc/php/conf.d/opcache.ini \\
 && echo "opcache.memory_consumption=128" >> /usr/local/etc/php/conf.d/opcache.ini \\
 && echo "opcache.max_accelerated_files=10000" >> /usr/local/etc/php/conf.d/opcache.ini \\
 && echo "opcache.validate_timestamps=0" >> /usr/local/etc/php/conf.d/opcache.ini

WORKDIR /workspace
COPY app/ .

EXPOSE 9000
DOCKERFILE
fi

# -----------------------------------------------------------------------------
# 9. aDespliegue/prod/docker-compose.yml
# -----------------------------------------------------------------------------
PROD_DB_NETWORK=""
PROD_EXTERNAL_NETWORK=""
if [[ -n "${DB_HOST_PROD:-}" ]] && [[ -n "$DB_NETWORK_PROD" && "$DB_NETWORK_PROD" != "${PROD_NETWORK_NAME}" ]]; then
  PROD_DB_NETWORK="      - ${DB_NETWORK_PROD}"
  PROD_EXTERNAL_NETWORK=$(printf '  %s:\n    external: true' "$DB_NETWORK_PROD")
fi

cat > aDespliegue/prod/docker-compose.yml <<YAML
services:
  ${PROD_PHP_SERVICE}:
    image: ${PROD_PHP_NAME}
    build:
      context: ../..
      dockerfile: aDespliegue/prod/Dockerfile
    container_name: ${PROD_PHP_NAME}
    restart: unless-stopped
    env_file: .env
    environment:
      APP_ENV: prod
      APP_DEBUG: "0"
      DATABASE_URL: "\${DATABASE_URL}"
    networks:
      - ${PROD_NETWORK_NAME}
${PROD_DB_NETWORK}
YAML

[[ -n "${DB_HOST_PROD:-}" ]] && cat >> aDespliegue/prod/docker-compose.yml <<YAML
    extra_hosts:
      - "host.docker.internal:host-gateway"
YAML

cat >> aDespliegue/prod/docker-compose.yml <<YAML

  ${PROD_NGINX_SERVICE}:
    image: nginx:alpine
    container_name: ${PROD_NGINX_NAME}
    restart: unless-stopped
    ports:
      - "\${PORT_PROD}:80"
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf
    depends_on:
      - ${PROD_PHP_SERVICE}
    networks:
      - ${PROD_NETWORK_NAME}

networks:
  ${PROD_NETWORK_NAME}:
    name: ${PROD_NETWORK_NAME}
${PROD_EXTERNAL_NETWORK}
YAML

# -----------------------------------------------------------------------------
# 10. aDespliegue/prod/nginx.conf
# -----------------------------------------------------------------------------
step "Generando nginx.conf prod"

cat > aDespliegue/prod/nginx.conf <<NGINX
server {
    listen 80;
    server_name _;
    root /workspace/public;

    index index.php;

    location / {
        try_files \$uri /index.php\$is_args\$args;
    }

    location ~ ^/index\\.php(/|$) {
        fastcgi_pass ${PROD_PHP_SERVICE}:9000;
        fastcgi_split_path_info ^(.+\\.php)(/.*)$;
        include fastcgi_params;

        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        fastcgi_param DOCUMENT_ROOT \$realpath_root;
        internal;
    }

    location ~ \\.php$ {
        return 404;
    }
}
NGINX

# -----------------------------------------------------------------------------
# 11. .devcontainer/devcontainer.json
# -----------------------------------------------------------------------------
step "Generando .devcontainer"

cat > .devcontainer/devcontainer.json <<JSON
{
  "name": "${PROJECT_NAME}",
  "dockerComposeFile": ["../aDespliegue/dev/docker-compose.yml"],
  "service": "${DEV_PHP_SERVICE}",
  "workspaceFolder": "/workspace",
  "remoteUser": "root",

  "customizations": {
    "vscode": {
      "extensions": [
        "bmewburn.vscode-intelephense-client",
        "mrmlnc.vscode-apache",
        "ikappas.phpcs",
        "junstyle.php-cs-fixer",
        "symfony.vscode-symfony"
      ],
      "settings": {
        "php.validate.executablePath": "/usr/local/bin/php",
        "php.debug.executablePath": "/usr/local/bin/php",
        "intelephense.environment.phpVersion": "${PHP_VERSION}",
        "editor.formatOnSave": true,
        "[php]": {
          "editor.defaultFormatter": "junstyle.php-cs-fixer"
        }
      }
    }
  },
  "postCreateCommand": "cd /workspace/app && composer install"
}
JSON

if ! $USE_SYMFONY; then
  cat > .devcontainer/devcontainer.json <<JSON
{
  "name": "${PROJECT_NAME}",
  "dockerComposeFile": ["../aDespliegue/dev/docker-compose.yml"],
  "service": "${DEV_PHP_SERVICE}",
  "workspaceFolder": "/workspace",
  "remoteUser": "root",
  "customizations": {
    "vscode": {
      "extensions": [
        "bmewburn.vscode-intelephense-client",
        "ikappas.phpcs",
        "junstyle.php-cs-fixer"
      ],
      "settings": {
        "php.validate.executablePath": "/usr/local/bin/php",
        "php.debug.executablePath": "/usr/local/bin/php",
        "intelephense.environment.phpVersion": "${PHP_VERSION}",
        "editor.formatOnSave": true,
        "[php]": {
          "editor.defaultFormatter": "junstyle.php-cs-fixer"
        }
      }
    }
  }
}
JSON
fi

# -----------------------------------------------------------------------------
# 11. Generando variables de entorno y secretos
# -----------------------------------------------------------------------------
step "Generando archivos .env de configuración"

APP_SECRET=$(openssl rand -hex 16)
DEV_ADMIN_LOGIN="${ADMIN_LOGIN:-}"
DEV_ADMIN_PASSWORD="${ADMIN_PASSWORD:-}"
ADMIN_CREDENTIALS_CONFIGURED=false
ADMIN_USER_CREATED=false
if [[ -n "${DEV_ADMIN_LOGIN}" && -n "${DEV_ADMIN_PASSWORD}" ]]; then
  ADMIN_CREDENTIALS_CONFIGURED=true
fi

# Generar URLs de conexión para DEV y PROD
DEV_DATABASE_URL=""
if [[ -n "${DB_HOST_DEV:-}" ]]; then
  ENCODED_DEV_USER=$(urlencode "${DB_USER_DEV}")
  ENCODED_DEV_PASSWORD=$(urlencode "${DB_PASSWORD_DEV}")
  DEV_DATABASE_URL="mysql://${ENCODED_DEV_USER}:${ENCODED_DEV_PASSWORD}@${DB_HOST_DEV}:${DB_PORT_DEV}/${DB_NAME_DEV}"
  DEV_DATABASE_URL=$(escape_symfony_env_percents "${DEV_DATABASE_URL}")
fi

PROD_DATABASE_URL=""
if [[ -n "${DB_HOST_PROD:-}" ]]; then
  ENCODED_PROD_USER=$(urlencode "${DB_USER_PROD}")
  ENCODED_PROD_PASSWORD=$(urlencode "${DB_PASSWORD_PROD}")
  PROD_DATABASE_URL="mysql://${ENCODED_PROD_USER}:${ENCODED_PROD_PASSWORD}@${DB_HOST_PROD}:${DB_PORT_PROD}/${DB_NAME_PROD}"
  PROD_DATABASE_URL=$(escape_symfony_env_percents "${PROD_DATABASE_URL}")
fi

# Escribir los archivos .env locales del entorno
cat > aDespliegue/dev/.env.example <<ENV
PORT_DEV=8080
DATABASE_URL=YOUR_DATABASE_URL
DB_NETWORK_DEV=${DB_NETWORK_DEV}
APP_SECRET=YOUR_APP_SECRET
JWT_PASSPHRASE=YOUR_JWT_PASSPHRASE
ENV

cat > aDespliegue/dev/.env <<ENV
PORT_DEV=${PORT_DEV}
DATABASE_URL=${DEV_DATABASE_URL}
DB_NETWORK_DEV=${DB_NETWORK_DEV}
APP_SECRET=${APP_SECRET}
JWT_PASSPHRASE=${DEV_JWT_PASSPHRASE}
ENV

cat > aDespliegue/prod/.env.example <<ENV
PORT_PROD=80
PROD_SERVER_IP=
DATABASE_URL=YOUR_DATABASE_URL
DB_NETWORK_PROD=${DB_NETWORK_PROD}
APP_SECRET=YOUR_APP_SECRET
JWT_PASSPHRASE=YOUR_JWT_PASSPHRASE
ENV

cat > aDespliegue/prod/.env <<ENV
PORT_PROD=${PORT_PROD}
PROD_SERVER_IP=${PROD_SERVER_IP}
DATABASE_URL=${PROD_DATABASE_URL}
DB_NETWORK_PROD=${DB_NETWORK_PROD}
APP_SECRET=${APP_SECRET}
JWT_PASSPHRASE=${DEV_JWT_PASSPHRASE}
ENV

# -----------------------------------------------------------------------------
# 12. Makefile en la raíz
# -----------------------------------------------------------------------------
step "Generando Makefile"

cat > Makefile <<MAKE
.PHONY: help serve stop sh cc logs logs-symfony ps migrate migration jwt-keys up-dev down-dev build-dev up-prod down-prod build-prod

PHP_SERVICE_dev = ${DEV_PHP_SERVICE}
PHP_SERVICE_prod = ${PROD_PHP_SERVICE}
APP_DIR_dev = /workspace/app
APP_DIR_prod = /workspace

help:
	@echo "Comandos disponibles:"
	@echo "  make help             - Muestra esta ayuda"
	@echo "  make up-{dev|prod}    - Levanta el ambiente de desarrollo/producción"
	@echo "  make down-{dev|prod}  - Detiene el ambiente de desarrollo/producción"
	@echo "  make build-{dev|prod} - Reconstruye el ambiente de desarrollo/producción"
	@echo "  make serve            - Inicia el servidor Symfony (solo dev)"
	@echo "  make stop             - Detiene el servidor Symfony (solo dev)"
	@echo "  make sh-{dev|prod}    - Accede al shell del contenedor PHP"
	@echo "  make cc-{dev|prod}    - Limpia el cache de Symfony"
	@echo "  make logs-{dev|prod}  - Muestra los logs de Docker"
	@echo "  make logs-symfony     - Muestra los logs del servidor Symfony (dev)"
	@echo "  make ps-{dev|prod}    - Muestra el estado de los contenedores"

up-dev:
	cd aDespliegue/dev && docker compose up -d

down-dev:
	cd aDespliegue/dev && docker compose down

build-dev:
	cd aDespliegue/dev && docker compose build --no-cache

up-prod:
	cd aDespliegue/prod && docker compose up -d

down-prod:
	cd aDespliegue/prod && docker compose down

build-prod:
	cd aDespliegue/prod && docker compose build --no-cache

serve:
	cd aDespliegue/dev && docker compose exec -w /workspace/app ${DEV_PHP_SERVICE} symfony server:start --no-tls --port=8000 --daemon

stop:
	cd aDespliegue/dev && docker compose exec -w /workspace/app ${DEV_PHP_SERVICE} symfony server:stop 2>/dev/null || true

sh-dev:
	cd aDespliegue/dev && docker compose exec -w /workspace/app ${DEV_PHP_SERVICE} bash

sh-prod:
	cd aDespliegue/prod && docker compose exec -w /workspace ${PROD_PHP_SERVICE} bash

cc-dev:
	cd aDespliegue/dev && docker compose exec -w /workspace/app ${DEV_PHP_SERVICE} php bin/console cache:clear

cc-prod:
	cd aDespliegue/prod && docker compose exec -w /workspace ${PROD_PHP_SERVICE} php bin/console cache:clear

logs-dev:
	cd aDespliegue/dev && docker compose logs -f

logs-prod:
	cd aDespliegue/prod && docker compose logs -f

logs-symfony:
	cd aDespliegue/dev && docker compose exec -w /workspace/app ${DEV_PHP_SERVICE} symfony server:log

ps-dev:
	cd aDespliegue/dev && docker compose ps

ps-prod:
	cd aDespliegue/prod && docker compose ps

MAKE

[[ -n "${DB_HOST:-}" ]] && cat >> Makefile <<MAKE
migrate-dev:
	cd aDespliegue/dev && docker compose exec -w /workspace/app ${DEV_PHP_SERVICE} php bin/console doctrine:migrations:migrate --no-interaction

migrate-prod:
	cd aDespliegue/prod && docker compose exec -w /workspace ${PROD_PHP_SERVICE} php bin/console doctrine:migrations:migrate --no-interaction

migration-dev:
	cd aDespliegue/dev && docker compose exec -w /workspace/app ${DEV_PHP_SERVICE} php bin/console make:migration

migration-prod:
	cd aDespliegue/prod && docker compose exec -w /workspace ${PROD_PHP_SERVICE} php bin/console make:migration

MAKE

$USE_JWT && cat >> Makefile <<MAKE
jwt-keys-dev:
	cd aDespliegue/dev && docker compose exec -w /workspace/app ${DEV_PHP_SERVICE} php bin/console lexik:jwt:generate-keypair

jwt-keys-prod:
	cd aDespliegue/prod && docker compose exec -w /workspace ${PROD_PHP_SERVICE} php bin/console lexik:jwt:generate-keypair

MAKE

if ! $USE_SYMFONY; then
  cat > Makefile <<MAKE
.PHONY: help sh logs ps up-dev down-dev build-dev up-prod down-prod build-prod

PHP_SERVICE_dev = ${DEV_PHP_SERVICE}
PHP_SERVICE_prod = ${PROD_PHP_SERVICE}
APP_DIR_dev = /workspace/app
APP_DIR_prod = /workspace

help:
	@echo "Comandos disponibles:"
	@echo "  make help             - Muestra esta ayuda"
	@echo "  make up-{dev|prod}    - Levanta el ambiente de desarrollo/producción"
	@echo "  make down-{dev|prod}  - Detiene el ambiente de desarrollo/producción"
	@echo "  make build-{dev|prod} - Reconstruye el ambiente de desarrollo/producción"
	@echo "  make sh-{dev|prod}    - Accede al shell del contenedor PHP"
	@echo "  make logs-{dev|prod}  - Muestra los logs de Docker"
	@echo "  make ps-{dev|prod}    - Muestra el estado de los contenedores"

up-dev:
	cd aDespliegue/dev && docker compose up -d

down-dev:
	cd aDespliegue/dev && docker compose down

build-dev:
	cd aDespliegue/dev && docker compose build --no-cache

up-prod:
	cd aDespliegue/prod && docker compose up -d

down-prod:
	cd aDespliegue/prod && docker compose down

build-prod:
	cd aDespliegue/prod && docker compose build --no-cache

sh-dev:
	cd aDespliegue/dev && docker compose exec -w /workspace/app ${DEV_PHP_SERVICE} bash

sh-prod:
	cd aDespliegue/prod && docker compose exec -w /workspace ${PROD_PHP_SERVICE} bash

logs-dev:
	cd aDespliegue/dev && docker compose logs -f

logs-prod:
	cd aDespliegue/prod && docker compose logs -f

ps-dev:
	cd aDespliegue/dev && docker compose ps

ps-prod:
	cd aDespliegue/prod && docker compose ps

MAKE
fi

# -----------------------------------------------------------------------------
# 13. .gitignore
# -----------------------------------------------------------------------------
cat > .gitignore <<GIT
app/vendor/
app/var/
app/public/bundles/
app/config/jwt/private.pem
app/config/jwt/public.pem
.idea/
.vscode/
GIT

# -----------------------------------------------------------------------------
# 14. Levantar contenedores
# -----------------------------------------------------------------------------
step "Levantando contenedores Docker"
docker compose -f aDespliegue/dev/docker-compose.yml build
docker compose -f aDespliegue/dev/docker-compose.yml up -d

# Esperar a que PHP esté listo
echo "Esperando que los contenedores estén listos..."
sleep 3

# -----------------------------------------------------------------------------
# 15. Crear aplicación
# -----------------------------------------------------------------------------
if $USE_SYMFONY; then

# -----------------------------------------------------------------------------
# 15. symfony new app
# -----------------------------------------------------------------------------
step "Creando proyecto Symfony en app/"
SYMFONY_INSTALL="${SYMFONY_INSTALL:-minimal}"
case "${SYMFONY_INSTALL}" in
  webapp) SYMFONY_FLAGS="--webapp --debug"; SYMFONY_PACKAGE="symfony/website-skeleton" ;;
  minimal) SYMFONY_FLAGS=""; SYMFONY_PACKAGE="symfony/skeleton" ;;
  *) echo "Error: SYMFONY_INSTALL debe ser minimal o webapp."; exit 1 ;;
esac

docker compose -f aDespliegue/dev/docker-compose.yml exec -w /workspace/app ${DEV_PHP_SERVICE} symfony new /workspace/app ${SYMFONY_FLAGS} --version=lts --no-git 2>/dev/null || docker compose -f aDespliegue/dev/docker-compose.yml exec -w /workspace/app ${DEV_PHP_SERVICE} composer create-project --no-interaction ${SYMFONY_PACKAGE} /workspace/app

# Ajustar permisos de los archivos creados para el usuario actual
docker compose -f aDespliegue/dev/docker-compose.yml exec -w /workspace ${DEV_PHP_SERVICE} chown -R $(id -u):$(id -g) /workspace

# Desactivar recetas de Docker de Symfony Flex para evitar prompts interactivos
docker compose -f aDespliegue/dev/docker-compose.yml exec -w /workspace/app ${DEV_PHP_SERVICE} composer config extra.symfony.docker false

# -----------------------------------------------------------------------------
# 16. Instalar paquetes según módulos
# -----------------------------------------------------------------------------
step "Instalando paquetes seleccionados"

sym_exec() {
  docker compose -f aDespliegue/dev/docker-compose.yml exec -w /workspace/app ${DEV_PHP_SERVICE} \
    bash -c "$1"
}

[[ -n "${DB_HOST:-}" ]]           && sym_exec "composer require --no-interaction symfony/orm-pack doctrine/doctrine-migrations-bundle"
($USE_AUTH || $USE_ADMIN) && sym_exec "composer require --no-interaction symfony/twig-bundle"
$USE_AUTH         && sym_exec "composer require --no-interaction symfony/security-bundle symfony/validator"
$USE_JWT          && sym_exec "composer require --no-interaction lexik/jwt-authentication-bundle"
$USE_ADMIN        && sym_exec "composer require --no-interaction easycorp/easyadmin-bundle vich/uploader-bundle"

sym_exec "composer require --no-interaction --dev symfony/maker-bundle symfony/debug-bundle"
# Composer puede crear carpetas nuevas como root; normalizar antes de copiar stubs desde el host.
docker compose -f aDespliegue/dev/docker-compose.yml exec -w /workspace ${DEV_PHP_SERVICE} chown -R $(id -u):$(id -g) /workspace
mkdir -p app/src app/templates app/config/packages

# -----------------------------------------------------------------------------
# 17. Copiar stubs de código base
# -----------------------------------------------------------------------------
if [[ -d "$STUBS_DIR" ]]; then
  step "Copiando stubs de código base"

  if [[ -d "$STUBS_DIR/common" ]]; then
    cp -r "$STUBS_DIR/common/." app/src/
    echo "  ✓ stubs/common → app/src/"
  fi

  if $USE_ADMIN && [[ -d "$STUBS_DIR/admin" ]]; then
    [[ -d "$STUBS_DIR/admin/Controller" ]] && cp -r "$STUBS_DIR/admin/Controller" app/src/
    [[ -d "$STUBS_DIR/admin/Filter" ]] && cp -r "$STUBS_DIR/admin/Filter" app/src/
    [[ -d "$STUBS_DIR/admin/templates" ]] && cp -r "$STUBS_DIR/admin/templates/." app/templates/
    echo "  ✓ stubs/admin → app/src/ + app/templates/"
  fi

  if $USE_AUTH && [[ -d "$STUBS_DIR/auth" ]]; then
    # src/ — Entity, Repository, Controller, Security
    for dir in Entity Repository Controller Security; do
      [[ -d "$STUBS_DIR/auth/$dir" ]] && cp -r "$STUBS_DIR/auth/$dir" app/src/
    done
    # templates/
    [[ -d "$STUBS_DIR/auth/templates" ]] && cp -r "$STUBS_DIR/auth/templates/." app/templates/
    # config/packages/
    [[ -d "$STUBS_DIR/auth/config" ]] && cp -r "$STUBS_DIR/auth/config/." app/config/
    echo "  ✓ stubs/auth → app/src/ + app/templates/ + app/config/"
  fi

  if $USE_JWT && [[ -d "$STUBS_DIR/jwt" ]]; then
    cp -r "$STUBS_DIR/jwt/." app/src/
    echo "  ✓ stubs/jwt → app/src/"
  fi

  # Combinación USE_AUTH + USE_ADMIN → UserCrudController + item de menú
  if $USE_AUTH && $USE_ADMIN && [[ -d "$STUBS_DIR/auth_admin" ]]; then
    cp -r "$STUBS_DIR/auth_admin/." app/src/
    echo "  ✓ stubs/auth_admin → app/src/ (UserCrudController)"

    # Inyectar item de menú en DashboardController si existe el marcador
    DASHBOARD="app/src/Controller/Admin/DashboardController.php"
    if [[ -f "$DASHBOARD" ]]; then
      sed -i 's|.*// @@USER_MENU_ITEM@@.*|        yield MenuItem::section('\''Seguridad'\'');\n        yield MenuItem::linkTo(\\App\\Controller\\Admin\\UserCrudController::class, '\''Usuarios'\'', '\''fa fa-users'\'');\n\n        yield MenuItem::section('\''Acciones'\'');\n        yield MenuItem::linkToLogout('\''Salir'\'', '\''fa fa-sign-out-alt text-danger'\'');|' "$DASHBOARD"
      echo "  ✓ Items 'Usuarios' y 'Salir' agregados al DashboardController"
    fi
  fi


else
  echo "  (No se encontró el directorio stubs/, se omite este paso)"
fi

if [[ -n "${DB_HOST_DEV:-}" ]]; then
  # Symfony/Doctrine puede dejar una DATABASE_URL de ejemplo activa; deshabilitarla antes de escribir la real.
  sed -i -E 's/^DATABASE_URL=/# DATABASE_URL=/' app/.env
  cat >> app/.env <<ENV

DATABASE_URL=${DEV_DATABASE_URL}
ENV
fi
if [[ -n "${DB_HOST_DEV:-}" ]]; then
  step "Verificando conexión a la base de datos"
  if ! docker compose -f aDespliegue/dev/docker-compose.yml exec -w /workspace/app ${DEV_PHP_SERVICE} php -r "
    require '/workspace/app/vendor/autoload.php';
    (new Symfony\Component\Dotenv\Dotenv())->bootEnv('/workspace/app/.env');
    \$databaseUrl = \$_ENV['DATABASE_URL'] ?? getenv('DATABASE_URL') ?: '';
    \$databaseParts = [];
    if (\$databaseUrl !== '') {
      \$databaseParts = parse_url(str_replace('%%', '%', \$databaseUrl)) ?: [];
    }
    \$host = \$_ENV['DB_HOST'] ?? (\$databaseParts['host'] ?? 'host.docker.internal');
    \$port = \$_ENV['DB_PORT'] ?? (\$databaseParts['port'] ?? 3306);
    \$user = \$_ENV['DB_USER'] ?? (isset(\$databaseParts['user']) ? rawurldecode(\$databaseParts['user']) : 'root');
    \$pass = \$_ENV['DB_PASSWORD'] ?? (isset(\$databaseParts['pass']) ? rawurldecode(\$databaseParts['pass']) : '');
    \$dbName = \$_ENV['DB_NAME'] ?? (isset(\$databaseParts['path']) ? ltrim(\$databaseParts['path'], '/') : '');

    // 1. Verificar conexión al servidor (sin dbname)
    \$maxAttempts = 5;
    \$serverConnected = false;
    for (\$i = 1; \$i <= \$maxAttempts; \$i++) {
      try {
        \$pdo = new PDO('mysql:host=' . \$host . ';port=' . \$port, \$user, \$pass, [
          PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
          PDO::ATTR_TIMEOUT => 2
        ]);
        \$serverConnected = true;
        break;
      } catch (Exception \$e) {
        if (\$i === \$maxAttempts) {
          echo '  Error: No se pudo conectar al servidor de base de datos: ' . \$e->getMessage() . PHP_EOL;
          exit(1);
        }
        echo '  [' . \$i . '/' . \$maxAttempts . '] Esperando al servidor de base de datos (' . \$host . ':' . \$port . ')...' . PHP_EOL;
        sleep(2);
      }
    }

    if (\$serverConnected) {
      // 2. Verificar si la base de datos existe e intentar acceder a ella
      try {
        \$pdoDb = new PDO('mysql:host=' . \$host . ';port=' . \$port . ';dbname=' . \$dbName, \$user, \$pass, [
          PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
          PDO::ATTR_TIMEOUT => 2
        ]);
        echo '  Conexión exitosa a la base de datos \'' . \$dbName . '\'' . PHP_EOL;
        exit(0);
      } catch (PDOException \$e) {
        if (\$e->getCode() == 1049) {
          echo '❌ Error crítico: La base de datos \'' . \$dbName . '\' no existe en el servidor.' . PHP_EOL;
          echo '   Por favor, crea la base de datos en tu MySQL y otorga los privilegios al usuario \'' . \$user . '\'.' . PHP_EOL;
          echo '   Puedes crearla con el siguiente comando SQL (ejecutado como root):' . PHP_EOL;
          echo '     CREATE DATABASE \`' . \$dbName . '\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;' . PHP_EOL;
          echo '     GRANT ALL PRIVILEGES ON \`' . \$dbName . '\`.* TO \'' . \$user . '\'@\'%\';' . PHP_EOL;
          echo '     FLUSH PRIVILEGES;' . PHP_EOL;
          exit(1);
        } else {
          echo '❌ Error crítico de conexión a la base de datos \'' . \$dbName . '\': ' . \$e->getMessage() . PHP_EOL;
          exit(1);
        }
      }
    }
  "; then
     exit 1
  fi
fi

if $USE_AUTH && [[ -n "${DB_HOST:-}" ]]; then
  step "Creando usuario admin por defecto"

  # Verificar si la base de datos ya tiene tablas (no está vacía)
  DB_HAS_TABLES=$(docker compose -f aDespliegue/dev/docker-compose.yml exec -w /workspace/app ${DEV_PHP_SERVICE} php -r "
    require '/workspace/app/vendor/autoload.php';
    (new Symfony\Component\Dotenv\Dotenv())->bootEnv('/workspace/app/.env');
    \$databaseUrl = \$_ENV['DATABASE_URL'] ?? getenv('DATABASE_URL') ?: '';
    \$databaseParts = [];
    if (\$databaseUrl !== '') {
      \$databaseParts = parse_url(str_replace('%%', '%', \$databaseUrl)) ?: [];
    }
    \$host = \$_ENV['DB_HOST'] ?? (\$databaseParts['host'] ?? 'host.docker.internal');
    \$port = \$_ENV['DB_PORT'] ?? (\$databaseParts['port'] ?? 3306);
    \$user = \$_ENV['DB_USER'] ?? (isset(\$databaseParts['user']) ? rawurldecode(\$databaseParts['user']) : 'root');
    \$pass = \$_ENV['DB_PASSWORD'] ?? (isset(\$databaseParts['pass']) ? rawurldecode(\$databaseParts['pass']) : '');
    \$dbName = \$_ENV['DB_NAME'] ?? (isset(\$databaseParts['path']) ? ltrim(\$databaseParts['path'], '/') : '');
    try {
      \$pdo = new PDO('mysql:host=' . \$host . ';port=' . \$port . ';dbname=' . \$dbName, \$user, \$pass);
      \$count = (int) \$pdo->query('SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE()')->fetchColumn();
      echo \$count > 0 ? 'true' : 'false';
    } catch (Exception \$e) {
      echo 'false';
    }
  " 2>/dev/null | tr -d '[:space:]')

  # Verificar si la base de datos ya tiene la tabla de usuarios
  DB_HAS_USER_TABLE=$(docker compose -f aDespliegue/dev/docker-compose.yml exec -w /workspace/app ${DEV_PHP_SERVICE} php -r "
    require '/workspace/app/vendor/autoload.php';
    (new Symfony\Component\Dotenv\Dotenv())->bootEnv('/workspace/app/.env');
    \$databaseUrl = \$_ENV['DATABASE_URL'] ?? getenv('DATABASE_URL') ?: '';
    \$databaseParts = [];
    if (\$databaseUrl !== '') {
      \$databaseParts = parse_url(str_replace('%%', '%', \$databaseUrl)) ?: [];
    }
    \$host = \$_ENV['DB_HOST'] ?? (\$databaseParts['host'] ?? 'host.docker.internal');
    \$port = \$_ENV['DB_PORT'] ?? (\$databaseParts['port'] ?? 3306);
    \$user = \$_ENV['DB_USER'] ?? (isset(\$databaseParts['user']) ? rawurldecode(\$databaseParts['user']) : 'root');
    \$pass = \$_ENV['DB_PASSWORD'] ?? (isset(\$databaseParts['pass']) ? rawurldecode(\$databaseParts['pass']) : '');
    \$dbName = \$_ENV['DB_NAME'] ?? (isset(\$databaseParts['path']) ? ltrim(\$databaseParts['path'], '/') : '');
    try {
      \$pdo = new PDO('mysql:host=' . \$host . ';port=' . \$port . ';dbname=' . \$dbName, \$user, \$pass);
      \$stmt = \$pdo->query(\"SHOW TABLES LIKE 'user'\");
      echo \$stmt && \$stmt->rowCount() > 0 ? 'true' : 'false';
    } catch (Exception \$e) {
      echo 'false';
    }
  " 2>/dev/null | tr -d '[:space:]')

  SKIP_ADMIN_CREATION=false
  RAN_INITIAL_MIGRATION=false
  set +e
  if [[ "$DB_HAS_TABLES" == "true" ]]; then
    echo "  ℹ️  La base de datos '${DEV_DB_NAME}' ya contiene tablas. Se omiten la migración y el usuario admin inicial por seguridad."
    SKIP_ADMIN_CREATION=true
    if [[ "$DB_HAS_USER_TABLE" != "true" ]]; then
      echo "  ⚠️  Advertencia: La tabla 'user' no existe. Se omitirá la creación del administrador inicial."
      SKIP_ADMIN_CREATION=true
    fi
  else
    echo "  La base de datos está vacía. Ejecutando migraciones..."
    RAN_INITIAL_MIGRATION=true
    sym_exec "php bin/console make:migration --no-interaction"
    if ! sym_exec "php bin/console doctrine:migrations:migrate --no-interaction"; then
      echo "  ⚠ Migraciones fallidas o no registradas. Sincronizando esquema de base de datos directamente..."
      sym_exec "php bin/console doctrine:schema:update --force"
    fi
  fi
  set -e

  if [[ "$SKIP_ADMIN_CREATION" == "true" ]]; then
    echo "  ℹ️  Creación del usuario administrador omitida."
  elif ! $ADMIN_CREDENTIALS_CONFIGURED; then
    echo "  ℹ️  ADMIN_LOGIN/ADMIN_PASSWORD no están definidos en el .conf. Se omite el usuario admin inicial."
  else
    if ! docker compose -f aDespliegue/dev/docker-compose.yml exec -w /workspace/app \
      -e INIT_ADMIN_LOGIN="${DEV_ADMIN_LOGIN}" \
      -e INIT_ADMIN_PASSWORD="${DEV_ADMIN_PASSWORD}" \
      ${DEV_PHP_SERVICE} php -r "
      require '/workspace/app/vendor/autoload.php';
      (new Symfony\Component\Dotenv\Dotenv())->bootEnv('/workspace/app/.env');
      \$kernel = new App\Kernel('dev', true);
      \$kernel->boot();
      \$adminLogin = getenv('INIT_ADMIN_LOGIN') ?: '';
      \$adminPassword = getenv('INIT_ADMIN_PASSWORD') ?: '';
      if (\$adminLogin === '' || \$adminPassword === '') {
        echo 'Credenciales admin iniciales no definidas.' . PHP_EOL;
        exit(1);
      }
      \$container = \$kernel->getContainer();
      \$em = \$container->get('doctrine')->getManager();
      \$repo = \$em->getRepository(App\Entity\User::class);
      if (\$repo->findOneBy(['login' => \$adminLogin])) {
        echo 'Usuario admin ya existe.' . PHP_EOL; exit(0);
      }
      \$user = new App\\Entity\\User();
      \$user->setLogin(\$adminLogin);
      \$user->setPassword(password_hash(\$adminPassword, PASSWORD_BCRYPT));
      \$user->setRoles(['ROLE_ADMIN']);
      \$user->setActivo(true);
      \$em->persist(\$user);
      \$em->flush();
      echo 'Usuario admin creado.' . PHP_EOL;
    "; then
      echo "❌ Error crítico: No se pudo crear el usuario admin inicial."
      echo "   Verifica permisos de base de datos para ${DEV_DB_USER} sobre ${DEV_DB_NAME}."
      exit 1
    fi
    echo "  ✓ Usuario admin creado con credenciales del .conf"
    ADMIN_USER_CREATED=true
  fi
fi

$USE_JWT && {
  step "Generando claves JWT"
  sym_exec "mkdir -p config/jwt && php bin/console lexik:jwt:generate-keypair --skip-if-exists"
}

else
  step "Creando aplicación PHP básica en app/"
  mkdir -p app/public
  cat > app/public/index.php <<PHP
<?php

http_response_code(200);

echo "<h1>PHP app lista</h1>";
echo "<p>Proyecto: ${PROJECT_NAME}</p>";
PHP

  cat > app/composer.json <<JSON
{
  "name": "app/${PROJECT_SLUG}",
  "type": "project",
  "require": {}
}
JSON
fi

step "Generando leeme.txt"
{
  echo "desarrollo:"
  echo "-----------"
  if $USE_SYMFONY; then
    echo "cd app"
    echo "symfony server:start --port=${PORT_DEV} --no-tls --allow-http --allow-all-ip"
  else
    echo "cd app/public"
    echo "php -S 0.0.0.0:${PORT_DEV}"
  fi
  echo "http://localhost:${PORT_DEV}"
  echo ""
  echo "produccion:"
  echo "-----------"
  if [[ -n "${PROD_SERVER_IP}" ]]; then
    PROD_SERVER_IP=$(echo "${PROD_SERVER_IP}" | xargs)
    echo "http://${PROD_SERVER_IP}:${PORT_PROD}"
  elif [[ -n "${PROD_URLS}" ]]; then
    IFS=',' read -ra PROD_URL_LIST <<< "${PROD_URLS}"
    for url in "${PROD_URL_LIST[@]}"; do
      url=$(echo "$url" | xargs)
      [[ -n "$url" ]] && echo "$url"
    done
  else
    echo "http://localhost:${PORT_PROD}"
  fi
  if [[ "${ADMIN_USER_CREATED}" == "true" ]]; then
    echo ""
    echo "admin:"
    echo "------"
    echo "Usuario: ${DEV_ADMIN_LOGIN}"
    echo "Password: ${DEV_ADMIN_PASSWORD}"
  fi
} > leeme.txt

# Asegurar que todos los archivos nuevos creados sean del usuario host
docker compose -f aDespliegue/dev/docker-compose.yml exec -w /workspace ${DEV_PHP_SERVICE} chown -R $(id -u):$(id -g) /workspace

# Reiniciar el contenedor para que el servidor interno detecte los nuevos archivos
docker compose -f aDespliegue/dev/docker-compose.yml restart ${DEV_PHP_SERVICE}

# -----------------------------------------------------------------------------
# 18. Listo
# -----------------------------------------------------------------------------
echo ""
echo "╔══════════════════════════════════════════╗"
echo "║   ✅  ${PROJECT_NAME} listo!              "
echo "╚══════════════════════════════════════════╝"
echo ""
echo "  Estructura creada:"
echo "  ${PROJECT_SLUG}/"
echo "  ├── .devcontainer/devcontainer.json"
echo "  ├── aDespliegue/dev/   (docker-compose + Dockerfile)"
echo "  ├── aDespliegue/prod/  (docker-compose + Dockerfile multistage)"
if $USE_SYMFONY; then
  echo "  ├── app/               (Symfony ${PHP_VERSION})"
else
  echo "  ├── app/               (PHP ${PHP_VERSION})"
fi
echo "  ├── Makefile"
echo "  ├── leeme.txt"
echo ""
echo "  🌐  App:     http://localhost:${PORT_DEV}"
if $USE_AUTH && $ADMIN_CREDENTIALS_CONFIGURED; then
  echo "  🔑  Admin inicial: ver leeme.txt si se creó una base nueva"
fi

echo ""
echo "  Comandos:"
if $USE_SYMFONY; then
  echo "    make up-{dev|prod}    → levanta Docker"
  echo "    make down-{dev|prod}  → detiene Docker"
  echo "    make serve           → solo arranca el servidor Symfony (dev)"
  echo "    make sh-{dev|prod}   → bash en el contenedor PHP"
  echo "    make cc-{dev|prod}   → cache:clear"
  [[ -n "${DB_HOST:-}" ]] && echo "    make migrate-{dev|prod} → doctrine:migrations:migrate"
  $USE_JWT     && echo "    make jwt-keys-{dev|prod} → regenerar claves JWT"
  echo "    make logs-symfony    → ver log del servidor Symfony (dev)"
else
  echo "    make up-{dev|prod}    → levanta Docker"
  echo "    make down-{dev|prod}  → detiene Docker"
  echo "    make sh-{dev|prod}   → bash en el contenedor PHP"
  echo "    make logs-{dev|prod} → ver logs de Docker"
fi
echo ""
echo "  En VSCode: Dev Containers: Reopen in Container"
echo ""
