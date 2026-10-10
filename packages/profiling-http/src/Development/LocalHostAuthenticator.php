<?php

declare(strict_types=1);

namespace Frontier\ProfilingHttp\Development;

use Frontier\ProfilingHttp\Authentication\HostAuthenticationFailed;
use Frontier\ProfilingHttp\Authentication\HostAuthenticatorInterface;
use Frontier\WorldContracts\World\WorldIdentity;
use InvalidArgumentException;
use Psr\Http\Message\ServerRequestInterface;
use React\Promise\PromiseInterface;

use function React\Promise\reject;
use function React\Promise\resolve;

/** Loopback-only test credential binding; never a production authentication provider. */
final readonly class LocalHostAuthenticator implements HostAuthenticatorInterface
{
    public function __construct(private string $token, private WorldIdentity $scope)
    {
        if (strlen($token) > 4096 || preg_match('/\A[A-Za-z0-9._~+\/-]+={0,2}\z/', $token) !== 1) {
            throw new InvalidArgumentException('A valid local test bearer token is required.');
        }
    }

    public function authenticateUpload(ServerRequestInterface $request): PromiseInterface
    {
        $remote = $request->getServerParams()['REMOTE_ADDR'] ?? null;
        if (!in_array($remote, ['127.0.0.1', '::1'], true)
            || count($request->getHeader('Authorization')) !== 1
            || !hash_equals('Bearer ' . $this->token, $request->getHeaderLine('Authorization'))) {
            return reject(new HostAuthenticationFailed('Local test upload denied.'));
        }

        return resolve($this->scope);
    }
}
