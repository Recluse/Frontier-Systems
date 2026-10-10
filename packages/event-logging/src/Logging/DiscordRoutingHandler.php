<?php

declare(strict_types=1);

namespace Frontier\EventLogging\Logging;

use Frontier\EventLogging\Discord\ChannelSenderInterface;
use Frontier\EventLogging\Event\GameEvent;
use Monolog\Handler\AbstractProcessingHandler;
use Monolog\Level;
use Monolog\LogRecord;
use React\EventLoop\LoopInterface;
use Throwable;

/** Monolog only enqueues; the React loop delivers without recursive error logging. */
final class DiscordRoutingHandler extends AbstractProcessingHandler
{
    /** @var list<array{channel: string, content: string, route: array, attempt: int}> */
    private array $queue = [];
    private bool $busy = false;
    private bool $stalled = false;
    private bool $closed = false;
    private int $queuedBytes = 0;
    private int $delivered = 0;
    private int $failed = 0;
    private int $dropped = 0;
    private int $invalid = 0;
    private int $unrouted = 0;

    public function __construct(
        private readonly LoopInterface $loop,
        private readonly ChannelRoutes $routes,
        private readonly ChannelSenderInterface $sender,
        private readonly int $maximumMessages = 256,
        private readonly int $maximumBytes = 524288,
        private readonly float $deliveryTimeoutSeconds = 30.0,
    ) {
        parent::__construct(Level::Debug, false); // Consume typed events before unclassified legacy handlers can export them.
        if ($maximumMessages < 1 || $maximumMessages > 1024 || $maximumBytes < 1024 || $maximumBytes > 2097152) {
            throw new \InvalidArgumentException('Event delivery queue bounds are invalid.');
        }
        if (!is_finite($deliveryTimeoutSeconds) || $deliveryTimeoutSeconds < 0.01 || $deliveryTimeoutSeconds > 30.0) {
            throw new \InvalidArgumentException('Event delivery deadline is invalid.');
        }
    }

    public function isHandling(LogRecord $record): bool
    {
        return isset($record->context['frontier_event']); // Never forward DiscordPHP HTTP/debug logs implicitly.
    }

    protected function write(LogRecord $record): void
    {
        if ($this->closed) {
            ++$this->dropped;
            return;
        }
        $event = $record->context['frontier_event'];
        if (!$event instanceof GameEvent) {
            ++$this->invalid;
            return;
        }
        $json = $event->json();
        $chunks = [];
        while ($json !== '') {
            $length = min(1300, strlen($json));
            while (preg_match('//u', substr($json, 0, $length)) !== 1) {
                --$length;
            }
            $chunks[] = substr($json, 0, $length);
            $json = substr($json, $length);
        }
        $pending = [];
        $bytes = 0;
        foreach ($this->routes->destinations($event) as $channel => $route) {
            foreach ($chunks as $index => $chunk) {
                $id = str_replace(["\r", "\n"], ['\\r', '\\n'], $event->record['event_id']);
                $content = sprintf('[event %s %d/%d] %s', $id, $index + 1, count($chunks), $chunk);
                $pending[] = ['channel' => (string) $channel, 'content' => $content, 'route' => $route, 'attempt' => 0];
                $bytes += strlen($content);
            }
        }
        if ($pending === []) {
            ++$this->unrouted;
            return;
        }
        if (count($this->queue) + count($pending) + ($this->busy ? 1 : 0) > $this->maximumMessages
            || $this->queuedBytes + $bytes > $this->maximumBytes) {
            ++$this->dropped;
            return; // Reject the whole fanout, never only its private/public half.
        }
        array_push($this->queue, ...$pending);
        $this->queuedBytes += $bytes;
    }

    /** Run from the bot's periodic timer. Logging itself never dispatches network work. */
    public function pump(): void
    {
        if ($this->closed || $this->stalled || $this->busy || $this->queue === []) {
            return;
        }
        $item = array_shift($this->queue);
        $this->busy = true;
        ++$item['attempt'];
        $settled = false;
        $timer = null;
        $finish = function (bool $success) use (&$settled, &$timer, $item): void {
            if ($settled) {
                return;
            }
            $settled = true;
            if ($timer !== null) {
                $this->loop->cancelTimer($timer);
            }
            $this->busy = false;
            if ($success) {
                ++$this->delivered;
                $this->queuedBytes -= strlen($item['content']);
            } elseif ($item['attempt'] < 3) {
                // Bounded retry; one serial pump means no per-channel unbounded promises.
                array_unshift($this->queue, $item);
            } else {
                ++$this->failed;
                $this->queuedBytes -= strlen($item['content']);
            }
        };
        $timer = $this->loop->addTimer($this->deliveryTimeoutSeconds, function () use ($finish): void {
            // An uncertain Discord request must not spawn an unbounded chain of new requests.
            $this->stalled = true;
            $finish(false);
        });
        try {
            $promise = $this->sender->send($item['channel'], $item['content'], $item['route']);
            $promise->then(static fn () => $finish(true), static fn () => $finish(false));
        } catch (Throwable) {
            $finish(false);
        }
    }

    /** @return array<string, int|bool> */
    public function counters(): array
    {
        return ['queued' => count($this->queue), 'queued_bytes' => $this->queuedBytes, 'in_flight' => $this->busy, 'stalled' => $this->stalled,
            'delivered' => $this->delivered, 'failed' => $this->failed, 'dropped' => $this->dropped, 'invalid' => $this->invalid, 'unrouted' => $this->unrouted, 'closed' => $this->closed];
    }

    public function close(): void
    {
        $this->closed = true;
    }
}
