<?php

declare(strict_types=1);

namespace Frontier\EventLogging\Discord;

use Discord\Builders\MessageBuilder;
use Discord\Discord;
use React\Promise\PromiseInterface;
use RuntimeException;

use function React\Promise\reject;
use function React\Promise\resolve;

/** Uses the bot's async sender. Operators must supply a private-channel ACL verifier. */
final readonly class DiscordPhpChannelSender implements ChannelSenderInterface
{
    private \Closure $privacyCheck;

    /** @param callable(object, array): bool|PromiseInterface $privacyCheck Verify audience access against actual Discord permissions. */
    public function __construct(private Discord $discord, callable $privacyCheck)
    {
        $this->privacyCheck = \Closure::fromCallable($privacyCheck);
    }

    public function send(string $channelId, string $content, array $route): PromiseInterface
    {
        $channel = $this->discord->getChannel($channelId);
        if ($channel === null) {
            return reject(new RuntimeException('Event destination is not available in the bot cache.'));
        }
        return resolve(($this->privacyCheck)($channel, $route))->then(static function (mixed $allowed) use ($channel, $content): PromiseInterface {
            if ($allowed !== true) {
                throw new RuntimeException('Event destination audience access was not verified.');
            }
            return $channel->sendMessage(MessageBuilder::new()->setContent($content)->setAllowedMentions(['parse' => [], 'replied_user' => false]));
        });
    }
}
