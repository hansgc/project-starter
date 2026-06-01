<?php

declare(strict_types=1);

namespace DoctrineMigrations;

use Doctrine\DBAL\Schema\Schema;
use Doctrine\Migrations\AbstractMigration;

/**
 * Crea la tabla backup_auditoria para registrar transacciones.
 * Esta tabla es consultada por el contenedor de backup para detectar cambios.
 */
final class Version20260531000000 extends AbstractMigration
{
    public function getDescription(): string
    {
        return 'Create backup_auditoria table for tracking transactions';
    }

    public function up(Schema $schema): void
    {
        $this->addSql('CREATE TABLE backup_auditoria (
            id INT AUTO_INCREMENT PRIMARY KEY,
            ultima_transaccion DATETIME DEFAULT NULL,
            ultimo_backup DATETIME DEFAULT NULL
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci');
    }

    public function down(Schema $schema): void
    {
        $this->addSql('DROP TABLE IF EXISTS backup_auditoria');
    }
}
