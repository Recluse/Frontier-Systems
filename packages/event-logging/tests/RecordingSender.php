<?php

declare(strict_types=1);

namespace Frontier\EventLogging\Tests;

use Frontier\EventLogging\Discord\ChannelSenderInterface;
use React\Promise\Deferred;
use React\Promise\PromiseInterface;

final class RecordingSender implements ChannelSenderInterface
{
    public array $calls = [];
    public Deferred $pending;
    public function send(string $channelId, string $content, array $route): PromiseInterface
    {
        $this->calls[] = ['channel' => $channelId,'content' => $content,'route' => $route];
        $this->pending = new Deferred();
        return $this->pending->promise();
    }
}
