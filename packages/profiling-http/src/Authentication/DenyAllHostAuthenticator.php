<?php

declare(strict_types=1);

namespace Frontier\ProfilingHttp\Authentication;

use Psr\Http\Message\ServerRequestInterface;
use React\Promise\PromiseInterface;

use function React\Promise\reject;

/** Safe unconfigured provider. No credentials or local-host exceptions are inferred. */
final class DenyAllHostAuthenticator implements HostAuthenticatorInterface
{
    public function authenticateUpload(ServerRequestInterface $request): PromiseInterface
    {
        return reject(new HostAuthenticationFailed('No host upload authority is configured.'));
    }
}
