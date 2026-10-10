<?php

declare(strict_types=1);

namespace Frontier\WorldContracts\Persistence;

use Frontier\WorldContracts\World\WorldIdentity;
use React\Promise\PromiseInterface;

/**
 * Asynchronous persistence boundary for versioned world snapshots.
 *
 * Implementations must atomically compare revisions and record request IDs with
 * successful writes. Repeating a request ID with the same content resolves to the
 * original stored result; reusing it with different content rejects with
 * SnapshotIdempotencyConflict. A stale expected revision rejects with
 * SnapshotRevisionConflict. Rejections are delivered through the returned promise.
 */
interface WorldSnapshotRepositoryInterface
{
    /**
     * @return PromiseInterface<StoredWorldSnapshot|null> Resolves null when no snapshot exists.
     */
    public function load(WorldIdentity $identity): PromiseInterface;

    /**
     * @return PromiseInterface<StoredWorldSnapshot> Resolves with the committed revision.
     */
    public function save(SnapshotWriteRequest $request): PromiseInterface;
}
