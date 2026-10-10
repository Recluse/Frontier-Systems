<?php

declare(strict_types=1);

namespace Frontier\EventLogging\Http;

use Frontier\EventLogging\Logging\EventIngestor;
use Frontier\ProfilingHttp\Authentication\HostAuthenticatorInterface;
use Frontier\ProfilingHttp\Body\BoundedBodyReader;
use Frontier\ProfilingHttp\Body\UploadBodyFailure;
use Frontier\WorldContracts\World\WorldIdentity;
use Psr\Http\Message\ServerRequestInterface;
use React\EventLoop\LoopInterface;
use React\Http\Message\Response;
use React\Promise\PromiseInterface;
use React\Stream\ReadableStreamInterface;
use Throwable;

use function React\Promise\resolve;

/** Authenticated streaming ingestion. Discord delivery is separate from the HTTP acknowledgement. */
final class EventHttpHandler
{
    public const PATH = '/v1/events';
    private int $active = 0;

    public function __construct(
        private readonly LoopInterface $loop,
        private readonly HostAuthenticatorInterface $authenticator,
        private readonly EventIngestor $ingestor,
    ) {
    }

    /** @return PromiseInterface<Response> */
    public function __invoke(ServerRequestInterface $request): PromiseInterface
    {
        $body = $request->getBody();
        if ($body instanceof ReadableStreamInterface) {
            $body->pause();
        }
        if ($request->getUri()->getPath() !== self::PATH || $request->getUri()->getQuery() !== '') {
            return resolve(new Response(404));
        }
        if ($request->getMethod() !== 'POST' || strtolower($request->getHeaderLine('Content-Type')) !== 'application/json'
            || !in_array(strtolower($request->getHeaderLine('Content-Encoding')), ['', 'identity'], true)) {
            return resolve(new Response(415));
        }
        $length = $request->getHeaderLine('Content-Length');
        if ($length !== '' && (preg_match('/\A[0-9]{1,6}\z/', $length) !== 1 || (int) $length > 16384)) {
            return resolve(new Response(413));
        }
        if (!$body instanceof ReadableStreamInterface || $this->active >= 2) {
            return resolve(new Response(429, ['Retry-After' => '1']));
        }
        ++$this->active;
        return $this->authenticator->authenticateUpload($request)->then(
            function (WorldIdentity $scope) use ($body, $length): PromiseInterface {
                return (new BoundedBodyReader($this->loop, 16384, 5.0))->read($body, $length === '' ? null : (int) $length)->then(
                    function (string $json) use ($scope): Response {
                        $created = $this->ingestor->ingest($scope, $json);
                        return new Response(202, ['Content-Type' => 'application/json'], json_encode(['accepted' => true, 'duplicate' => !$created], JSON_THROW_ON_ERROR));
                    }
                );
            }
        )->then(null, static function (Throwable $error): Response {
            $status = $error instanceof UploadBodyFailure ? $error->status : 503;
            if ($error instanceof \InvalidArgumentException || $error instanceof \JsonException) {
                $status = 400;
            }
            if ($error instanceof \Frontier\EventLogging\Event\EventIdConflict) {
                $status = 409;
            }
            if ($error instanceof \Frontier\ProfilingHttp\Authentication\HostAuthenticationFailed) {
                $status = 401;
            }
            return new Response($status, ['Content-Type' => 'application/json'], '{"accepted":false}');
        })->finally(function (): void {
            --$this->active;
        });
    }
}
