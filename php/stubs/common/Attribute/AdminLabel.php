<?php

namespace App\Attribute;

use Attribute;

#[Attribute(Attribute::TARGET_PROPERTY)]
class AdminLabel
{
    public function __construct(
        public ?string $full = null,
        public ?string $short = null,
        public ?string $memo = null,
        public ?bool $disabled = null,
    ) {}
}
