<?php

declare(strict_types=1);

namespace Frontier\WorldContracts\Persistence;

use RuntimeException;

/** Raised when compare-and-swap persistence sees a different current revision. */
final class SnapshotRevisionConflict extends RuntimeException
{
    public function __construct(
        public readonly int $expectedRevision,
        public readonly int $currentRevision,
    ) {
        parent::__construct(sprintf('Snapshot revision conflict: expected %d, current revision is %d.', $expectedRevision, $currentRevision));
    }
}
