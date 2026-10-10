<?php

declare(strict_types=1);

namespace Frontier\ProfilingHttp\Http;

use Frontier\Profiling\Capture\ProfileCaptureDocument;
use Frontier\Profiling\Ingestion\ProfileCaptureIngestor;
use Frontier\Profiling\Persistence\StoredProfileCapture;
use Frontier\ProfilingHttp\Authentication\HostAuthenticationFailed;
use Frontier\ProfilingHttp\Authentication\HostAuthenticatorInterface;
use Frontier\ProfilingHttp\Body\BoundedBodyReader;
use Frontier\ProfilingHttp\Body\UploadBodyFailure;
use Frontier\WorldContracts\World\WorldIdentity;
use InvalidArgumentException;
use Psr\Http\Message\ResponseInterface;
use Psr\Http\Message\ServerRequestInterface;
use React\EventLoop\LoopInterface;
use React\Http\Message\Response;
use React\Promise\Deferred;
use React\Promise\PromiseInterface;
use React\Stream\ReadableStreamInterface;
use RuntimeException;
use Throwable;

use function React\Promise\resolve;

/** Dedicated streaming endpoint; excess requests reject rather than queue. */
final class ProfileCaptureHttpHandler
{
    public const PATH = '/v1/profiling/captures';
    private int $active = 0;
    private int $accepted = 0;
    private int $failed = 0;
    private int $overloaded = 0;

    public function __construct(
        private readonly LoopInterface $loop,
        private readonly HostAuthenticatorInterface $authenticator,
        private readonly ProfileCaptureIngestor $ingestor,
        private readonly int $maximumBytes = 1_048_576,
        private readonly int $maximumConcurrent = 2,
        private readonly float $authenticationSeconds = 5.0,
        private readonly float $bodySeconds = 10.0,
    ) {
        if ($maximumBytes < 1 || $maximumBytes > ProfileCaptureDocument::MAX_ENCODED_BYTES || $maximumConcurrent < 1 || $maximumConcurrent > 16) {
            throw new InvalidArgumentException('Upload size or concurrency lies outside supported bounds.');
        }
        foreach ([$authenticationSeconds, $bodySeconds] as $timeout) {
            if (!is_finite($timeout) || $timeout <= 0.0 || $timeout > 30.0) {
                throw new InvalidArgumentException('Upload deadlines must be positive and at most thirty seconds.');
            }
        }
    }

