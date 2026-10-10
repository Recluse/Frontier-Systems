<?php

declare(strict_types=1);

namespace Frontier\ServerStatus;

use Frontier\WorldContracts\World\WorldIdentity;
use React\Promise\PromiseInterface;

use function React\Promise\reject;
use function React\Promise\resolve;

/** Disposable latest-per-region cache; expiry never changes authoritative world state. */
final class InMemoryPublicStatusRepository implements PublicStatusRepositoryInterface
{
    /** @var array<string, PublicServerStatus> Oldest successful publication first. */
    private array $records = [];
    private int $bytes = 0;
    private int $evictions = 0;

    public function __construct(private readonly int $maxRegions = 16, private readonly int $maxBytes = 65536, private readonly int $freshnessSeconds = 30)
    {
        if ($maxRegions < 1 || $maxRegions > 128 || $maxBytes < PublicServerStatus::MAX_BYTES || $maxBytes > 524288 || $freshnessSeconds < 1 || $freshnessSeconds > 300) {
            throw new \InvalidArgumentException('Cache needs bounded regions/bytes and 1..300 second freshness.');
        }
    }

    public function store(PublicServerStatus $status, int $nowUnix): PromiseInterface
    {
        if (!self::validTime($nowUnix) || $status->observedAtUnix() > $nowUnix || $nowUnix - $status->observedAtUnix() >= $this->freshnessSeconds) {
            return reject(new \InvalidArgumentException('Publication timestamp must be current and not future-dated.'));
        }
        $key = self::key($status->identity());
        $existing = $this->records[$key] ?? null;
        if ($existing !== null) {
            if ($status->tickNumber() < $existing->tickNumber() || $status->observedAtUnix() < $existing->observedAtUnix()) {
                return reject(new \InvalidArgumentException('Delayed status cannot replace the retained frontier.'));
            }
            if ($status->fingerprint() === $existing->fingerprint()) {
                return resolve($existing);
            }
            if ($status->tickNumber() === $existing->tickNumber() && $status->observedAtUnix() === $existing->observedAtUnix()) {
                return reject(new \InvalidArgumentException('The same publication frontier cannot identify conflicting status.'));
            }
            $this->bytes -= $existing->encodedBytes();
            unset($this->records[$key]);
        }
        $this->records[$key] = $status;
        $this->bytes += $status->encodedBytes();
        while (count($this->records) > $this->maxRegions || $this->bytes > $this->maxBytes) {
            $first = array_key_first($this->records);
            $this->bytes -= $this->records[$first]->encodedBytes();
            unset($this->records[$first]);
            $this->evictions = min(1_000_000_000, $this->evictions + 1);
        }
        return resolve($status);
    }

    public function publicView(WorldIdentity $identity, int $nowUnix): PromiseInterface
    {
        if (!self::validTime($nowUnix)) {
            return reject(new \InvalidArgumentException('A bounded current timestamp is required.'));
        }
        $status = $this->records[self::key($identity)] ?? null;
        if ($status === null) {
            return resolve(['availability' => 'unavailable', 'effective_online' => false, 'status' => null]);
        }
        $fresh = $nowUnix >= $status->observedAtUnix() && $nowUnix - $status->observedAtUnix() < $this->freshnessSeconds;
        $record = $status->publicRecord();
        return resolve(['availability' => $fresh ? 'fresh' : 'stale', 'effective_online' => $fresh && $record['online'], 'status' => $record]);
    }

    /** Numeric-only, bounded diagnostics. */
    public function metrics(): array
    {
        return ['regions' => count($this->records), 'encoded_bytes' => $this->bytes, 'evictions' => $this->evictions];
    }

    private static function validTime(int $time): bool
    {
        return $time >= 0 && $time <= PublicServerStatus::MAX_INTEGER;
    }

    private static function key(WorldIdentity $identity): string
    {
        return strlen($identity->worldId) . ':' . $identity->worldId . strlen($identity->regionId) . ':' . $identity->regionId;
    }
}
