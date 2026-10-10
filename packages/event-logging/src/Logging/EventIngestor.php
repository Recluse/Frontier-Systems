<?php

declare(strict_types=1);

namespace Frontier\EventLogging\Logging;

use Frontier\EventLogging\Event\EventPolicy;
use Frontier\EventLogging\Event\EventIdConflict;
use Frontier\EventLogging\Event\GameEvent;
use Frontier\WorldContracts\World\WorldIdentity;
use Psr\Log\LoggerInterface;

/** Uses the supplied shared logger; deduplication is bounded and memory-only. */
final class EventIngestor
{
    /** @var array<string, string> */
    private array $seen = [];

    public function __construct(private readonly LoggerInterface $logger, private readonly EventPolicy $policy)
    {
    }

    /** @return bool True for newly recorded events, false for retained retries. */
    public function ingest(WorldIdentity $scope, string $json): bool
    {
        $event = GameEvent::decode($json, $scope, $this->policy);
        $key = hash('sha256', json_encode([$scope->worldId, $scope->regionId, $event->record['event_id']], JSON_THROW_ON_ERROR));
        $fingerprint = hash('sha256', $event->json());
        if (isset($this->seen[$key])) {
            if ($this->seen[$key] !== $fingerprint) {
                throw new EventIdConflict('Retained event ID identifies changed content.');
            }
            return false;
        }
        $this->logger->info($event->record['kind'], ['frontier_event' => $event]);
        $this->seen[$key] = $fingerprint;
        if (count($this->seen) > 1024) {
            array_shift($this->seen);
        }
        return true;
    }
}
