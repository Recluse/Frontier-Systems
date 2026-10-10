<?php

declare(strict_types=1);

namespace Frontier\ProfilingHttp\Body;

use Frontier\Profiling\Capture\ProfileCaptureDocument;
use InvalidArgumentException;
use React\EventLoop\LoopInterface;
use React\Promise\Deferred;
use React\Promise\PromiseInterface;
use React\Stream\ReadableStreamInterface;

use function React\Promise\reject;

/** Streaming-only reader: memory bound checked before concatenating each chunk. */
final readonly class BoundedBodyReader
{
    public function __construct(private LoopInterface $loop, private int $maximumBytes, private float $timeoutSeconds)
    {
        if ($maximumBytes < 1 || $maximumBytes > ProfileCaptureDocument::MAX_ENCODED_BYTES
            || !is_finite($timeoutSeconds) || $timeoutSeconds <= 0.0 || $timeoutSeconds > 30.0) {
            throw new InvalidArgumentException('Reader size/deadline settings are outside supported bounds.');
        }
    }

    /** @return PromiseInterface<string> */
    public function read(ReadableStreamInterface $body, ?int $expectedBytes): PromiseInterface
    {
        if (!$body->isReadable()) {
            return reject(new UploadBodyFailure(400, 'body_unavailable'));
        }
        $deferred = new Deferred();
        $settled = false;
        $buffer = '';
        $listeners = [];
        $timer = null;
        $finish = function (?UploadBodyFailure $failure) use ($body, $deferred, &$settled, &$buffer, &$listeners, &$timer): void {
            if ($settled) {
                return;
            }
            $settled = true;
            if ($timer !== null) {
                $this->loop->cancelTimer($timer);
                $timer = null;
            }
            foreach ($listeners as $event => $listener) {
                $body->removeListener($event, $listener);
            }
            $listeners = [];
            if ($failure !== null) {
                $buffer = '';
                $body->pause();
                $deferred->reject($failure);
            } else {
                $deferred->resolve($buffer);
                $buffer = '';
            }
        };
        $listeners['data'] = function ($chunk) use (&$buffer, $finish): void {
            if (!is_string($chunk) || strlen($chunk) > $this->maximumBytes - strlen($buffer)) {
                $finish(new UploadBodyFailure(413, 'capture_too_large'));
                return;
            }
            $buffer .= $chunk;
        };
        $listeners['end'] = function () use (&$buffer, $expectedBytes, $finish): void {
            $finish($expectedBytes !== null && strlen($buffer) !== $expectedBytes
                ? new UploadBodyFailure(400, 'content_length_mismatch') : null);
        };
        $listeners['error'] = static function () use ($finish): void {
            $finish(new UploadBodyFailure(400, 'body_stream_error'));
        };
        $listeners['close'] = static function () use ($finish): void {
            $finish(new UploadBodyFailure(400, 'body_closed_early'));
        };
        foreach ($listeners as $event => $listener) {
            $body->on($event, $listener);
        }
        $timer = $this->loop->addTimer($this->timeoutSeconds, static function () use ($finish): void {
            $finish(new UploadBodyFailure(408, 'body_timeout'));
        });
        $body->resume();

        return $deferred->promise();
    }
}
