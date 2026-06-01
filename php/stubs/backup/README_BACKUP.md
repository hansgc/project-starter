# Instrucciones para integrar Backup al proyecto

## Cuando `USE_BACKUP=true` en el archivo .conf:

1. Se copia la entidad `BackupAuditoria` a `app/src/Entity/`
2. Se copia el event listener `TransaccionListener` a `app/src/EventListener/`
3. Se copia la migración `Version20260531000000.php` a `app/migrations/`

## Después de ejecutar init-php.sh:

### Ejecutar migraciones:
```bash
cd proyecto
make migrate
```

O manualmente:
```bash
docker compose -f aDespliegue/dev/docker-compose.yml exec -w /workspace/app php-service \
  php bin/console doctrine:migrations:migrate --no-interaction
```

### Verificar que funciona:
```bash
docker compose -f aDespliegue/dev/docker-compose.yml exec mysql mysql \
  -h mysql -u app -p'secret' mi_proyecto_db \
  -e "SELECT * FROM backup_auditoria;"
```

## Cómo funciona:

- Cada vez que se inserta, actualiza o elimina un registro en la BD,
  el evento listener `TransaccionListener` actualiza automáticamente
  el campo `ultima_transaccion` en la tabla `backup_auditoria`.

- El contenedor de backup consulta esta tabla para decidir si hay cambios.

- La tabla se crea automáticamente al ejecutar las migraciones.
