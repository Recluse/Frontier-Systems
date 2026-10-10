<?php

declare(strict_types=1);

namespace Frontier\Profiling\Ingestion;

use Frontier\Profiling\Capture\ProfileCaptureDocument;
use Frontier\Profiling\Persistence\ProfileCaptureRepositoryInterface;
use Frontier\Profiling\Persistence\StoredProfileCapture;
use Frontier\WorldContracts\World\WorldIdentity;
use InvalidArgumentException;
use React\Promise\PromiseInterface;
use Throwable;

use function React\Promise\reject;

/** Server-owned scope binding; request payloads cannot select their authorized identity. */
final readonly class ProfileCaptureIngestor
{
    public function __construct(private ProfileCaptureRepositoryInterface $repository)
    {
    }

    /**
     * The transport must authenticate the host and derive this scope before calling.
     * Validation is bounded CPU work; transport buffering/rate limits remain mandatory.
     *
     * @return PromiseInterface<StoredProfileCapture>
     */
    public function ingest(WorldIdentity $authenticatedScope, string $json): PromiseInterface
    {
        try {
            $capture = ProfileCaptureDocument::fromJson($json);
            if ($capture->identity->worldId !== $authenticatedScope->worldId || $capture->identity->regionId !== $authenticatedScope->regionId) {
                throw new InvalidArgumentException('Profiling capture does not match the authenticated host scope.');
            }

            return $this->repository->store($capture);
        } catch (Throwable $exception) {
            return reject($exception);
        }
    }
}
