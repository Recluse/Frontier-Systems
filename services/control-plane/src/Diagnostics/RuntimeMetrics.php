<?php

declare(strict_types=1);

namespace Frontier\ControlPlane\Diagnostics;

final class RuntimeMetrics
{
    private readonly int $startedAtNanoseconds;

    public function __construct()
    {
        $this->startedAtNanoseconds = hrtime(true);
    }

    /** @return array{status: string, uptime_seconds: float, php_version: string} */
    public function snapshot(): array
    {
        return [
            'status' => 'ok',
            'uptime_seconds' => (hrtime(true) - $this->startedAtNanoseconds) / 1_000_000_000,
            'php_version' => PHP_VERSION,
        ];
    }
}
