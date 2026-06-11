# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

A collection of shell-script initializers that scaffold Docker-based projects. Each subdirectory (`php/`, `mysql/`, `phpmyadmin/`, `backup/`) is an independent initializer: copy the example `.conf`, edit it, run the `init-*.sh` script, and it generates a ready-to-use project directory.

## Running the Initializers

```bash
# PHP/Symfony project (most complex — see Configuration section)
cd php/
./init-php.sh my-project.conf

# MySQL container
cd mysql/
./init-mysql.sh my-project.conf

# PostgreSQL container
cd postgres/
./init-postgres.sh my-project.conf

# phpMyAdmin panel (MySQL)
cd phpmyadmin/
./init-phpmyadmin.sh my-project.conf

# pgAdmin4 panel (PostgreSQL)
cd pgadmin/
./init-pgadmin.sh my-project.conf

# Backup service (Backblaze B2)
cd backup/
./init-backup.sh my-project.conf
```

The scripts require running Docker containers when a database or backup container is referenced — they verify container presence before proceeding.

## Generated Project Commands (Makefile)

After `init-php.sh` runs, the generated project has a `Makefile` with these targets:

```bash
make up-dev / down-dev / build-dev   # Dev Docker stack
make up-prod / down-prod / build-prod # Prod Docker stack (Nginx + PHP-FPM)
make sh-dev / sh-prod                 # Shell into container
make serve / stop                     # Symfony dev server (dev only)
make cc-dev / cc-prod                 # Clear Symfony cache
make migrate-dev / migration-dev      # Doctrine migrations
make logs-dev / logs-symfony          # Docker and Symfony logs
make jwt-keys-dev                     # Generate JWT keypair (if USE_JWT=true)
```

## PHP Initializer Architecture (`php/init-php.sh`)

The main script (~1300 lines) reads a `.conf` file and conditionally:
1. Verifies required Docker containers are running
2. Creates the project directory with `aDespliegue/dev/`, `aDespliegue/prod/`, `.devcontainer/`, and `app/`
3. Installs Symfony (`minimal` = skeleton, `webapp` = full distribution)
4. Copies stubs from `php/stubs/` based on feature flags
5. Installs Composer packages matching enabled features
6. Runs database migrations and creates the initial admin user

### Stubs (`php/stubs/`)

Code templates copied into generated projects based on config flags:

| Directory | Condition |
|-----------|-----------|
| `common/` | Always — `HomeController`, `AdminLabel` attribute |
| `auth/` | `USE_AUTH=true` — User entity, LoginController, security.yaml |
| `admin/` | `USE_ADMIN=true` — EasyAdmin DashboardController, BaseCrudController |
| `auth_admin/` | Both `USE_AUTH` and `USE_ADMIN` — UserCrudController |
| `backup/` | `BACKUP_CONTAINER_NAME` set — BackupAuditoria entity, TransaccionListener |

### Key Configuration Variables

```ini
PHP_VERSION=8.4
PORT_DEV=8080
PORT_PROD=80
SYMFONY_INSTALL=minimal        # minimal | webapp
USE_SYMFONY=true
USE_AUTH=true                  # Adds User entity + login flow
USE_JWT=false                  # Requires USE_AUTH=true
USE_ADMIN=true                 # Adds EasyAdmin panel
BACKUP_CONTAINER_NAME=         # Name of a running backup container

DB_HOST_DEV=host.docker.internal
DB_PORT_DEV=3306
DB_NAME_DEV=myproject_dev
DB_USER_DEV=app
DB_PASSWORD_DEV=secret
DB_NETWORK_DEV=               # External Docker network name (empty = internal)

ADMIN_LOGIN=admin              # Created if USE_AUTH=true
ADMIN_PASSWORD=admin123
JWT_PASSPHRASE=changeme        # Used if USE_JWT=true
```

### Docker Architecture

**Dev:** Single PHP-FPM container + Symfony dev server, project root mounted as volume.

**Prod:** Multistage build — builder stage (Composer install) → minimal runtime image + separate `nginx:alpine` container as reverse proxy on port 80.

## Typical Setup Order

1. Run `mysql/init-mysql.sh` first (PHP initializer requires the DB container to be running)
2. Start the MySQL container (`make up-dev` inside the generated MySQL project)
3. Run `php/init-php.sh` — it connects to the running DB, creates schema, and seeds admin user
4. Optionally run `backup/init-backup.sh` before PHP init if `BACKUP_CONTAINER_NAME` is set
