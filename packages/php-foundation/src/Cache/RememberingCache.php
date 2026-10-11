<?php

declare(strict_types=1);

namespace Frontier\Foundation\Cache;

use React\Cache\CacheInterface;
use React\Promise\Deferred;
use React\Promise\PromiseInterface;
use Throwable;

use function React\Promise\resolve;

/**
 * Adds asynchronous cache-aside reads and duplicate-work coalescing to a ReactPHP cache.
 *
 * The producer may return a value or a PromiseInterface. Cache writes are best-effort:
 * a failed cache write does not discard a successfully produced value.
 */
final class RememberingCache
{
    private readonly object $missSentinel;
    /** @var array<string, PromiseInterface<mixed>> */
    private array $inFlight = [];

    /** @var array{hits: int, misses: int, coalesced: int, producer_failures: int, write_failures: int} */
    private array $metrics = [
        'hits' => 0,
        'misses' => 0,
        'coalesced' => 0,
        'producer_failures' => 0,
        'write_failures' => 0,
    ];

    public function __construct(private readonly CacheInterface $cache)
    {
        $this->missSentinel = new \stdClass();
    }

    /**
     * Return a cached value or asynchronously produce and cache one.
     * Concurrent misses for the same key share one producer operation.
     *
     * @param callable(): (mixed|PromiseInterface<mixed>) $producer
     */
    public function remember(string $key, callable $producer, ?float $ttl = null): PromiseInterface
    {
        if (isset($this->inFlight[$key])) {
            ++$this->metrics['coalesced'];

            return $this->inFlight[$key];
        }

        $deferred = new Deferred();
        $promise = $deferred->promise();
        $this->inFlight[$key] = $promise;

        try {
            $lookup = $this->cache->get($key, $this->missSentinel);
        } catch (Throwable $exception) {
            unset($this->inFlight[$key]);
            $deferred->reject($exception);

            return $promise;
        }

        $lookup->then(
            function (mixed $cachedValue) use ($key, $producer, $ttl, $deferred): void {
                if ($cachedValue !== $this->missSentinel) {
                    ++$this->metrics['hits'];
                    unset($this->inFlight[$key]);
                    $deferred->resolve($cachedValue);

                    return;
                }

                ++$this->metrics['misses'];

                try {
                    $producedValue = $producer();
                } catch (Throwable $exception) {
                    ++$this->metrics['producer_failures'];
                    unset($this->inFlight[$key]);
                    $deferred->reject($exception);

                    return;
                }

                resolve($producedValue)->then(
                    function (mixed $value) use ($key, $ttl, $deferred): void {
                        try {
                            $write = $this->cache->set($key, $value, $ttl);
                        } catch (Throwable $exception) {
                            ++$this->metrics['write_failures'];
                            unset($this->inFlight[$key]);
                            $deferred->resolve($value);

                            return;
                        }

                        $write->then(
                            function (bool $stored) use ($key, $value, $deferred): void {
                                if (!$stored) {
                                    ++$this->metrics['write_failures'];
                                }

                                unset($this->inFlight[$key]);
                                $deferred->resolve($value);
                            },
                            function (mixed $reason) use ($key, $value, $deferred): void {
                                ++$this->metrics['write_failures'];
                                unset($this->inFlight[$key]);
                                $deferred->resolve($value);
                            }
                        );
                    },
                    function (mixed $reason) use ($key, $deferred): void {
                        ++$this->metrics['producer_failures'];
                        unset($this->inFlight[$key]);
                        $deferred->reject($reason);
                    }
                );
            },
            function (mixed $reason) use ($key, $deferred): void {
                unset($this->inFlight[$key]);
                $deferred->reject($reason);
            }
        );

        return $promise;
    }

    /** @return array{hits: int, misses: int, coalesced: int, producer_failures: int, write_failures: int, in_flight: int} */
    public function metrics(): array
    {
        return $this->metrics + ['in_flight' => count($this->inFlight)];
    }
}
