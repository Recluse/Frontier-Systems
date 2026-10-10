<?php

declare(strict_types=1);

namespace Frontier\Twitch\Tests\Fixtures;

use Frontier\Twitch\Http\HttpTransportInterface;
use React\Promise\Deferred;
use React\Promise\PromiseInterface;

final class RecordingTwitchTransport implements HttpTransportInterface
{
    public Deferred $deferred;
    public array $headers = [];
    public string $json = '';
    public int $calls = 0;

    public function __construct()
    {
        $this->deferred = new Deferred();
    }

    public function postChatMessage(array $headers, string $json): PromiseInterface
    {
        $this->headers = $headers;
        $this->json = $json;
        $this->calls++;
        return $this->deferred->promise();
    }
}
