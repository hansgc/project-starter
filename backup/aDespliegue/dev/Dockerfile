FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    default-mysql-client \
    cron \
    curl \
    gzip \
    unzip \
    && curl https://rclone.org/install.sh | bash \
    && rm -rf /var/lib/apt/lists/*

# Copiar configuracion de rclone (credenciales Google Drive)
COPY app/rclone.conf /root/.config/rclone/rclone.conf 2>/dev/null || true

# Copiar scripts
COPY app/backup.sh     /usr/local/bin/backup.sh
COPY app/crontab       /etc/cron.d/backup-cron
COPY app/entrypoint.sh /entrypoint.sh

# Permisos
RUN chmod +x /usr/local/bin/backup.sh \
    && chmod +x /entrypoint.sh \
    && chmod 0644 /etc/cron.d/backup-cron \
    && mkdir -p /root/.config/rclone \
    && chmod 600 /root/.config/rclone/rclone.conf 2>/dev/null || true \
    && crontab /etc/cron.d/backup-cron

# Directorios de trabajo
RUN mkdir -p /backups/pendientes /backups/enviados

ENTRYPOINT ["/entrypoint.sh"]
