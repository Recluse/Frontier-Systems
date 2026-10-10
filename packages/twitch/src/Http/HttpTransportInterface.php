<?php

declare(strict_types=1);

namespace Frontier\Twitch\Http;

use Psr\Http\Message\ResponseInterface;
use React\Promise\PromiseInterface;

/** Bounded asynchronous transport; implementations must not log authorization headers. */
interface HttpTransportInterface
{
    /**
     * @param array<string, string> $headers
     * @return PromiseInterface<ResponseInterface>
     */
    public function postChatMessage(array $headers, string $json): PromiseInterface;
}
