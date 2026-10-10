<?php

declare(strict_types=1);

namespace Frontier\Twitch\Tests;

use Frontier\Twitch\Chat\HelixChatSender;
use Frontier\Twitch\Chat\TwitchRequestFailed;
use Frontier\Twitch\Tests\Fixtures\RecordingTwitchTransport;
use InvalidArgumentException;
use PHPUnit\Framework\TestCase;
use React\Http\Message\Response;
use React\Promise\Deferred;
use RuntimeException;
use Throwable;

final class HelixChatSenderTest extends TestCase
{
    public function testAsyncDeliveryBoundedConcurrencyAndPayload(): void
    {
        $http = new RecordingTwitchTransport();
        $client = new HelixChatSender($http, 'test-client', 'test-token', '123', '456');
        $result = null;
        $client->sendMessage('Server online')->then(static function (array $sent) use (&$result): void {
            $result = $sent;
        });
        self::assertNull($result);
        self::assertSame(true, json_decode($http->json, true)['for_source_only']);
        self::assertSame('Bearer test-token', $http->headers['Authorization']);
        $failure = null;
        $client->sendMessage('Busy')->catch(static function (Throwable $error) use (&$failure): void {
            $failure = $error;
        });
        self::assertInstanceOf(RuntimeException::class, $failure);
        $http->deferred->resolve(Response::json(['data' => [['message_id' => 'message-1', 'is_sent' => true]]]));
        self::assertSame('message-1', $result['message_id']);
        self::assertSame(1, $http->calls);
    }

    public function testInvalidMessageDoesNotReachTransport(): void
    {
        $http = new RecordingTwitchTransport();
        $client = new HelixChatSender($http, 'test-client', 'test-token', '123', '456');
        foreach ([str_repeat('a', 501), "bad\ntext", "\xff", ''] as $message) {
            $failure = null;
            $client->sendMessage($message)->catch(static function (Throwable $error) use (&$failure): void {
                $failure = $error;
            });
            self::assertInstanceOf(InvalidArgumentException::class, $failure);
        }
        self::assertSame(0, $http->calls);
    }

    public function testFailureIsSanitizedAndNeverAutomaticallyRetried(): void
    {
        $http = new RecordingTwitchTransport();
        $client = new HelixChatSender($http, 'test-client', 'test-token', '123', '456');
        $failure = null;
        $client->sendMessage('Status')->catch(static function (Throwable $error) use (&$failure): void {
            $failure = $error;
        });
        $http->deferred->reject(new RuntimeException('secret transport text'));
        self::assertInstanceOf(TwitchRequestFailed::class, $failure);
        self::assertTrue($failure->deliveryUnknown);
        self::assertNull($failure->getPrevious());
        self::assertStringNotContainsString('secret', $failure->getMessage());
        self::assertSame(1, $http->calls);
        self::assertStringNotContainsString('test-token', print_r($client, true));
    }

    public function testDroppedMessageIsNotReportedAsSent(): void
    {
        $http = new RecordingTwitchTransport();
        $client = new HelixChatSender($http, 'test-client', 'test-token', '123', '456');
        $result = null;
        $client->sendMessage('Status')->then(static function (array $sent) use (&$result): void {
            $result = $sent;
        });
        $http->deferred->resolve(Response::json(['data' => [['message_id' => '', 'is_sent' => false, 'drop_reason' => ['code' => 'blocked', 'message' => 'Filtered']]]]));
        self::assertFalse($result['is_sent']);
    }

    public function testRateErrorPreservesStatusAndReleasesConcurrency(): void
    {
        $http = new RecordingTwitchTransport();
        $client = new HelixChatSender($http, 'test-client', 'test-token', '123', '456');
        $failure = null;
        $client->sendMessage('Status')->catch(static function (Throwable $error) use (&$failure): void {
            $failure = $error;
        });
        $http->deferred->resolve(new Response(429, [], 'Do not expose this body'));
        self::assertSame(429, $failure->httpStatus);
        self::assertFalse($failure->deliveryUnknown);
        $http->deferred = new Deferred();
        $client->sendMessage('Another approved request')->catch(static function (): void {
        });
        self::assertSame(2, $http->calls);
        $http->deferred->resolve(Response::json(['data' => [['message_id' => 'second', 'is_sent' => true]]]));
    }

    public function testMalformedSuccessHasUnknownDelivery(): void
    {
        foreach (['not-json', '"scalar"', '{"data":[]}', '{"data":[{"is_sent":true,"message_id":""}]}'] as $body) {
            $http = new RecordingTwitchTransport();
            $client = new HelixChatSender($http, 'test-client', 'test-token', '123', '456');
            $failure = null;
            $client->sendMessage('Status')->catch(static function (Throwable $error) use (&$failure): void {
                $failure = $error;
            });
            $http->deferred->resolve(new Response(200, [], $body));
            self::assertInstanceOf(TwitchRequestFailed::class, $failure);
            self::assertTrue($failure->deliveryUnknown);
        }
    }
}
