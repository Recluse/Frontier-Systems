<?php

declare(strict_types=1);

namespace Frontier\WorldContracts\Persistence;

use DateTimeImmutable;
use Frontier\WorldContracts\World\WorldSnapshotDocument;
use InvalidArgumentException;

/** Persisted snapshot and storage revision metadata. */
final readonly class StoredWorldSnapshot
{
    public function __construct(
        public WorldSnapshotDocument $snapshot,
        public int $revision,
        public DateTimeImmutable $savedAt,
    ) {
        if ($revision < 1) {
            throw new InvalidArgumentException('Stored snapshot revisions start at one.');
        }
    }
}
