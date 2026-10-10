<?php

declare(strict_types=1);

namespace Frontier\Profiling\Persistence;

use Frontier\Profiling\Capture\ProfileCaptureDocument;
use Frontier\WorldContracts\World\WorldIdentity;
use React\Promise\PromiseInterface;

/** Nonblocking storage boundary. Failures reject promises; adapters never await ticks. */
interface ProfileCaptureRepositoryInterface
{
    /** @return PromiseInterface<StoredProfileCapture|null> */
    public function loadLatest(WorldIdentity $identity): PromiseInterface;

    /**
     * Save latest capture; older frontiers must reject without replacing newer data.
     * Identical normalized bytes resolve the existing receipt while it is retained.
     *
     * @return PromiseInterface<StoredProfileCapture>
     */
    public function store(ProfileCaptureDocument $capture): PromiseInterface;
}
