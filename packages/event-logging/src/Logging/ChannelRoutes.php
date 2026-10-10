<?php

declare(strict_types=1);

namespace Frontier\EventLogging\Logging;

use Frontier\EventLogging\Event\GameEvent;
use InvalidArgumentException;

/** Operator-owned destinations; private routes never fall back to public. */
final readonly class ChannelRoutes
{
    /** @param array<string, array{audience: string, scope_id: string, kinds: list<string>}> $channels */
    public function __construct(private array $channels)
    {
        if (count($channels) > 16) {
            throw new InvalidArgumentException('Too many event destinations.');
        }
        foreach ($channels as $id => $route) {
            if (preg_match('/\A[0-9]{1,20}\z/', (string) $id) !== 1
                || !in_array($route['audience'] ?? null, ['public', 'staff', 'private'], true)
                || !is_string($route['scope_id'] ?? null) || strlen($route['scope_id']) > 128
                || (($route['audience'] === 'private') !== ($route['scope_id'] !== ''))
                || !is_array($route['kinds'] ?? null) || count($route['kinds']) > 64) {
                throw new InvalidArgumentException('Invalid event channel route.');
            }
            foreach ($route['kinds'] as $kind) {
                if (!is_string($kind) || $kind === '' || strlen($kind) > 128) {
                    throw new InvalidArgumentException('Invalid route event kind.');
                }
            }
        }
    }

    /** @return array<string, array{audience: string, scope_id: string, kinds: list<string>}> */
    public function destinations(GameEvent $event): array
    {
        $record = $event->record;
        return array_filter($this->channels, static function (array $route) use ($record): bool {
            if (!in_array('*', $route['kinds'], true) && !in_array($record['kind'], $route['kinds'], true)) {
                return false;
            }
            return match ($route['audience']) {
                'public' => $record['audience'] === 'public',
                'staff' => true,
                'private' => $record['audience'] === 'private' && $record['scope_id'] === $route['scope_id'],
            };
        });
    }
}
