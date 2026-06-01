<?php

namespace App\Entity;

use Doctrine\ORM\Mapping as ORM;

#[ORM\Entity]
#[ORM\Table(name: 'backup_auditoria')]
class BackupAuditoria
{
    #[ORM\Id, ORM\GeneratedValue, ORM\Column]
    private ?int $id = null;

    #[ORM\Column(type: 'datetime', nullable: true)]
    private ?\DateTime $ultimaTransaccion = null;

    #[ORM\Column(type: 'datetime', nullable: true)]
    private ?\DateTime $ultimoBackup = null;

    public function getId(): ?int
    {
        return $this->id;
    }

    public function getUltimaTransaccion(): ?\DateTime
    {
        return $this->ultimaTransaccion;
    }

    public function setUltimaTransaccion(\DateTime $dt): self
    {
        $this->ultimaTransaccion = $dt;
        return $this;
    }

    public function getUltimoBackup(): ?\DateTime
    {
        return $this->ultimoBackup;
    }

    public function setUltimoBackup(\DateTime $dt): self
    {
        $this->ultimoBackup = $dt;
        return $this;
    }
}
