<?php

declare(strict_types=1);

namespace Frontier\ServerStatus;

use Frontier\WorldContracts\World\WorldIdentity;
use React\Promise\PromiseInterface;

interface PublicStatusRepositoryInterface
{
    /** @return PromiseInterface<PublicServerStatus> */
    public function store(PublicServerStatus $status, int $nowUnix): PromiseInterface;

    /** @return PromiseInterface<array{availability: string, effective_online: bool, status: ?array}> */
    public function publicView(WorldIdentity $identity, int $nowUnix): PromiseInterface;
}
