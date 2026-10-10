<?php

declare(strict_types=1);

namespace Frontier\Profiling\Persistence;

use Frontier\Profiling\Capture\ProfileCaptureDocument;
use Frontier\WorldContracts\World\WorldIdentity;
use InvalidArgumentException;
use OverflowException;
use React\Promise\PromiseInterface;

use function React\Promise\reject;
use function React\Promise\resolve;

/** Bounded latest-per-region development store. No files, subprocesses or blocking I/O. */
final class InMemoryProfileCaptureRepository implements ProfileCaptureRepositoryInterface
{
    /** @var array<string, StoredProfileCapture> Oldest successful store first. */
    private array $captures = [];
    private int $retainedBytes = 0;
    private int $sequence = 0;
    private int $evictions = 0;

    public function __construct(
        private readonly int $maximumCaptures = 16,
        private readonly int $maximumEncodedBytes = 16_777_216,
    ) {
        if ($maximumCaptures < 1 || $maximumCaptures > 128 || $maximumEncodedBytes < 1 || $maximumEncodedBytes > 134_217_728) {
            throw new InvalidArgumentException('Repository limits must be 1–128 captures and at most 128 MiB.');
        }
    }

    /** @return PromiseInterface<StoredProfileCapture|null> */
    public function loadLatest(WorldIdentity $identity): PromiseInterface
    {
        return resolve($this->captures[self::key($identity)] ?? null);
    }

    /** @return PromiseInterface<StoredProfileCapture> */
    public function store(ProfileCaptureDocument $capture): PromiseInterface
    {
        if ($capture->encodedBytes() > $this->maximumEncodedBytes) {
            return reject(new InvalidArgumentException('Capture exceeds repository retention capacity.'));
        }
        $key = self::key($capture->identity);
        $existing = $this->captures[$key] ?? null;
        $fingerprint = $capture->fingerprint();
        if ($existing !== null) {
            if ($capture->captureTickNumber < $existing->document->captureTickNumber) {
                return reject(new InvalidArgumentException('Delayed capture cannot replace a newer frontier.'));
            }
            if ($fingerprint === $existing->fingerprint) {
                return resolve($existing);
            }
        }
        if ($this->sequence === PHP_INT_MAX) {
            return reject(new OverflowException('Repository receipt sequence is exhausted.'));
        }
        $stored = new StoredProfileCapture($capture, ++$this->sequence, $fingerprint);
        if ($existing !== null) {
            $this->retainedBytes -= $existing->document->encodedBytes();
            unset($this->captures[$key]);
        }
        $this->captures[$key] = $stored;
        $this->retainedBytes += $capture->encodedBytes();
        while (count($this->captures) > $this->maximumCaptures || $this->retainedBytes > $this->maximumEncodedBytes) {
            $oldest = array_key_first($this->captures);
            $this->retainedBytes -= $this->captures[$oldest]->document->encodedBytes();
            unset($this->captures[$oldest]);
            ++$this->evictions;
        }

        return resolve($stored);
    }

    /** @return array<string, int> Numeric diagnostics contain no capture content. */
    public function metrics(): array
    {
        return ['retained_captures' => count($this->captures), 'retained_encoded_bytes' => $this->retainedBytes,
            'maximum_captures' => $this->maximumCaptures, 'maximum_encoded_bytes' => $this->maximumEncodedBytes,
            'evictions' => $this->evictions, 'last_sequence' => $this->sequence];
    }

    private static function key(WorldIdentity $identity): string
    {
        return strlen($identity->worldId) . ':' . $identity->worldId . strlen($identity->regionId) . ':' . $identity->regionId;
    }
}
