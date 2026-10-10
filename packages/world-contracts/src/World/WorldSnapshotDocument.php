<?php

declare(strict_types=1);

namespace Frontier\WorldContracts\World;

use InvalidArgumentException;
use JsonException;
use stdClass;

/** Immutable, validated JSON snapshot envelope shared with the Godot runtime. */
final readonly class WorldSnapshotDocument
{
    public const SCHEMA_VERSION = 1;
    public const MAX_ENCODED_BYTES = 8_388_608;

    private function __construct(
        public string $worldId,
        public string $regionId,
        public int $tickNumber,
        private string $json,
    ) {
    }

    public static function fromJson(string $json): self
    {
        if (strlen($json) > self::MAX_ENCODED_BYTES) {
            throw new InvalidArgumentException('World snapshot exceeds the encoded size limit.');
        }

        try {
            $record = json_decode($json, false, 64, JSON_THROW_ON_ERROR);
        } catch (JsonException $exception) {
            throw new InvalidArgumentException('World snapshot is not valid JSON.', previous: $exception);
        }

        if (!$record instanceof stdClass) {
            throw new InvalidArgumentException('World snapshot JSON must have an object at its root.');
        }
        $properties = get_object_vars($record);
        $required = ['schema_version', 'world_id', 'region_id', 'tick_number', 'systems'];
        if (array_diff($required, array_keys($properties)) !== [] || array_diff(array_keys($properties), $required) !== []) {
            throw new InvalidArgumentException('World snapshot must contain exactly the versioned envelope properties.');
        }
        if ($record->schema_version !== self::SCHEMA_VERSION) {
            throw new InvalidArgumentException('World snapshot schema version is not supported.');
        }
        if (!self::isIdentifier($record->world_id) || !self::isIdentifier($record->region_id)) {
            throw new InvalidArgumentException('World and region IDs must be non-empty strings.');
        }
        if (!is_int($record->tick_number) || $record->tick_number < 0) {
            throw new InvalidArgumentException('World snapshot tick number must be a non-negative integer.');
        }
        if (!$record->systems instanceof stdClass || get_object_vars($record->systems) === []) {
            throw new InvalidArgumentException('World snapshot must contain at least one system record.');
        }
        foreach (get_object_vars($record->systems) as $systemId => $systemRecord) {
            if ($systemId === '' || !$systemRecord instanceof stdClass || !isset($systemRecord->schema_version) || !is_int($systemRecord->schema_version) || $systemRecord->schema_version < 1) {
                throw new InvalidArgumentException('Every system snapshot requires a stable ID and positive schema version.');
            }
        }

        return new self($record->world_id, $record->region_id, $record->tick_number, $json);
    }

    public function toJson(): string
    {
        return $this->json;
    }

    public function identity(): WorldIdentity
    {
        return new WorldIdentity($this->worldId, $this->regionId);
    }

    private static function isIdentifier(mixed $value): bool
    {
        return is_string($value) && trim($value) !== '' && strlen($value) <= 128;
    }
}
