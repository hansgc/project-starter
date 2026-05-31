# Proyecto Backup

Sistema automatizado de backup de bases de datos MySQL con sincronización a Google Drive.

## Características

- ✅ Backup automático cada hora (configurable con cron)
- ✅ Detección de cambios en la BD antes de hacer backup
- ✅ Compresión automática con gzip
- ✅ Sincronización a Google Drive con rclone
- ✅ Almacenamiento local de pendientes si no hay internet
- ✅ Reintentos automáticos cuando vuelve la conexión
- ✅ Limpieza automática de backups de más de 30 días

## Estructura

```
backup/
├── .devcontainer/
│   └── devcontainer.json
├── aDespliegue/
│   ├── dev/
│   │   ├── Dockerfile
│   │   └── docker-compose.yml
│   └── prod/
│       ├── Dockerfile
│       └── docker-compose.yml
├── app/
│   ├── .env                  (variables de configuración)
│   ├── backup.sh             (script principal)
│   ├── crontab               (horario de ejecución)
│   ├── entrypoint.sh         (arranque del contenedor)
│   └── rclone.conf           (credenciales Google Drive)
├── Makefile
├── .gitignore
└── README.md
```

## Configuración Rápida

### 1. Clonar estructura
```bash
cd /home/hans/proyectos/project-starter/backup
```

### 2. Configurar variables de entorno
Editar `app/.env` con los datos de tu MySQL:

```bash
DB_HOST=mysql
DB_PORT=3306
DB_NAME=mibasededatos
DB_USER=usuario
DB_PASS=password123

CLIENTE_ID=cliente_juan
DRIVE_REMOTE=gdrive_cliente_juan
DRIVE_PATH=Backups
```

### 3. Configurar Google Drive (rclone)
```bash
# Generar credenciales
docker compose -f aDespliegue/dev/docker-compose.yml run --rm backup \
  rclone config

# Seleccionar opción "new remote" y seguir los pasos de autenticación
# El archivo rclone.conf se guardará en app/rclone.conf
```

## Comandos

### Desarrollo
```bash
make up              # Levantar contenedores
make down            # Detener contenedores
make start           # Arrancar (up)
make stop            # Parar (down)

make sh              # Bash dentro del contenedor
make logs            # Ver logs en tiempo real
make ps              # Estado de servicios

make backup-manual   # Forzar backup inmediatamente
make backup-logs     # Ver últimas líneas del log
make backup-pendientes   # Listar backups en cola
make backup-enviados     # Listar backups ya enviados
```

### Producción
```bash
make prod-up         # Levantar en producción
make prod-down       # Detener producción
```

## Flujo de Funcionamiento

1. **Cada hora** (cron ejecuta `backup.sh`):
   - Verifica si hay cambios en `backup_auditoria`
   - Si hay cambios:
     - Genera dump comprimido → `/backups/pendientes/`
     - Actualiza `ultimo_backup` en BD
   - Verifica internet
   - Si hay internet + backups pendientes:
     - Sube a Google Drive con rclone
     - Mueve a `/backups/enviados/`
   - Limpia backups de más de 30 días

2. **Sin internet**:
   - Los backups quedan en `/backups/pendientes/`
   - Se reintenta en el siguiente ciclo

3. **Inicio del contenedor**:
   - Ejecuta backup inicial
   - Inicia cron daemon

## Variables de Entorno

| Variable | Descripción |
|----------|-------------|
| `DB_HOST` | Host del servidor MySQL |
| `DB_PORT` | Puerto MySQL (3306) |
| `DB_NAME` | Nombre de la BD a respaldar |
| `DB_USER` | Usuario MySQL |
| `DB_PASS` | Contraseña MySQL |
| `CLIENTE_ID` | ID del cliente (carpeta en Drive) |
| `DRIVE_REMOTE` | Nombre remoto rclone configurado |
| `DRIVE_PATH` | Ruta en Google Drive |

## Notas Importantes

- El archivo `app/rclone.conf` contiene credenciales y **no debe commiterse** al repo
- Los backups locales se mantienen indefinidamente en `/backups/`
- El crontab ejecuta cada hora. Ajustar en `app/crontab` si es necesario
- Se requiere tabla `backup_auditoria` en la BD con campos `ultima_transaccion` y `ultimo_backup`

## Solución de Problemas

### Backups no se generan
```bash
# Revisar logs
make backup-logs

# Verificar conectividad a MySQL
make sh
mysql -h mysql -u usuario -p'password123' -e "SELECT 1"
```

### Backups no se envían a Drive
```bash
# Verificar rclone.conf
make sh
rclone config show

# Probar conexión
rclone lsd gdrive_cliente_juan:
```

### Ver estado actual
```bash
make ps
make backup-pendientes
make backup-enviados
```
