<?php

declare(strict_types=1);

namespace Frontier\ControlPlane\Tests\Unit;

use Frontier\Foundation\Cache\RememberingCache;
use PHPUnit\Framework\TestCase;
use React\Cache\CacheInterface;
use React\Promise\Deferred;
use RuntimeException;
use Throwable;

use function React\Promise\reject;
use function React\Promise\resolve;

final class RememberingCacheTest extends TestCase
{
    public function testReadExceptionRejectsAndAllowsTheSameKeyToRetry(): void
    {
        $failure = new RuntimeException('read unavailable');
        $attempt = 0;
        $adapter = $this->createMock(CacheInterface::class);
        $adapter->expects(self::exactly(2))->method('get')->willReturnCallback(
            function ($key, $default) use (&$attempt, $failure) {
                if (++$attempt === 1) {
                    throw $failure;
                }
                return resolve($default);
            }
        );
        $adapter->expects(self::once())->method('set')->willReturn(resolve(true));
        $cache = new RememberingCache($adapter);
        $reason = null;
        $cache->remember('same-key', static fn () => 41)->then(null, function (Throwable $error) use (&$reason): void {
            $reason = $error;
        });
        self::assertSame($failure, $reason);
        self::assertSame(0, $cache->metrics()['in_flight']);
        $value = null;
        $cache->remember('same-key', static fn () => 42)->then(function ($result) use (&$value): void {
            $value = $result;
        });
        self::assertSame(42, $value);
        self::assertSame(0, $cache->metrics()['coalesced']);
    }

    public function testWriteExceptionPreservesProducedValueAndAllowsRetry(): void
    {
        $attempt = 0;
        $adapter = $this->createMock(CacheInterface::class);
        $adapter->expects(self::exactly(2))->method('get')->willReturnCallback(static fn ($key, $default) => resolve($default));
        $adapter->expects(self::exactly(2))->method('set')->willReturnCallback(
            function () use (&$attempt) {
                if (++$attempt === 1) {
                    throw new RuntimeException('write unavailable');
                }
                return resolve(true);
            }
        );
        $cache = new RememberingCache($adapter);
        $values = [];
        foreach ([41, 42] as $produced) {
            $cache->remember('same-key', static fn () => $produced)->then(function ($value) use (&$values): void {
                $values[] = $value;
            });
            self::assertSame(0, $cache->metrics()['in_flight']);
        }
        self::assertSame([41, 42], $values);
        self::assertSame(1, $cache->metrics()['write_failures']);
        self::assertSame(0, $cache->metrics()['producer_failures']);
    }

    public function testCoalescedReadersReceiveValueWhenTheWriteThrows(): void
    {
        $producer = new Deferred();
        $adapter = $this->createMock(CacheInterface::class);
        $adapter->expects(self::once())->method('get')->willReturnCallback(static fn ($key, $default) => resolve($default));
        $adapter->expects(self::once())->method('set')->willThrowException(new RuntimeException('write unavailable'));
        $cache = new RememberingCache($adapter);
        $first = $cache->remember('shared', static fn () => $producer->promise());
        $second = $cache->remember('shared', static function (): never {
            throw new RuntimeException('coalesced producer must not run');
        });
        self::assertSame($first, $second);
        $values = [];
        foreach ([$first, $second] as $promise) {
            $promise->then(function ($value) use (&$values): void {
                $values[] = $value;
            });
        }
        $producer->resolve(42);
        self::assertSame([42, 42], $values);
        self::assertSame(0, $cache->metrics()['in_flight']);
        self::assertSame(1, $cache->metrics()['coalesced']);
        self::assertSame(1, $cache->metrics()['write_failures']);
    }

    public function testRejectedWriteKeepsExistingBestEffortSemantics(): void
    {
        $adapter = $this->createMock(CacheInterface::class);
        $adapter->method('get')->willReturnCallback(static fn ($key, $default) => resolve($default));
        $adapter->method('set')->willReturnCallback(static fn () => reject(new RuntimeException('async write unavailable')));
        $cache = new RememberingCache($adapter);
        $value = null;
        $cache->remember('key', static fn () => null)->then(function ($result) use (&$value): void {
            $value = ['resolved', $result];
        });
        self::assertSame(['resolved', null], $value);
        self::assertSame(1, $cache->metrics()['write_failures']);
        self::assertSame(0, $cache->metrics()['in_flight']);
    }
}
