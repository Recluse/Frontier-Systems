<?php

declare(strict_types=1);

namespace Frontier\WorldContracts\World;

use InvalidArgumentException;

/** Stable identity for one persisted simulation region. */
final readonly class WorldIdentity
{
    public function __construct(
        public string $worldId,
        public string $regionId,
    ) {
        foreach (['world_id' => $worldId, 'region_id' => $regionId] as $name => $value) {
            if (trim($value) === '' || strlen($value) > 128) {
                throw new InvalidArgumentException(sprintf('%s must be a non-empty string of at most 128 bytes.', $name));
            }
        }
    }
}
