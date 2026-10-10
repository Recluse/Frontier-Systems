<?php

declare(strict_types=1);

namespace Frontier\ServerStatus;

use Frontier\WorldContracts\World\WorldIdentity;
use InvalidArgumentException;

/** Explicitly public observations; immutable normalized bytes avoid cached mutable state. */
final readonly class PublicServerStatus
{
    public const MAX_BYTES = 4096;
    public const MAX_INTEGER = 9_007_199_254_740_990;

    private function __construct(private WorldIdentity $identity, private string $json)
    {
    }

    public static function fromJson(string $json): self
    {
        if (strlen($json) > self::MAX_BYTES) {
            throw new InvalidArgumentException('Public status exceeds its byte limit.');
        }
        try {
            $record = json_decode($json, true, 16, JSON_THROW_ON_ERROR);
        } catch (\JsonException) {
            throw new InvalidArgumentException('Public status must contain valid bounded JSON.');
        }
        $fields = ['schema_version', 'world_id', 'region_id', 'tick_number', 'public_name', 'online', 'players_online', 'player_capacity', 'observed_at_unix'];
        if (!is_array($record) || count($record) !== count($fields) || array_diff($fields, array_keys($record)) !== []) {
            throw new InvalidArgumentException('Public status must match the exact v1 fields.');
        }
        if ($record['schema_version'] !== 1 || !is_string($record['world_id']) || !is_string($record['region_id'])
            || !is_string($record['public_name']) || preg_match('/\A.{1,128}\z/us', $record['public_name']) !== 1
            || trim($record['public_name']) === '' || preg_match('/[\x00-\x1F\x7F]/', $record['public_name']) === 1 || !is_bool($record['online'])) {
            throw new InvalidArgumentException('Public status identity, name, version or online flag is invalid.');
        }
        foreach (['tick_number' => self::MAX_INTEGER, 'players_online' => 65536, 'player_capacity' => 65536, 'observed_at_unix' => self::MAX_INTEGER] as $field => $maximum) {
            if (!is_int($record[$field]) || $record[$field] < 0 || $record[$field] > $maximum) {
                throw new InvalidArgumentException('Public status counters must be bounded integers.');
            }
        }
        if ($record['players_online'] > $record['player_capacity'] || (!$record['online'] && $record['players_online'] !== 0)) {
            throw new InvalidArgumentException('Player counts contradict capacity or offline status.');
        }
        $identity = new WorldIdentity($record['world_id'], $record['region_id']);
        // Rebuild in canonical order for retry comparison rather than preserving input key order.
        $normalized = [];
        foreach ($fields as $field) {
            $normalized[$field] = $record[$field];
        }
        return new self($identity, json_encode($normalized, JSON_THROW_ON_ERROR));
    }

    public function identity(): WorldIdentity
    {
        return $this->identity;
    }

    public function tickNumber(): int
    {
        return $this->record()['tick_number'];
    }

    public function observedAtUnix(): int
    {
        return $this->record()['observed_at_unix'];
    }

    public function encodedBytes(): int
    {
        return strlen($this->json);
    }

    public function fingerprint(): string
    {
        return hash('sha256', $this->json);
    }

    /** @return array<string, int|string|bool> World/region/tick identities never enter the public card. */
    public function publicRecord(): array
    {
        return array_diff_key($this->record(), array_flip(['world_id', 'region_id', 'tick_number']));
    }

    private function record(): array
    {
        return json_decode($this->json, true, 16, JSON_THROW_ON_ERROR);
    }
}
