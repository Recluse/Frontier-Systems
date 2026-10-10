<?php

declare(strict_types=1);

namespace Frontier\ProfilingHttp\Authentication;

use Frontier\WorldContracts\World\WorldIdentity;
use Psr\Http\Message\ServerRequestInterface;
use React\Promise\PromiseInterface;

/** Authenticate upload authority and derive the region from server-owned host state. */
interface HostAuthenticatorInterface
{
    /**
     * Never derive scope from JSON or client world/region headers. No blocking I/O.
     * Reject HostAuthenticationFailed for denied credentials; other errors are outages.
     *
     * @return PromiseInterface<WorldIdentity>
     */
    public function authenticateUpload(ServerRequestInterface $request): PromiseInterface;
}
