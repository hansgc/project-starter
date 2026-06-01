<?php

namespace App\EventListener;

use App\Entity\BackupAuditoria;
use Doctrine\Bundle\DoctrineBundle\Attribute\AsDoctrineListener;
use Doctrine\ORM\Events;
use Doctrine\ORM\Event\PostPersistEventArgs;
use Doctrine\ORM\Event\PostUpdateEventArgs;
use Doctrine\ORM\Event\PostRemoveEventArgs;

#[AsDoctrineListener(event: Events::postPersist)]
#[AsDoctrineListener(event: Events::postUpdate)]
#[AsDoctrineListener(event: Events::postRemove)]
class TransaccionListener
{
    // Evita multiples actualizaciones en una misma request
    private bool $yaRegistrado = false;

    public function postPersist(PostPersistEventArgs $args): void
    {
        $this->registrar($args);
    }

    public function postUpdate(PostUpdateEventArgs $args): void
    {
        $this->registrar($args);
    }

    public function postRemove(PostRemoveEventArgs $args): void
    {
        $this->registrar($args);
    }

    private function registrar(mixed $args): void
    {
        // Ignorar si el evento es sobre la misma tabla de auditoria
        // para evitar loop infinito
        if ($args->getObject() instanceof BackupAuditoria) {
            return;
        }

        if ($this->yaRegistrado) {
            return;
        }

        $this->yaRegistrado = true;

        $conn = $args->getObjectManager()->getConnection();

        // Verificar si ya existe un registro en la tabla
        $existe = $conn->fetchOne("SELECT COUNT(*) FROM backup_auditoria");

        if ((int)$existe === 0) {
            $conn->executeStatement(
                "INSERT INTO backup_auditoria (ultima_transaccion) VALUES (NOW())"
            );
        } else {
            $conn->executeStatement(
                "UPDATE backup_auditoria SET ultima_transaccion = NOW() LIMIT 1"
            );
        }
    }
}
