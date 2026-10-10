<?php

declare(strict_types=1);

namespace Frontier\Twitch\Chat;

/** Sanitized failure; no token, raw response or transport exception is retained. */
final class TwitchRequestFailed extends \RuntimeException
{
    public function __construct(public readonly int $httpStatus, public readonly bool $deliveryUnknown = false)
    {
        parent::__construct($deliveryUnknown ? 'Twitch delivery outcome is unknown; do not blindly retry.' : 'Twitch rejected the request or returned an invalid response.');
    }
}
