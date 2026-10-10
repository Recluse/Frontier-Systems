<?php

declare(strict_types=1);

namespace Frontier\ServerStatus;

use Frontier\WorldContracts\World\WorldIdentity;
use React\Promise\PromiseInterface;

use function React\Promise\reject;

/** Host identity comes from the service's authenticated session, never from JSON alone. */
final readonly class PublicStatusIngestor
{
    public function __construct(private PublicStatusRepositoryInterface $repository)
    {
    }

    /** @return PromiseInterface<PublicServerStatus> */
    public function ingest(WorldIdentity $authenticatedHost, string $json, int $nowUnix): PromiseInterface
    {
        try {
            $status = PublicServerStatus::fromJson($json);
            if ($status->identity()->worldId !== $authenticatedHost->worldId || $status->identity()->regionId !== $authenticatedHost->regionId) {
                throw new \InvalidArgumentException('Publication does not match the authenticated host scope.');
            }
            return $this->repository->store($status, $nowUnix);
        } catch (\InvalidArgumentException $error) {
            return reject($error);
        }
    }
}
