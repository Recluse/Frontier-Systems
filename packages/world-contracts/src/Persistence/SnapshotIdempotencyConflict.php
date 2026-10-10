<?php

declare(strict_types=1);

namespace Frontier\WorldContracts\Persistence;

use RuntimeException;

/** Raised when a request ID is reused for a different snapshot write. */
final class SnapshotIdempotencyConflict extends RuntimeException
{
    public function __construct()
    {
        parent::__construct('Snapshot request ID was already used with different content.');
    }
}
