<?php

declare(strict_types=1);

namespace Frontier\EventLogging\Discord;

use React\Promise\PromiseInterface;

interface ChannelSenderInterface
{
    /**
     * @param array{audience: string, scope_id: string, kinds: list<string>} $route
     * @return PromiseInterface<mixed>
     */
    public function send(string $channelId, string $content, array $route): PromiseInterface;
}
