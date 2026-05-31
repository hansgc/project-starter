#!/bin/bash

LOG="/var/log/backup.log"
DIR_PENDIENTES="/backups/pendientes"
DIR_ENVIADOS="/backups/enviados"

mkdir -p "$DIR_PENDIENTES" "$DIR_ENVIADOS"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG"
}

# ── FUNCION 1: Verificar si hubo cambios ─────────────────────
# Consulta la tabla backup_auditoria creada por el proyecto app.
# Si ultima_transaccion es mayor que ultimo_backup, hay cambios.
hubo_cambios() {
    RESULTADO=$(mysql \
        --host="$DB_HOST" \
        --port="$DB_PORT" \
        --user="$DB_USER" \
        --password="$DB_PASS" \
        --silent --skip-column-names \
        -e "SELECT
                CASE
                    WHEN ultimo_backup IS NULL THEN 'SI'
                    WHEN ultima_transaccion > ultimo_backup THEN 'SI'
                    ELSE 'NO'
                END
            FROM backup_auditoria
            LIMIT 1;" 2>/dev/null)

    if [ "$RESULTADO" = "SI" ]; then
        return 0  # Hubo cambios
    else
        return 1  # Sin cambios
    fi
}

# ── FUNCION 2: Generar el backup comprimido ───────────────────
generar_backup() {
    FECHA=$(date +%Y%m%d_%H%M%S)
    ARCHIVO="${DIR_PENDIENTES}/backup_${DB_NAME}_${FECHA}.sql.gz"

    log "Generando backup: $(basename $ARCHIVO)"

    mysqldump \
        --host="$DB_HOST" \
        --port="$DB_PORT" \
        --user="$DB_USER" \
        --password="$DB_PASS" \
        --single-transaction \
        --routines \
        --triggers \
        "$DB_NAME" | gzip > "$ARCHIVO"

    if [ $? -ne 0 ]; then
        log "ERROR: Fallo el mysqldump. Se elimina archivo corrupto."
        rm -f "$ARCHIVO"
        return 1
    fi

    TAMANIO=$(du -sh "$ARCHIVO" | cut -f1)
    log "Backup generado. Tamanio: $TAMANIO"

    # Registrar en la tabla que se hizo el backup
    mysql \
        --host="$DB_HOST" \
        --port="$DB_PORT" \
        --user="$DB_USER" \
        --password="$DB_PASS" \
        -e "UPDATE backup_auditoria SET ultimo_backup = NOW() LIMIT 1;" 2>/dev/null

    return 0
}

# ── FUNCION 3: Verificar conexion a internet ──────────────────
hay_conexion() {
    curl -s --max-time 10 https://www.google.com > /dev/null 2>&1
    return $?
}

# ── FUNCION 4: Enviar todos los pendientes a Google Drive ─────
enviar_pendientes() {
    PENDIENTES=$(ls "$DIR_PENDIENTES"/*.sql.gz 2>/dev/null)

    if [ -z "$PENDIENTES" ]; then
        log "No hay backups pendientes de envio."
        return 0
    fi

    CANTIDAD=$(echo "$PENDIENTES" | wc -l)

    if ! hay_conexion; then
        log "Sin conexion a internet. $CANTIDAD backup(s) pendiente(s) en cola."
        return 1
    fi

    log "Conexion disponible. Enviando $CANTIDAD backup(s) pendiente(s)..."

    for ARCHIVO in $PENDIENTES; do
        NOMBRE=$(basename "$ARCHIVO")
        log "Enviando: $NOMBRE"

        rclone copy "$ARCHIVO" "${DRIVE_REMOTE}:${DRIVE_PATH}/${CLIENTE_ID}" \
            --config /root/.config/rclone/rclone.conf \
            --retries 3

        if [ $? -eq 0 ]; then
            log "OK enviado: $NOMBRE"
            mv "$ARCHIVO" "$DIR_ENVIADOS/"
            echo "$(date '+%Y-%m-%d %H:%M:%S') - $NOMBRE" >> "$DIR_ENVIADOS/enviados.log"
        else
            log "ERROR al enviar: $NOMBRE. Se reintentara en el proximo ciclo."
        fi
    done
}

# ── FUNCION 5: Limpiar backups enviados de mas de 30 dias ─────
limpiar_antiguos() {
    ELIMINADOS=$(find "$DIR_ENVIADOS" -name "*.sql.gz" -mtime +30 -delete -print | wc -l)
    if [ "$ELIMINADOS" -gt 0 ]; then
        log "Limpieza: $ELIMINADOS archivo(s) antiguo(s) eliminado(s)."
    fi
}

# ── EJECUCION PRINCIPAL ───────────────────────────────────────
log "===== Iniciando ciclo de backup ====="

if hubo_cambios; then
    log "Cambios detectados en la base de datos."
    generar_backup
else
    log "Sin cambios desde el ultimo backup. No se genera archivo."
fi

enviar_pendientes
limpiar_antiguos

log "===== Ciclo finalizado ====="
