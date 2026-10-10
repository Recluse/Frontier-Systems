<?php

declare(strict_types=1);

namespace Frontier\Profiling\Persistence;

use Frontier\Profiling\Capture\ProfileCaptureDocument;

/** Immutable receipt; sequence belongs to this repository process, not world state. */
final readonly class StoredProfileCapture
{
    public function __construct(
        public ProfileCaptureDocument $document,
        public int $sequence,
        public string $fingerprint,
    ) {
    }
}
