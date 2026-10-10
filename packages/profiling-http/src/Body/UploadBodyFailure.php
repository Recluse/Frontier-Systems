<?php

declare(strict_types=1);

namespace Frontier\ProfilingHttp\Body;

use RuntimeException;

/** Stable HTTP classification; raw stream failures are never returned to clients. */
final class UploadBodyFailure extends RuntimeException
{
    public function __construct(public readonly int $status, public readonly string $errorCode)
    {
        parent::__construct($errorCode);
    }
}
