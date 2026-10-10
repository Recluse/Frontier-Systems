<?php

declare(strict_types=1);

namespace Frontier\ControlPlane\Tests\Unit;

use Frontier\ControlPlane\Diagnostics\RuntimeMetrics;
use PHPUnit\Framework\TestCase;

final class RuntimeMetricsTest extends TestCase
{
    public function testSnapshotReportsRuntimeMetadata(): void
    {
        $snapshot = (new RuntimeMetrics())->snapshot();

        self::assertSame('ok', $snapshot['status']);
        self::assertGreaterThanOrEqual(0.0, $snapshot['uptime_seconds']);
        self::assertSame(PHP_VERSION, $snapshot['php_version']);
    }
}
