<?php

declare(strict_types=1);

namespace Frontier\Twitch\Tests\Fixtures;

use Frontier\ServerStatus\PublicServerStatus;
use Frontier\ServerStatus\PublicStatusRepositoryInterface;
use Frontier\WorldContracts\World\WorldIdentity;
use React\Promise\Deferred;
use React\Promise\PromiseInterface;

use function React\Promise\resolve;

final class DeferredStatusRepository implements PublicStatusRepositoryInterface
{
    public Deferred $pending;

    public function __construct()
    {
        $this->pending = new Deferred();
    }

    public function store(PublicServerStatus $status, int $nowUnix): PromiseInterface
    {
        return resolve($status);
    }

    public function publicView(WorldIdentity $identity, int $nowUnix): PromiseInterface
    {
        return $this->pending->promise();
    }
}
