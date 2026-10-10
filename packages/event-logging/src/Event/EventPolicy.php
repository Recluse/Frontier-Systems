<?php

declare(strict_types=1);

namespace Frontier\EventLogging\Event;

use InvalidArgumentException;

/** Server-owned event classifications. Unknown kinds and audience downgrades reject. */
final class EventPolicy
{
    /** @var array<string, array{audience: string, fields: list<string>}> */
    private array $types;

    /** @param array<string, array{audience: string, fields: list<string>}> $extensions */
    public function __construct(array $extensions = [])
    {
        $this->types = [
            'game.event' => ['audience' => 'public', 'fields' => ['text']],
            'chat.public' => ['audience' => 'public', 'fields' => ['text', 'speaker']],
            'chat.private' => ['audience' => 'private', 'fields' => ['text', 'speaker']],
            'llm.request' => ['audience' => 'staff', 'fields' => ['text', 'agent']],
            'llm.response' => ['audience' => 'staff', 'fields' => ['text', 'agent']],
            'simulation.command' => ['audience' => 'staff', 'fields' => ['operation', 'success', 'request_id', 'code']],
            'production.batch' => ['audience' => 'public', 'fields' => ['recipe_id']],
            'production.extraction' => ['audience' => 'staff', 'fields' => ['request_id', 'completed_cycles']],
        ];
        foreach ($extensions as $kind => $type) {
            if (isset($this->types[$kind]) || !is_string($kind) || strlen($kind) > 128
                || !in_array($type['audience'] ?? null, ['public', 'staff', 'private'], true)
                || !isset($type['fields']) || !is_array($type['fields']) || count($type['fields']) > 8) {
                throw new InvalidArgumentException('Invalid event classification extension.');
            }
            foreach ($type['fields'] as $field) {
                if (!is_string($field) || preg_match('/\A[a-z][a-z0-9_]{0,63}\z/', $field) !== 1
                    || preg_match('/token|password|secret|credential|authorization/i', $field) === 1) {
                    throw new InvalidArgumentException('Event fields must be explicit non-credential names.');
                }
            }
            $this->types[$kind] = $type;
        }
    }

    /** @param array<string, mixed> $data */
    public function validate(string $kind, string $audience, string $scope, array $data): void
    {
        $type = $this->types[$kind] ?? null;
        if ($type === null || $audience !== $type['audience'] || (($audience === 'private') !== ($scope !== ''))) {
            throw new InvalidArgumentException('Event classification or private scope differs from policy.');
        }
        $actual = array_keys($data);
        $expected = $type['fields'];
        sort($actual);
        sort($expected);
        if ($actual !== $expected) {
            throw new InvalidArgumentException('Event data fields differ from the registered contract.');
        }
        foreach ($data as $value) {
            if ((!is_string($value) && !is_bool($value) && !is_int($value))
                || (is_string($value) && (strlen($value) > 8192 || preg_match('//u', $value) !== 1))) {
                throw new InvalidArgumentException('Event data must contain bounded UTF-8 scalars.');
            }
        }
    }
}
