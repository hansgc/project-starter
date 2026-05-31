.PHONY: up down build start stop sh logs ps backup-manual backup-logs restore-list

ENV_DIR = aDespliegue/dev

up:
	docker compose -f $(ENV_DIR)/docker-compose.yml up -d

down:
	docker compose -f $(ENV_DIR)/docker-compose.yml down

build:
	docker compose -f $(ENV_DIR)/docker-compose.yml build --no-cache

start: up

stop: down

sh:
	docker compose -f $(ENV_DIR)/docker-compose.yml exec backup bash

logs:
	docker compose -f $(ENV_DIR)/docker-compose.yml logs -f backup

ps:
	docker compose -f $(ENV_DIR)/docker-compose.yml ps

backup-manual:
	docker compose -f $(ENV_DIR)/docker-compose.yml exec backup /usr/local/bin/backup.sh

backup-logs:
	docker compose -f $(ENV_DIR)/docker-compose.yml exec backup tail -50 /var/log/backup.log

backup-pendientes:
	docker compose -f $(ENV_DIR)/docker-compose.yml exec backup ls -lh /backups/pendientes/

backup-enviados:
	docker compose -f $(ENV_DIR)/docker-compose.yml exec backup ls -lh /backups/enviados/

prod-up:
	docker compose -f aDespliegue/prod/docker-compose.yml up -d

prod-down:
	docker compose -f aDespliegue/prod/docker-compose.yml down
