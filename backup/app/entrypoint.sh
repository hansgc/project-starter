#!/bin/bash

echo "[ENTRYPOINT] Contenedor de backup iniciado."
echo "[ENTRYPOINT] Ejecutando backup inicial..."

/usr/local/bin/backup.sh

echo "[ENTRYPOINT] Iniciando cron..."
cron -f