    /** @return PromiseInterface<ResponseInterface> */
    public function __invoke(ServerRequestInterface $request): PromiseInterface
    {
        $body = $request->getBody();
        if ($body instanceof ReadableStreamInterface) {
            $body->pause();
        }
        if ($request->getUri()->getPath() !== self::PATH) {
            return resolve(self::response(404, ['error' => 'not_found']));
        }
        if ($request->getMethod() !== 'POST') {
            return resolve(self::response(405, ['error' => 'method_not_allowed'])->withHeader('Allow', 'POST'));
        }
        if ($request->getUri()->getQuery() !== '') {
            return resolve(self::response(400, ['error' => 'unexpected_query']));
        }
        $mediaType = strtolower(trim(explode(';', $request->getHeaderLine('Content-Type'), 2)[0]));
        $encoding = strtolower(trim($request->getHeaderLine('Content-Encoding')));
        if ($mediaType !== 'application/json' || ($encoding !== '' && $encoding !== 'identity')) {
            return resolve(self::response(415, ['error' => 'unsupported_media_type']));
        }
        $expectedBytes = null;
        if ($request->hasHeader('Content-Length')) {
            $length = $request->getHeaderLine('Content-Length');
            if (preg_match('/^(0|[1-9][0-9]*)$/D', $length) !== 1) {
                return resolve(self::response(400, ['error' => 'invalid_content_length']));
            }
            $maximum = (string) $this->maximumBytes;
            if (strlen($length) > strlen($maximum) || (strlen($length) === strlen($maximum) && strcmp($length, $maximum) > 0)) {
                return resolve(self::response(413, ['error' => 'capture_too_large']));
            }
            $expectedBytes = (int) $length;
        }
        if ($this->active >= $this->maximumConcurrent) {
            ++$this->overloaded;
            return resolve(self::response(429, ['error' => 'upload_capacity'])->withHeader('Retry-After', '1'));
        }
        // Streaming middleware is mandatory; never read arbitrary synchronous PSR streams.
        if (!$body instanceof ReadableStreamInterface) {
            return resolve(self::response(503, ['error' => 'streaming_pipeline_required']));
        }
        ++$this->active;
        $reader = new BoundedBodyReader($this->loop, $this->maximumBytes, $this->bodySeconds);
        return $this->authenticate($request)->then(
            function (WorldIdentity $scope) use ($reader, $body, $expectedBytes): PromiseInterface {
                return $reader->read($body, $expectedBytes)->then(
                    fn (string $json): PromiseInterface => $this->ingestor->ingest($scope, $json),
                );
            },
        )->then(
            function (StoredProfileCapture $stored): ResponseInterface {
                --$this->active;
                ++$this->accepted;
                return self::response(200, ['schema_version' => 1, 'status' => 'stored',
                    'sequence' => $stored->sequence, 'capture_tick_number' => $stored->document->captureTickNumber,
                    'fingerprint' => $stored->fingerprint]);
            },
            function (Throwable $failure): ResponseInterface {
                --$this->active;
                ++$this->failed;
                if ($failure instanceof HostAuthenticationFailed) {
                    return self::response(401, ['error' => 'host_authentication_failed']);
                }
                if ($failure instanceof UploadBodyFailure) {
                    return self::response($failure->status, ['error' => $failure->errorCode]);
                }
                if ($failure instanceof InvalidArgumentException) {
                    return self::response(422, ['error' => 'invalid_capture']);
                }
                return self::response(503, ['error' => 'upload_unavailable']);
            },
        );
    }

    /** @return array<string, int> */
    public function metrics(): array
    {
        return ['active_uploads' => $this->active, 'accepted_uploads' => $this->accepted,
            'failed_uploads' => $this->failed, 'overloaded_uploads' => $this->overloaded];
    }

    /** @return PromiseInterface<WorldIdentity> */
    private function authenticate(ServerRequestInterface $request): PromiseInterface
    {
        $deferred = new Deferred();
        $settled = false;
        $pending = null;
        $timer = null;
        $finish = function (?WorldIdentity $identity, ?Throwable $failure) use ($deferred, &$settled, &$timer): void {
            if ($settled) {
                return;
            }
            $settled = true;
            if ($timer !== null) {
                $this->loop->cancelTimer($timer);
                $timer = null;
            }
            if ($failure !== null) {
                $deferred->reject($failure);
            } else {
                $deferred->resolve($identity);
            }
        };
        $timer = $this->loop->addTimer($this->authenticationSeconds, static function () use ($finish, &$pending): void {
            $finish(null, new RuntimeException('Authentication deadline elapsed.'));
            if ($pending !== null) {
                try {
                    $pending->cancel();
                } catch (Throwable) {
                    // Late provider cancellation cannot override the deadline result.
                }
            }
        });
        try {
            $pending = $this->authenticator->authenticateUpload($request);
            $pending->then(
                static function (mixed $identity) use ($finish): void {
                    $finish(
                        $identity instanceof WorldIdentity ? $identity : null,
                        $identity instanceof WorldIdentity ? null : new RuntimeException('Invalid authentication result.')
                    );
                },
                static function (Throwable $failure) use ($finish): void {
                    $finish(null, $failure instanceof HostAuthenticationFailed ? $failure : new RuntimeException('Authentication provider unavailable.'));
                },
            );
        } catch (Throwable $failure) {
            $finish(null, new RuntimeException('Authentication provider unavailable.', previous: $failure));
        }
        return $deferred->promise();
    }

    /** @param array<string, int|string> $record */
    private static function response(int $status, array $record): ResponseInterface
    {
        $record['schema_version'] = 1;
        return new Response(
            $status,
            ['Content-Type' => 'application/json', 'Cache-Control' => 'no-store', 'Connection' => 'close'],
            json_encode($record, JSON_THROW_ON_ERROR | JSON_UNESCAPED_SLASHES)
        );
    }
}
