<?php

declare(strict_types=1);

namespace Frontier\WorldContracts\Commands;

use InvalidArgumentException;

/**
 * Server-internal command binding created only after transport authentication.
 *
 * This object is not a wire DTO. Its principal and session IDs must come from the
 * authenticated server session, never from CommandEnvelope payload data.
 */
final readonly class AuthenticatedCommandRequest
{
    public function __construct(
        public CommandEnvelope $intent,
        public string $principalId,
        public string $sessionId,
    ) {
        if (trim($principalId) === '' || strlen($principalId) > 128) {
            throw new InvalidArgumentException('Authenticated principal ID is required.');
        }
        if (trim($sessionId) === '' || strlen($sessionId) > 128) {
            throw new InvalidArgumentException('Authenticated session ID is required.');
        }
    }
}
