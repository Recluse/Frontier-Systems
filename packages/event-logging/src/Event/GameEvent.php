<?php

declare(strict_types=1);

namespace Frontier\EventLogging\Event;

use Frontier\Profiling\Validation\RecordGuard;
use Frontier\WorldContracts\World\WorldIdentity;
use InvalidArgumentException;

/** Validated telemetry document; it cannot authorize world changes. */
final readonly class GameEvent
{
    /** @param array<string, mixed> $record */
    private function __construct(public array $record)
    {
    }

    public static function decode(string $json, WorldIdentity $scope, EventPolicy $policy): self
    {
        if (strlen($json) > 16384) {
            throw new InvalidArgumentException('Event exceeds its encoded bound.');
        }
        $doc = RecordGuard::object(json_decode($json, false, 8, JSON_THROW_ON_ERROR), [
            'schema_version', 'event_id', 'world_id', 'region_id', 'tick_number', 'kind', 'audience', 'scope_id', 'data',
        ]);
        RecordGuard::integer($doc->schema_version, 1, 1);
        foreach (['event_id', 'world_id', 'region_id', 'kind'] as $field) {
            RecordGuard::identifier($doc->{$field});
        }
        if ($doc->world_id !== $scope->worldId || $doc->region_id !== $scope->regionId || !is_string($doc->scope_id)
            || strlen($doc->scope_id) > 128 || !is_string($doc->audience) || !($doc->data instanceof \stdClass)) {
            throw new InvalidArgumentException('Event scope or data shape is invalid.');
        }
        RecordGuard::integer($doc->tick_number, 0, 9_007_199_254_740_000);
        $policy->validate($doc->kind, $doc->audience, $doc->scope_id, (array) $doc->data);
        $record = (array) $doc;
        $record['schema_version'] = 1;
        $record['tick_number'] = (int) $record['tick_number'];
        $record['data'] = (array) $doc->data;
        return new self($record);
    }

    public function json(): string
    {
        $record = $this->record;
        ksort($record);
        ksort($record['data']);
        $record['data'] = (object) $record['data'];
        return json_encode($record, JSON_THROW_ON_ERROR | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    }
}
