<?php

declare(strict_types=1);

namespace Frontier\EventLogging\Discord;

use Discord\Discord;
use Frontier\EventLogging\Event\EventPolicy;
use Frontier\EventLogging\Logging\ChannelRoutes;
use Frontier\EventLogging\Logging\DiscordRoutingHandler;
use Frontier\EventLogging\Logging\EventIngestor;
use Monolog\Logger;
use React\EventLoop\LoopInterface;
use React\EventLoop\TimerInterface;
use RuntimeException;

/** Attach once to an existing bot; never creates a second logger or gateway client. */
final class DiscordPhpEventBridge
{
    public readonly EventIngestor $ingestor;
    public readonly DiscordRoutingHandler $handler;
    private readonly TimerInterface $timer;
    private readonly Logger $logger;

    /** @param callable(object, array): bool|\React\Promise\PromiseInterface $privacyCheck */
    public function __construct(
        Discord $discord,
        private readonly LoopInterface $loop,
        ChannelRoutes $routes,
        callable $privacyCheck,
        ?EventPolicy $policy = null,
    ) {
        $logger = $discord->getLogger();
        if (!$logger instanceof Logger) {
            throw new RuntimeException('Game event routing requires the bot\'s Monolog 3 logger.');
        }
        foreach ($logger->getHandlers() as $handler) {
            if ($handler instanceof DiscordRoutingHandler) {
                throw new RuntimeException('Attach one game event routing handler to the shared logger.');
            }
        }
        $this->logger = $logger;
        $this->handler = new DiscordRoutingHandler($loop, $routes, new DiscordPhpChannelSender($discord, $privacyCheck));
        $logger->pushHandler($this->handler);
        $this->ingestor = new EventIngestor($logger, $policy ?? new EventPolicy());
        $this->timer = $loop->addPeriodicTimer(1.0, $this->handler->pump(...));
    }

    public function stop(): void
    {
        $this->loop->cancelTimer($this->timer);
        $this->handler->close(); // Keep the closed classifier attached so shutdown cannot leak typed private records to legacy exporters.
    }
}
