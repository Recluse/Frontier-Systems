<?php

declare(strict_types=1);

namespace Frontier\WorldContracts\Persistence;

use Frontier\WorldContracts\World\WorldSnapshotDocument;
use InvalidArgumentException;

/** Idempotent compare-and-swap request for storing a world snapshot. */
final readonly class SnapshotWriteRequest
{
    public function __construct(
        public string $requestId,
        public int $expectedRevision,
        public WorldSnapshotDocument $snapshot,
    ) {
        if (trim($requestId) === '' || strlen($requestId) > 128) {
            throw new InvalidArgumentException('Snapshot request ID must be a non-empty string of at most 128 bytes.');
        }
        if ($expectedRevision < 0) {
            throw new InvalidArgumentException('Expected snapshot revision must be non-negative; use zero when creating a world record.');
        }
    }
}
