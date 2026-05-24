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
ask_yn() {
  local label=$1
  local default=${2:-n}
  local hint=$([ "$default" = "s" ] && echo "[S/n]" || echo "[s/N]")
  read -p "  $label $hint: " ans
  ans=${ans:-$default}
  [[ "$ans" =~ ^[sS]$ ]]
}

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
    value=$(echo "$value" | tr -d '"' | tr -d "'" | sed 's/[[:space:]]*#.*//' | xargs)
    declare "$key=$value"
  done < "$CONFIG_FILE"

  # Derivar PROJECT_NAME del nombre del archivo de configuración
  CONFIG_BASENAME=$(basename "$CONFIG_FILE" .conf)
  PROJECT_NAME=${CONFIG_BASENAME#project_}
  if [[ -z "${PROJECT_NAME:-}" ]]; then
    echo "Error: PROJECT_NAME es obligatorio en el archivo de config."; exit 1
  fi

  # Aplicar defaults para campos opcionales
  PHP_VERSION="${PHP_VERSION:-8.3}"
  HTTP_PORT="${HTTP_PORT:-8080}"
  DB_NETWORK="${DB_NETWORK:-}"

  # Normalizar booleanos
  bool_default_true "${USE_SYMFONY:-true}" && USE_SYMFONY=true || USE_SYMFONY=false
  bool "${USE_DB:-false}"           && USE_DB=true           || USE_DB=false
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
  HTTP_PORT=$(ask_input "Puerto HTTP local (dev)" "8080")
  DB_NETWORK=""

  echo ""
  echo "Módulos a incluir:"

  USE_SYMFONY=false;      ask_yn "Framework Symfony" "s"                        && USE_SYMFONY=true
  USE_DB=false
  USE_AUTH=false
  USE_JWT=false
  USE_ADMIN=false
  if $USE_SYMFONY; then
    ask_yn "Base de datos (Doctrine + MySQL)" "s"                               && USE_DB=true
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
  USE_DB=false
  USE_AUTH=false
  USE_JWT=false
  USE_ADMIN=false
fi

# EasyAdmin necesita Doctrine (aplica en ambos modos)
if $USE_ADMIN && ! $USE_DB; then
  echo ""
  echo "⚠ EasyAdmin requiere Doctrine. Se habilitará automáticamente."
  USE_DB=true
fi

PROJECT_SLUG=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g')
CONFIRM=s
# -----------------------------------------------------------------------------
# 2. Resumen (siempre se muestra, con confirmación solo en modo interactivo)
  [[ "$CONFIRM" =~ ^[sS]$ ]] || { echo "Cancelado."; exit 0; }

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
  DEV_APT="git curl unzip libicu-dev libonig-dev libxml2-dev libzip-dev"
else
  DEV_EXTENSIONS=""
  DEV_APT="curl"
fi
$USE_DB        && DEV_APT+=" default-libmysqlclient-dev"         && DEV_EXTENSIONS+=" pdo pdo_mysql"

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

WORKDIR /workspace

EXPOSE 9000
DOCKERFILE
else
  cat > aDespliegue/dev/Dockerfile <<DOCKERFILE
FROM php:${PHP_VERSION}-fpm

WORKDIR /workspace

EXPOSE 9000
DOCKERFILE
fi

# -----------------------------------------------------------------------------
# 6. aDespliegue/dev/docker-compose.yml
# -----------------------------------------------------------------------------
step "Generando docker-compose.yml dev"

DEV_DB_NETWORK=""
DEV_EXTERNAL_NETWORK=""
if $USE_DB && [[ -n "$DB_NETWORK" && "$DB_NETWORK" != "${PROJECT_SLUG}_net" ]]; then
  DEV_DB_NETWORK="      - ${DB_NETWORK}"
  DEV_EXTERNAL_NETWORK=$(printf '  %s:\n    external: true' "$DB_NETWORK")
fi

cat > aDespliegue/dev/docker-compose.yml <<YAML
services:
  ${PROJECT_SLUG}_php:
    build:
      context: ../..
      dockerfile: aDespliegue/dev/Dockerfile
    container_name: ${PROJECT_SLUG}_php
    ports:
      - "${HTTP_PORT}:8000"
    volumes:
      - ../../app:/workspace
    environment:
      APP_ENV: dev
      APP_DEBUG: "1"
    networks:
      - ${PROJECT_SLUG}_net
${DEV_DB_NETWORK}
YAML

$USE_DB && cat >> aDespliegue/dev/docker-compose.yml <<YAML
    extra_hosts:
      - "host.docker.internal:host-gateway"
YAML

cat >> aDespliegue/dev/docker-compose.yml <<YAML

networks:
  ${PROJECT_SLUG}_net:
    name: ${PROJECT_SLUG}_net
${DEV_EXTERNAL_NETWORK}
YAML

# -----------------------------------------------------------------------------
# 8. aDespliegue/prod/Dockerfile
# -----------------------------------------------------------------------------
step "Generando Dockerfile prod"

if $USE_SYMFONY; then
  PROD_EXTENSIONS="intl opcache zip"
  PROD_APT="git curl unzip libicu-dev libonig-dev libxml2-dev libzip-dev"
  $USE_DB && PROD_APT+=" default-libmysqlclient-dev" && PROD_EXTENSIONS+=" pdo pdo_mysql"

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
if $USE_DB && [[ -n "$DB_NETWORK" && "$DB_NETWORK" != "${PROJECT_SLUG}_prod_net" ]]; then
  PROD_DB_NETWORK="      - ${DB_NETWORK}"
  PROD_EXTERNAL_NETWORK=$(printf '  %s:\n    external: true' "$DB_NETWORK")
fi

cat > aDespliegue/prod/docker-compose.yml <<YAML
services:
  ${PROJECT_SLUG}_php_prod:
    build:
      context: ../..
      dockerfile: aDespliegue/prod/Dockerfile
    container_name: ${PROJECT_SLUG}_php_prod
    environment:
      APP_ENV: prod
      APP_DEBUG: "0"
    networks:
      - ${PROJECT_SLUG}_prod_net
${PROD_DB_NETWORK}
YAML

$USE_DB && cat >> aDespliegue/prod/docker-compose.yml <<YAML
    extra_hosts:
      - "host.docker.internal:host-gateway"
YAML

cat >> aDespliegue/prod/docker-compose.yml <<YAML

  ${PROJECT_SLUG}_nginx_prod:
    image: nginx:alpine
    container_name: ${PROJECT_SLUG}_nginx_prod
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf
    depends_on:
      - ${PROJECT_SLUG}_php_prod
    networks:
      - ${PROJECT_SLUG}_prod_net

networks:
  ${PROJECT_SLUG}_prod_net:
    name: ${PROJECT_SLUG}_prod_net
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
        fastcgi_pass ${PROJECT_SLUG}_php_prod:9000;
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
  "service": "${PROJECT_SLUG}_php",
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

  
  },

  "postStartCommand": "cd /workspace && composer install && symfony server:start --no-tls --port=8000 --daemon"
}
JSON

