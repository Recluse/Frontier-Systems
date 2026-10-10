<?php

declare(strict_types=1);

namespace Frontier\Twitch\Http;

use React\Http\Browser;
use React\Promise\PromiseInterface;

/** Fixed Twitch HTTPS destination; no redirects, bounded response buffer and timeout. */
final class ReactHttpTransport implements HttpTransportInterface
{
    private readonly Browser $browser;

    public function __construct(Browser $browser)
    {
        $this->browser = $browser->withTimeout(10.0)
            ->withResponseBuffer(65536)
            ->withFollowRedirects(false)
            ->withRejectErrorResponse(false);
    }

    public function postChatMessage(array $headers, string $json): PromiseInterface
    {
        return $this->browser->post('https://api.twitch.tv/helix/chat/messages', $headers, $json);
    }
}
