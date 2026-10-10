<?php

declare(strict_types=1);

namespace Frontier\Twitch\Chat;

use Frontier\Twitch\Http\HttpTransportInterface;
use Psr\Http\Message\ResponseInterface;
use React\Promise\PromiseInterface;

use function React\Promise\reject;

/** App-token bot adapter. OAuth grants/validation and rate scheduling belong to its service. */
final class HelixChatSender implements ChatSenderInterface
{
    private bool $inFlight = false;

    public function __construct(
        private readonly HttpTransportInterface $http,
        private readonly string $clientId,
        #[\SensitiveParameter] private readonly string $appAccessToken,
        private readonly string $senderUserId,
        private readonly string $broadcasterId,
    ) {
        if (preg_match('/\A[A-Za-z0-9_-]{1,128}\z/', $clientId) !== 1
            || preg_match('/\A[A-Za-z0-9._-]{1,512}\z/', $appAccessToken) !== 1
            || preg_match('/\A[1-9][0-9]{0,31}\z/', $senderUserId) !== 1
            || preg_match('/\A[1-9][0-9]{0,31}\z/', $broadcasterId) !== 1) {
            throw new \InvalidArgumentException('Bounded client credentials and numeric Twitch identities are required.');
        }
    }

    /** Secrets are deliberately omitted from ordinary diagnostic dumps. */
    public function __debugInfo(): array
    {
        return ['sender_user_id' => $this->senderUserId, 'broadcaster_id' => $this->broadcasterId, 'in_flight' => $this->inFlight];
    }

    public function sendMessage(string $message): PromiseInterface
    {
        if (preg_match('/\A.{1,500}\z/us', $message) !== 1 || trim($message) === '' || preg_match('/[\x00-\x1F\x7F]/', $message) === 1) {
            return reject(new \InvalidArgumentException('Chat text must contain 1..500 UTF-8 code points without control characters.'));
        }
        if ($this->inFlight) {
            return reject(new \RuntimeException('One chat request is already in flight; scheduling must remain bounded.'));
        }
        $this->inFlight = true;
        try {
            $pending = $this->http->postChatMessage([
                'Client-Id' => $this->clientId,
                'Authorization' => 'Bearer ' . $this->appAccessToken,
                'Content-Type' => 'application/json',
            ], json_encode([
                'sender_id' => $this->senderUserId,
                'broadcaster_id' => $this->broadcasterId,
                'message' => $message,
                'for_source_only' => true,
            ], JSON_THROW_ON_ERROR));
        } catch (\Throwable) {
            $this->inFlight = false;
            return reject(new TwitchRequestFailed(0, true));
        }

        return $pending->then(
            static function (ResponseInterface $response): array {
                $status = $response->getStatusCode();
                if ($status !== 200) {
                    throw new TwitchRequestFailed($status, $status >= 500 || ($status >= 200 && $status < 300));
                }
                $body = (string) $response->getBody();
                if (strlen($body) > 65536) {
                    throw new TwitchRequestFailed($status, true);
                }
                try {
                    $record = json_decode($body, true, 16, JSON_THROW_ON_ERROR);
                } catch (\JsonException) {
                    throw new TwitchRequestFailed($status, true);
                }
                $data = is_array($record) ? ($record['data'] ?? null) : null;
                if (!is_array($data) || !array_is_list($data) || count($data) !== 1 || !is_array($data[0])) {
                    throw new TwitchRequestFailed($status, true);
                }
                $entry = $data[0];
                if (!is_bool($entry['is_sent'] ?? null) || !is_string($entry['message_id'] ?? null)
                    || strlen($entry['message_id']) > 128 || ($entry['is_sent'] && $entry['message_id'] === '')
                    || (isset($entry['drop_reason']) && (!is_array($entry['drop_reason'])
                        || !is_string($entry['drop_reason']['code'] ?? null) || !is_string($entry['drop_reason']['message'] ?? null)))) {
                    throw new TwitchRequestFailed($status, true);
                }
                return ['message_id' => $entry['message_id'], 'is_sent' => $entry['is_sent'], 'drop_reason' => $entry['drop_reason'] ?? null];
            },
            static function (): never {
                throw new TwitchRequestFailed(0, true);
            },
        )->finally(function (): void {
            $this->inFlight = false;
        });
    }
}