if ! $USE_SYMFONY; then
  cat > .devcontainer/devcontainer.json <<JSON
{
  "name": "${PROJECT_NAME}",
  "dockerComposeFile": ["../aDespliegue/dev/docker-compose.yml"],
  "service": "${PROJECT_SLUG}_php",
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
# 11. .env base en la raíz
# -----------------------------------------------------------------------------
step "Generando .env"

APP_SECRET=$(openssl rand -hex 16)
DEV_DB_HOST="${DB_HOST:-host.docker.internal}"
DEV_DB_PORT="${DB_PORT:-3306}"
DEV_DB_USER="app"
DEV_DB_PASSWORD="secret"
DEV_ADMIN_LOGIN="${ADMIN_LOGIN:-admin}"
DEV_ADMIN_PASSWORD="${ADMIN_PASSWORD:-change_me_admin_password}"
DEV_JWT_PASSPHRASE="changeme"

if $USE_SYMFONY; then
  # ── Leer defaults globales desde ~/.symfony-defaults ──────────────────────────
  DEFAULTS_FILE="$HOME/.symfony-defaults"

  if [[ ! -f "$DEFAULTS_FILE" ]]; then
    echo "⚠ No se encontró ~/.symfony-defaults. Creando uno con valores de ejemplo..."
    cat > "$DEFAULTS_FILE" <<DEFAULTS
# Credenciales por defecto para proyectos Symfony en dev
# Este archivo nunca debe commitearse al repositorio.
DB_USER=app
DB_PASSWORD=secret
DB_HOST=host.docker.internal
DB_PORT=3306
ADMIN_LOGIN=admin
ADMIN_PASSWORD=change_me_admin_password
JWT_PASSPHRASE=dev_jwt_passphrase
DEFAULTS
    echo "  Editá ~/.symfony-defaults con tus credenciales reales antes de continuar."
    echo "  Luego volvé a correr el script."
    exit 0
  fi

  # Cargar defaults (ignorar comentarios y líneas vacías)
  while IFS="=" read -r key value; do
    [[ "$key" =~ ^#.*$ || -z "$key" ]] && continue
    key=$(echo "$key" | tr -d " ")
    value=$(echo "$value" | tr -d "\"" | tr -d "\047" | xargs)
    declare "DEFAULT_${key}=$value"
  done < "$DEFAULTS_FILE"

  DEV_DB_USER="${DEFAULT_DB_USER:-app}"
  DEV_DB_PASSWORD="${DEFAULT_DB_PASSWORD:-secret}"
  DEV_DB_HOST="${DB_HOST:-${DEFAULT_DB_HOST:-host.docker.internal}}"
  DEV_DB_PORT="${DB_PORT:-${DEFAULT_DB_PORT:-3306}}"
  DEV_ADMIN_LOGIN="${ADMIN_LOGIN:-${DEFAULT_ADMIN_LOGIN:-admin}}"
  DEV_ADMIN_PASSWORD="${ADMIN_PASSWORD:-${DEFAULT_ADMIN_PASSWORD:-change_me_admin_password}}"
  DEV_JWT_PASSPHRASE="${DEFAULT_JWT_PASSPHRASE:-changeme}"
fi

# ── .env.example (se commitea, sin valores reales) ───────────────────────────
cat > .env.example <<ENV
APP_ENV=dev
APP_SECRET=CHANGE_ME
ADMIN_LOGIN=YOUR_ADMIN_LOGIN
ADMIN_PASSWORD=YOUR_ADMIN_PASSWORD
ENV

$USE_DB && cat >> .env.example <<ENV
DB_NAME=${PROJECT_SLUG}
DB_USER=YOUR_DB_USER
DB_PASSWORD=YOUR_DB_PASSWORD
DB_HOST=YOUR_DB_HOST
DB_PORT=3306
DATABASE_URL=mysql://YOUR_DB_USER:YOUR_DB_PASSWORD@YOUR_DB_HOST:3306/${PROJECT_SLUG}


$USE_JWT && cat >> .env.example <<ENV
JWT_SECRET_KEY=%kernel.project_dir%/config/jwt/private.pem
JWT_PUBLIC_KEY=%kernel.project_dir%/config/jwt/public.pem
JWT_PASSPHRASE=YOUR_JWT_PASSPHRASE
ENV


# ── .env real (no se commitea, usa credenciales del ~/.symfony-defaults) ──────
cat > .env <<ENV
APP_ENV=dev
APP_SECRET=${APP_SECRET}
ADMIN_LOGIN=${DEV_ADMIN_LOGIN}
ADMIN_PASSWORD=${DEV_ADMIN_PASSWORD}
ENV

$USE_DB && cat >> .env <<ENV
DB_NAME=${PROJECT_SLUG}
DB_USER=${DEV_DB_USER}
DB_PASSWORD=${DEV_DB_PASSWORD}
DB_HOST=${DEV_DB_HOST}
DB_PORT=${DEV_DB_PORT}
DATABASE_URL=mysql://${DEV_DB_USER}:${DEV_DB_PASSWORD}@${DEV_DB_HOST}:${DEV_DB_PORT}/${PROJECT_SLUG}
ENV

$USE_JWT && cat >> .env <<ENV
JWT_SECRET_KEY=%kernel.project_dir%/config/jwt/private.pem
JWT_PUBLIC_KEY=%kernel.project_dir%/config/jwt/public.pem
JWT_PASSPHRASE=${DEV_JWT_PASSPHRASE}
ENV






# -----------------------------------------------------------------------------
# 12. Makefile en la raíz
# -----------------------------------------------------------------------------
step "Generando Makefile"

cat > Makefile <<MAKE
.PHONY: up down build serve start stop sh cc logs logs-symfony ps migrate migration jwt-keys prod-build prod-up admin

ENV_DIR = aDespliegue/dev
RUN_PHP = docker compose -f \$(ENV_DIR)/docker-compose.yml exec -w /workspace ${PROJECT_SLUG}_php

up:
	docker compose -f \$(ENV_DIR)/docker-compose.yml up -d

down:
	docker compose -f \$(ENV_DIR)/docker-compose.yml down
	\$(RUN_PHP) symfony server:stop 2>/dev/null || true

build:
	docker compose -f \$(ENV_DIR)/docker-compose.yml build --no-cache

serve:
	\$(RUN_PHP) symfony server:start --no-tls --port=8000 --daemon

stop:
	\$(RUN_PHP) symfony server:stop

start: up serve

sh:
	\$(RUN_PHP) bash

cc:
	\$(RUN_PHP) php bin/console cache:clear

logs:
	docker compose -f \$(ENV_DIR)/docker-compose.yml logs -f

logs-symfony:
	\$(RUN_PHP) symfony server:log

ps:
	docker compose -f \$(ENV_DIR)/docker-compose.yml ps

MAKE

$USE_DB && cat >> Makefile <<MAKE
migrate:
	\$(RUN_PHP) php bin/console doctrine:migrations:migrate --no-interaction

migration:
	\$(RUN_PHP) php bin/console make:migration

MAKE

$USE_JWT && cat >> Makefile <<MAKE
jwt-keys:
	\$(RUN_PHP) php bin/console lexik:jwt:generate-keypair

MAKE

cat >> Makefile <<MAKE
prod-build:
	docker compose -f aDespliegue/prod/docker-compose.yml build --no-cache

prod-up:
	docker compose -f aDespliegue/prod/docker-compose.yml up -d

MAKE

if ! $USE_SYMFONY; then
  cat > Makefile <<MAKE
.PHONY: up down build start stop sh logs ps prod-build prod-up

ENV_DIR = aDespliegue/dev
RUN_PHP = docker compose -f \$(ENV_DIR)/docker-compose.yml exec -w /workspace ${PROJECT_SLUG}_php

up:
	docker compose -f \$(ENV_DIR)/docker-compose.yml up -d

down:
	docker compose -f \$(ENV_DIR)/docker-compose.yml down

build:
	docker compose -f \$(ENV_DIR)/docker-compose.yml build --no-cache

start: up

stop: down

sh:
	\$(RUN_PHP) bash

logs:
	docker compose -f \$(ENV_DIR)/docker-compose.yml logs -f

ps:
	docker compose -f \$(ENV_DIR)/docker-compose.yml ps

prod-build:
	docker compose -f aDespliegue/prod/docker-compose.yml build --no-cache

prod-up:
	docker compose -f aDespliegue/prod/docker-compose.yml up -d

MAKE
fi

if $USE_AUTH && $USE_DB; then
  cat >> Makefile <<MAKE
admin:
	\$(RUN_PHP) php -r "\
	  require '\''/workspace/vendor/autoload.php'\'';\
	  (new Symfony\\Component\\Dotenv\\Dotenv())->bootEnv('\''/workspace/.env'\'');\
	  \$kernel = new App\\Kernel('\''dev'\'', true);\
	  \$kernel->boot();\
	  \$adminLogin = \$_ENV['\''ADMIN_LOGIN'\''] ?: getenv('\''ADMIN_LOGIN'\'') ?: '\''admin'\'';\
	  \$adminPassword = \$_ENV['\''ADMIN_PASSWORD'\''] ?: getenv('\''ADMIN_PASSWORD'\'') ?: '\''change_me_admin_password'\'';\
	  \$c = \$kernel->getContainer();\
	  \$em = \$c->get('\''doctrine'\'')->getManager();\
	  if (\$em->getRepository(App\\Entity\\User::class)->findOneBy(['\''login'\''=>\$adminLogin])) { echo '\''Ya existe.\n'\''; exit(0); }\
	  \$h = \$c->get(Symfony\\Component\\PasswordHasher\\Hasher\\UserPasswordHasherInterface::class);\
	  \$u = new App\\Entity\\User();\
	  \$u->setLogin(\$adminLogin);\
	  \$u->setPassword(\$h->hashPassword(\$u,\$adminPassword));\
	  \$u->setRoles(['\''ROLE_ADMIN'\'']);\
	  \$u->setActivo(true);\
	  \$em->persist(\$u); \$em->flush();\
	  echo \$adminLogin . '\'' creado.\n'\'';\
	"
MAKE
fi

# -----------------------------------------------------------------------------
# 13. .gitignore
# -----------------------------------------------------------------------------
cat > .gitignore <<GIT
.env
app/.env.local
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

SYMFONY_FLAGS=""

# Usamos --webapp como base para tener flex habilitado; los paquetes específicos se instalan después

docker compose -f aDespliegue/dev/docker-compose.yml exec -w /workspace ${PROJECT_SLUG}_php symfony new /workspace --webapp --debug --version=lts --no-git 2>/dev/null || docker compose -f aDespliegue/dev/docker-compose.yml exec -w /workspace ${PROJECT_SLUG}_php composer create-project symfony/skeleton /workspace

# Ajustar permisos de los archivos creados para el usuario actual
docker compose -f aDespliegue/dev/docker-compose.yml exec -w /workspace ${PROJECT_SLUG}_php chown -R $(id -u):$(id -g) /workspace

# -----------------------------------------------------------------------------
# 16. Instalar paquetes según módulos
# -----------------------------------------------------------------------------
step "Instalando paquetes seleccionados"

sym_exec() {
  docker compose -f aDespliegue/dev/docker-compose.yml exec -w /workspace ${PROJECT_SLUG}_php \
    bash -c "$1"
}

$USE_DB           && sym_exec "composer require symfony/orm-pack doctrine/doctrine-migrations-bundle"
$USE_AUTH         && sym_exec "composer require symfony/security-bundle"
$USE_JWT          && sym_exec "composer require lexik/jwt-authentication-bundle"
$USE_ADMIN        && sym_exec "composer require easycorp/easyadmin-bundle"


sym_exec "composer require --dev symfony/maker-bundle symfony/debug-bundle"

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
      sed -i 's|.*// @@USER_MENU_ITEM@@.*|        yield MenuItem::section('\''Seguridad'\'');\n        yield MenuItem::linkToCrud('\''Usuarios'\'', '\''fa fa-users'\'', \\App\\Entity\\User::class);|' "$DASHBOARD"
      echo "  ✓ Item 'Usuarios' agregado al DashboardController"
    fi
  fi

else
  echo "  (No se encontró el directorio stubs/, se omite este paso)"
fi

# Las credenciales reales van a app/.env.local (no se commitea, anula app/.env de Symfony)
cp .env app/.env.local
# .env.example va al repo como plantilla de referencia
cp .env.example app/.env.example
if $USE_DB; then
  step "Verificando conexión a la base de datos"
  if ! docker compose -f aDespliegue/dev/docker-compose.yml exec -w /workspace ${PROJECT_SLUG}_php php -r "
    require '/workspace/vendor/autoload.php';
    (new Symfony\Component\Dotenv\Dotenv())->bootEnv('/workspace/.env');
    \$host = \$_ENV['DB_HOST'] ?? 'host.docker.internal';
    \$port = \$_ENV['DB_PORT'] ?? 3306;
    \$user = \$_ENV['DB_USER'] ?? 'root';
    \$pass = \$_ENV['DB_PASSWORD'] ?? '';
    \$maxAttempts = 5;
    for (\$i = 1; \$i <= \$maxAttempts; \$i++) {
      try {
        \$pdo = new PDO('mysql:host=' . \$host . ';port=' . \$port, \$user, \$pass, [
          PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
          PDO::ATTR_TIMEOUT => 2
        ]);
        echo '  Conexión exitosa a la base de datos (' . \$host . ':' . \$port . ')' . PHP_EOL;
        exit(0);
      } catch (Exception \$e) {
        if (\$i === \$maxAttempts) {
          echo '  Error: No se pudo conectar al servidor de base de datos: ' . \$e->getMessage() . PHP_EOL;
          exit(1);
        }
        echo '  [' . \$i . '/' . \$maxAttempts . '] Esperando al servidor de base de datos (' . \$host . ':' . \$port . ')...' . PHP_EOL;
        sleep(2);
      }
    }
  "; then
     echo "❌ Error crítico: No se pudo establecer conexión con la base de datos."
     echo "   Por favor, verifica:"
     echo "   1. Que el servidor de base de datos en '${DEV_DB_HOST}:${DEV_DB_PORT}' esté encendido y operativo."
     echo "   2. Que el usuario '${DEV_DB_USER}' tenga permisos de acceso."
     echo "   3. Que la red o host estén configurados correctamente."
     exit 1
  fi

  sym_exec "php bin/console doctrine:database:create --if-not-exists 2>/dev/null || true"
fi

# Crear usuario admin por defecto si USE_AUTH está activo
if $USE_AUTH && $USE_DB; then
  step "Creando usuario admin por defecto"
  sym_exec "php bin/console make:migration --no-interaction 2>/dev/null || true"
  sym_exec "php bin/console doctrine:migrations:migrate --no-interaction 2>/dev/null || true"

  docker compose -f aDespliegue/dev/docker-compose.yml exec -w /workspace ${PROJECT_SLUG}_php php -r "
    require '/workspace/vendor/autoload.php';
    (new Symfony\Component\Dotenv\Dotenv())->bootEnv('/workspace/.env');
    \$kernel = new App\Kernel('dev', true);
    \$kernel->boot();
    \$adminLogin = \$_ENV['ADMIN_LOGIN'] ?: getenv('ADMIN_LOGIN') ?: 'admin';
    \$adminPassword = \$_ENV['ADMIN_PASSWORD'] ?: getenv('ADMIN_PASSWORD') ?: 'change_me_admin_password';
    \$container = \$kernel->getContainer();
    \$em = \$container->get('doctrine')->getManager();
    \$repo = \$em->getRepository(App\Entity\User::class);
    if (\$repo->findOneBy(['login' => \$adminLogin])) {
      echo 'Usuario admin ya existe.' . PHP_EOL; exit(0);
    }
    \$hasher = \$container->get(Symfony\\Component\\PasswordHasher\\Hasher\\UserPasswordHasherInterface::class);
    \$user = new App\\Entity\\User();
    \$user->setLogin(\$adminLogin);
    \$user->setPassword(\$hasher->hashPassword(\$user, \$adminPassword));
    \$user->setRoles(['ROLE_ADMIN']);
    \$user->setActivo(true);
    \$em->persist(\$user);
    \$em->flush();
    echo 'Usuario admin creado.' . PHP_EOL;
  " 2>/dev/null \
    && echo "  ✓ Usuario admin creado con ADMIN_LOGIN / ADMIN_PASSWORD" \
    || echo "  ⚠ No se pudo crear el admin. Corré: make migrate && make admin"
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

# Asegurar que todos los archivos nuevos creados sean del usuario host
docker compose -f aDespliegue/dev/docker-compose.yml exec -w /workspace ${PROJECT_SLUG}_php chown -R $(id -u):$(id -g) /workspace

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
echo "  └── .env"
echo ""
echo "  🌐  App:     http://localhost:${HTTP_PORT}"
$USE_AUTH && echo "  🔑  Admin:   ${DEV_ADMIN_LOGIN} / ADMIN_PASSWORD  ← contraseña definida en .env"

echo ""
echo "  Comandos:"
if $USE_SYMFONY; then
  echo "    make start     → levanta Docker + servidor Symfony"
  echo "    make serve     → solo arranca el servidor Symfony"
  echo "    make sh        → bash en el contenedor PHP"
  echo "    make cc        → cache:clear"
  $USE_DB      && echo "    make migrate   → doctrine:migrations:migrate"
  $USE_JWT     && echo "    make jwt-keys  → regenerar claves JWT"
  echo "    make logs-symfony → ver log del servidor Symfony"
else
  echo "    make start     → levanta Docker"
  echo "    make sh        → bash en el contenedor PHP"
  echo "    make logs      → ver logs de Docker"
fi
echo "    make prod-up   → levantar entorno prod (Nginx)"
echo ""
echo "  En VSCode: Dev Containers: Reopen in Container"
echo ""
