<?php

declare(strict_types=1);

namespace Frontier\WorldContracts\Commands;

use InvalidArgumentException;
use JsonException;
use stdClass;

/**
 * Untrusted request data received from a game client.
 *
 * The envelope intentionally has no actor field. The transport adapter derives the
 * principal from an authenticated session and binds it to a command only after
 * validating this request.
 */
final readonly class CommandEnvelope
{
    public const PROTOCOL_VERSION = 1;
    public const MAX_ENCODED_BYTES = 65_536;
    public const MAX_EXPECTED_TICK = 9_007_199_254_740_990;

    /** @param array<string, mixed> $payload */
    private function __construct(
        public string $requestId,
        public string $worldId,
        public string $regionId,
        public string $commandType,
        public array $payload,
        public ?int $expectedTickNumber,
    ) {
    }

    /** @param array<string, mixed> $record */
    public static function fromArray(array $record): self
    {
        self::assertAllowedKeys($record);

        if (!self::isIntegerWithin($record['protocol_version'] ?? null, self::PROTOCOL_VERSION, self::PROTOCOL_VERSION)) {
            throw new InvalidArgumentException('Unsupported command protocol version.');
        }

        $requestId = self::requiredIdentifier($record, 'request_id', 128);
        $worldId = self::requiredIdentifier($record, 'world_id', 128);
        $regionId = self::requiredIdentifier($record, 'region_id', 128);
        $commandType = self::requiredIdentifier($record, 'command_type', 64);
        if (preg_match('/^[a-z][a-z0-9_.-]{0,63}$/D', $commandType) !== 1) {
            throw new InvalidArgumentException('Command type must use the registered lowercase identifier format.');
        }

        $expectedTick = $record['expected_tick_number'] ?? null;
        if (array_key_exists('expected_tick_number', $record)) {
            if (!self::isIntegerWithin($expectedTick, 0, self::MAX_EXPECTED_TICK)) {
                throw new InvalidArgumentException('Expected tick number must be a non-negative exact JSON integer within the world tick range.');
            }
            $expectedTick = (int) $expectedTick;
        }

        $payload = $record['payload'] ?? null;
        if (!is_array($payload) || (array_is_list($payload) && $payload !== [])) {
            throw new InvalidArgumentException('Command payload must be a JSON object.');
        }
        if (count($payload) > 128) {
            throw new InvalidArgumentException('Command payload has too many top-level properties.');
        }
        self::assertJsonValue($payload, 0);

        $envelope = new self($requestId, $worldId, $regionId, $commandType, $payload, $expectedTick);
        if (strlen($envelope->toJson()) > self::MAX_ENCODED_BYTES) {
            throw new InvalidArgumentException('Command request exceeds the encoded size limit.');
        }

        return $envelope;
    }

    private static function isIntegerWithin(mixed $value, int $minimum, int $maximum): bool
    {
        if (!is_int($value) && !is_float($value)) {
            return false;
        }

        return is_finite((float) $value) && floor((float) $value) === (float) $value
            && $value >= $minimum && $value <= $maximum;
    }

    public static function fromJson(string $json): self
    {
        if (strlen($json) > self::MAX_ENCODED_BYTES) {
            throw new InvalidArgumentException('Command request exceeds the encoded size limit.');
        }

        try {
            $decoded = json_decode($json, false, 32, JSON_THROW_ON_ERROR);
        } catch (JsonException $exception) {
            throw new InvalidArgumentException('Command request is not valid JSON.', previous: $exception);
        }

        if (!$decoded instanceof stdClass) {
            throw new InvalidArgumentException('Command request JSON must have an object at its root.');
        }

        $record = get_object_vars($decoded);
        $payload = $record['payload'] ?? null;
        if (!$payload instanceof stdClass) {
            throw new InvalidArgumentException('Command payload must be a JSON object.');
        }
        $record['payload'] = self::jsonValueToPhp($payload, 0);

        return self::fromArray($record);
    }

    /** @return array<string, mixed> */
    public function toArray(): array
    {
        $record = [
            'protocol_version' => self::PROTOCOL_VERSION,
            'request_id' => $this->requestId,
            'world_id' => $this->worldId,
            'region_id' => $this->regionId,
            'command_type' => $this->commandType,
        ];
        if ($this->expectedTickNumber !== null) {
            $record['expected_tick_number'] = $this->expectedTickNumber;
        }
        $record['payload'] = $this->payload;

        return $record;
    }

    public function toJson(): string
    {
        $record = $this->toArray();
        $record['payload'] = (object) $this->payload;

        try {
            return json_encode(
                (object) $record,
                JSON_THROW_ON_ERROR | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE | JSON_PRESERVE_ZERO_FRACTION,
                32,
            );
        } catch (JsonException $exception) {
            throw new InvalidArgumentException('Command request could not be encoded.', previous: $exception);
        }
    }

    /** @param array<string, mixed> $record */
    private static function assertAllowedKeys(array $record): void
    {
        $allowed = [
            'protocol_version',
            'request_id',
            'world_id',
            'region_id',
            'command_type',
            'expected_tick_number',
            'payload',
        ];
        if (array_diff(array_keys($record), $allowed) !== []) {
            throw new InvalidArgumentException('Command request contains an unsupported property.');
        }
    }

    /** @param array<string, mixed> $record */
    private static function requiredIdentifier(array $record, string $key, int $maxLength): string
    {
        $value = $record[$key] ?? null;
        if (!is_string($value) || trim($value) === '' || strlen($value) > $maxLength) {
            throw new InvalidArgumentException(sprintf('Command property "%s" must be a non-empty string of at most %d bytes.', $key, $maxLength));
        }

        return $value;
    }

    private static function assertJsonValue(mixed $value, int $depth): void
    {
        if ($depth > 16) {
            throw new InvalidArgumentException('Command payload exceeds the maximum nesting depth.');
        }
        if ($value === null || is_bool($value) || is_int($value) || is_float($value) || is_string($value)) {
            return;
        }
        if (!is_array($value)) {
            throw new InvalidArgumentException('Command payload must contain only JSON-compatible values.');
        }

        foreach ($value as $key => $item) {
            if (!is_string($key) && !is_int($key)) {
                throw new InvalidArgumentException('Command payload contains an unsupported object key.');
            }
            self::assertJsonValue($item, $depth + 1);
        }
    }

    private static function jsonValueToPhp(mixed $value, int $depth): mixed
    {
        if ($depth > 16) {
            throw new InvalidArgumentException('Command payload exceeds the maximum nesting depth.');
        }

        if ($value instanceof stdClass) {
            $values = [];
            foreach (get_object_vars($value) as $key => $item) {
                $values[$key] = self::jsonValueToPhp($item, $depth + 1);
            }

            return $values;
        }
        if (is_array($value)) {
            $values = [];
            foreach ($value as $key => $item) {
                $values[$key] = self::jsonValueToPhp($item, $depth + 1);
            }

            return $values;
        }

        return $value;
    }
}
