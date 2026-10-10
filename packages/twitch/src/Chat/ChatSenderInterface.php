<?php

declare(strict_types=1);

namespace Frontier\Twitch\Chat;

use React\Promise\PromiseInterface;

/** Optional chat delivery boundary, separate from simulation permissions. */
interface ChatSenderInterface
{
    /** @return PromiseInterface<array{message_id: string, is_sent: bool, drop_reason: ?array}> */
    public function sendMessage(string $message): PromiseInterface;
}
