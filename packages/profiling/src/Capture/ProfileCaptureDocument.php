<?php

declare(strict_types=1);

namespace Frontier\Profiling\Capture;

use Frontier\Profiling\Validation\ProfileCaptureValidator;
use Frontier\WorldContracts\World\WorldIdentity;
use InvalidArgumentException;
use JsonException;

/** Immutable capture bytes: decoded mutable JSON objects are never retained publicly. */
final readonly class ProfileCaptureDocument
{
    public const MAX_ENCODED_BYTES = 8_388_608;

    private function __construct(
        public WorldIdentity $identity,
        public int $captureTickNumber,
        private string $json,
    ) {
    }

    public static function fromJson(string $json): self
    {
        if (strlen($json) > self::MAX_ENCODED_BYTES) {
            throw new InvalidArgumentException('Profiling capture exceeds the eight MiB encoded limit.');
        }
        try {
            $record = json_decode($json, false, 32, JSON_THROW_ON_ERROR);
            $capture = ProfileCaptureValidator::validate($record);
            $encoded = json_encode($capture, JSON_THROW_ON_ERROR | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
        } catch (JsonException $exception) {
            throw new InvalidArgumentException('Profiling capture JSON is invalid.', previous: $exception);
        }
        if (strlen($encoded) > self::MAX_ENCODED_BYTES) {
            throw new InvalidArgumentException('Normalized profiling capture exceeds the size limit.');
        }

        return new self(new WorldIdentity($capture->world_id, $capture->region_id), (int) $capture->capture_tick_number, $encoded);
    }

    public function toJson(): string
    {
        return $this->json;
    }

    public function encodedBytes(): int
    {
        return strlen($this->json);
    }

    /** Digest of normalized bytes, not a signature or semantic content identity. */
    public function fingerprint(): string
    {
        return hash('sha256', $this->json);
    }
}
