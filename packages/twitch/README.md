# Frontier Systems Twitch package

First-party MIT PHP 8.3+ library, namespace `Frontier\Twitch\`, PSR-4 and strict types. It is optional and not yet wired into control-plane startup. See the [integration plan](../../docs/design/twitch-streamer-integration.md).

`Chat\ChatSenderInterface` returns ReactPHP promises. `Chat\HelixChatSender` binds one bot sender/broadcaster and uses an **app token**, with explicit source-only shared-chat delivery. Application/bot/broadcaster grants must already be validated by the service. This package does not obtain/refresh credentials.

`Http\ReactHttpTransport` wraps an injected `React\Http\Browser`, targeting the fixed Twitch HTTPS chat endpoint with redirects off, a ten-second timeout and 64 KiB response limit. `HttpTransportInterface` enables offline mocks. Sending rejects invalid UTF-8/control text and more than 500 code points, and permits one request in flight. There is no unbounded queue, automatic retry or rate scheduler.

Results include `message_id`, `is_sent` and optional `drop_reason`. Callers must check `is_sent`; a dropped message is not successful delivery. `TwitchRequestFailed` exposes HTTP status and delivery uncertainty without retaining raw error bodies or credential-bearing transport exceptions. Unknown delivery must not be blindly resent.

```php
$sender = new \Frontier\Twitch\Chat\HelixChatSender(
    new \Frontier\Twitch\Http\ReactHttpTransport(new \React\Http\Browser()),
    $configuredClientId,
    $validatedAppToken,
    $configuredBotUserId,
    $authorizedBroadcasterId,
);
// Only invoke after the channel operator enables this feature and authorizes delivery.
$sender->sendMessage($approvedPublicStatus)->then(
    function (array $result): void { /* Inspect is_sent; record a bounded outcome. */ },
    function (\Throwable $error): void { /* Handle sanitized failure, no simulation mutation. */ },
);
```

Token-bearing adapter instances must never be serialized into caches/world data or logged through reflection. Debug dumps omit credentials. Twitch is external platform infrastructure; no SDK or creative assets are bundled.

Package installation: `composer install`, then `composer unit`. For development using existing workspace dependencies, run `C:\php\php.exe services/control-plane/vendor/phpunit/phpunit/phpunit --bootstrap packages/twitch/tests/bootstrap.php packages/twitch/tests` from the repository root. The test-only bootstrap supports both locations; production uses normal Composer PSR-4 autoloading.

Incoming EventSub, OAuth, panel frontend/EBS, viewer gameplay and service wiring are pending. This package performs no platform actions until explicitly configured and invoked. No live account connection was tested.

Public status schemas/caching are now supplied by `frontier-systems/server-status`; `Status\ChannelStatusProvider` adds bounded operator-approved channel mappings and rejects late results after unlink/rebind. Live host publication and panel UI remain pending. See [the status contract](../../docs/architecture/public-server-status.md), including the preferred TwitchPHP/HTTP providers and their PHP-version/retry boundaries.
