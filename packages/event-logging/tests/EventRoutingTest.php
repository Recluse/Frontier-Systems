<?php

declare(strict_types=1);

namespace Frontier\EventLogging\Tests;

use Frontier\EventLogging\Discord\ChannelSenderInterface;
use Frontier\EventLogging\Event\EventPolicy;
use Frontier\EventLogging\Event\GameEvent;
use Frontier\EventLogging\Http\EventHttpHandler;
use Frontier\EventLogging\Logging\ChannelRoutes;
use Frontier\EventLogging\Logging\DiscordRoutingHandler;
use Frontier\EventLogging\Logging\EventIngestor;
use Frontier\ProfilingHttp\Development\LocalHostAuthenticator;
use Frontier\WorldContracts\World\WorldIdentity;
use Monolog\Logger;
use PHPUnit\Framework\TestCase;
use React\EventLoop\StreamSelectLoop;
use React\Http\Message\ServerRequest;
use React\Promise\Deferred;
use React\Promise\PromiseInterface;
use React\Stream\ThroughStream;

final class EventRoutingTest extends TestCase
{
    public function testPrivateChannelAclRejectsPublicOrUnapprovedGrants(): void
    {
        $policy = new \Frontier\EventLogging\Discord\GuildAudiencePolicy(['staff'], ['bot'], ['a' => ['roles' => [], 'users' => ['crew']]]);
        $staff = ['audience' => 'staff', 'scope_id' => '', 'kinds' => ['*']];
        $denial = ['id' => 'guild', 'type' => 0, 'allow_view' => false, 'deny_view' => true];
        self::assertTrue($policy->allows('guild', ['staff'], [$denial], $staff));
        self::assertFalse($policy->allows('guild', ['unapproved-admin'], [$denial], $staff));
        self::assertFalse($policy->allows('guild', [], [], $staff));
        $grant = ['id' => 'crew', 'type' => 1, 'allow_view' => true, 'deny_view' => false];
        self::assertFalse($policy->allows('guild', [], [$denial, $grant], $staff));
        self::assertTrue($policy->allows('guild', [], [$denial, $grant], ['audience' => 'private', 'scope_id' => 'a', 'kinds' => ['*']]));
        self::assertFalse($policy->allows('guild', [], [$denial, $grant], ['audience' => 'private', 'scope_id' => 'b', 'kinds' => ['*']]));
    }
    private function json(string $id, string $kind = 'game.event', string $audience = 'public', string $scope = '', ?array $data = null): string
    {
        return json_encode(['schema_version' => 1, 'event_id' => $id, 'world_id' => 'world', 'region_id' => 'region', 'tick_number' => 10,
            'kind' => $kind, 'audience' => $audience, 'scope_id' => $scope, 'data' => (object)($data ?? ['text' => 'hello'])], JSON_THROW_ON_ERROR);
    }

    public function testAudienceIsolationAndSharedMonologWithoutSynchronousSends(): void
    {
        $loop = new StreamSelectLoop();
        $sender = new RecordingSender();
        $routes = new ChannelRoutes([
            '101' => ['audience' => 'public', 'scope_id' => '', 'kinds' => ['*']],
            '102' => ['audience' => 'staff', 'scope_id' => '', 'kinds' => ['*']],
            '103' => ['audience' => 'private', 'scope_id' => 'conversation-a', 'kinds' => ['chat.private']],
            '104' => ['audience' => 'private', 'scope_id' => 'conversation-b', 'kinds' => ['chat.private']],
        ]);
        $handler = new DiscordRoutingHandler($loop, $routes, $sender);
        $legacy = new \Monolog\Handler\TestHandler();
        $logger = new Logger('same-discordphp-logger', [$handler, $legacy]);
        $ingestor = new EventIngestor($logger, new EventPolicy());
        $scope = new WorldIdentity('world', 'region');
        $ingestor->ingest($scope, $this->json('public'));
        $ingestor->ingest($scope, $this->json('private', 'chat.private', 'private', 'conversation-a', ['text' => 'private text','speaker' => 'crew']));
        $ingestor->ingest($scope, $this->json('llm', 'llm.response', 'staff', '', ['text' => 'model trace','agent' => 'station-ai']));
        $logger->debug('SDK traffic must not be forwarded', ['Authorization' => 'secret']);
        self::assertCount(1, $legacy->getRecords());
        self::assertSame([], $sender->calls);
        self::assertSame(5, $handler->counters()['queued']);
        while ($handler->counters()['queued'] > 0) {
            $handler->pump();
            $sender->pending->resolve(null);
        }
        self::assertSame(['101','102','102','103','102'], array_column($sender->calls, 'channel'));
        foreach ($sender->calls as $call) {
            if ($call['channel'] === '101') {
                self::assertStringNotContainsString('private text', $call['content']);
                self::assertStringNotContainsString('model trace', $call['content']);
            }
        }
        self::assertSame(5, $handler->counters()['delivered']);
    }

    public function testDowngradeUnknownAndCredentialFieldsReject(): void
    {
        foreach ([
            $this->json('bad', 'llm.response', 'public', '', ['text' => 'secret','agent' => 'AI']),
            $this->json('bad', 'unknown', 'public'),
            $this->json('bad', 'game.event', 'public', '', ['text' => 'hello','token' => 'secret']),
            $this->json('bad', 'chat.private', 'private', '', ['text' => 'hello','speaker' => 'crew']),
        ] as $json) {
            try {
                GameEvent::decode($json, new WorldIdentity('world', 'region'), new EventPolicy());
                self::fail('Invalid policy was accepted.');
            } catch (\InvalidArgumentException) {
                self::assertTrue(true);
            }
        }
    }

    public function testRetainedRetryAndChangedIntent(): void
    {
        $logger = new Logger('test');
        $ingestor = new EventIngestor($logger, new EventPolicy());
        $scope = new WorldIdentity('world', 'region');
        self::assertTrue($ingestor->ingest($scope, $this->json('same')));
        self::assertFalse($ingestor->ingest($scope, $this->json('same')));
        $this->expectException(\RuntimeException::class);
        $ingestor->ingest($scope, $this->json('same', 'game.event', 'public', '', ['text' => 'changed']));
    }

    public function testQueueBoundsUtf8AndTerminalFailures(): void
    {
        $loop = new StreamSelectLoop();
        $sender = new RecordingSender();
        $handler = new DiscordRoutingHandler($loop, new ChannelRoutes(['101' => ['audience' => 'public','scope_id' => '','kinds' => ['*']]]), $sender, 8);
        $ingestor = new EventIngestor(new Logger('test', [$handler]), new EventPolicy());
        $scope = new WorldIdentity('world', 'region');
        $ingestor->ingest($scope, $this->json('unicode', 'game.event', 'public', '', ['text' => str_repeat('🌕', 1000)]));
        while ($handler->counters()['queued'] > 0) {
            $handler->pump();
            self::assertSame(1, preg_match('//u', $sender->calls[array_key_last($sender->calls)]['content']));
            self::assertLessThanOrEqual(1900, strlen($sender->calls[array_key_last($sender->calls)]['content']));
            $sender->pending->resolve(null);
        }
        for ($i = 0;$i < 10;++$i) {
            $ingestor->ingest($scope, $this->json('overflow-'.$i));
        }
        self::assertSame(2, $handler->counters()['dropped']);
        for ($i = 0;$i < 3;++$i) {
            $handler->pump();
            $sender->pending->reject(new \RuntimeException('failed'));
        }
        self::assertSame(1, $handler->counters()['failed']);
    }

    public function testUncertainDeliveryStallsInsteadOfCreatingMoreRequests(): void
    {
        $loop = new StreamSelectLoop();
        $sender = new RecordingSender();
        $handler = new DiscordRoutingHandler($loop, new ChannelRoutes(['101' => ['audience' => 'public','scope_id' => '','kinds' => ['*']]]), $sender, 8, 524288, 0.01);
        (new EventIngestor(new Logger('test', [$handler]), new EventPolicy()))->ingest(new WorldIdentity('world', 'region'), $this->json('stall'));
        $handler->pump();
        $loop->addTimer(0.03, $loop->stop(...));
        $loop->run();
        self::assertTrue($handler->counters()['stalled']);
        $handler->pump();
        self::assertCount(1, $sender->calls);
        $sender->pending->resolve(null); // Late completion cannot double-count or drain a new item.
        self::assertSame(0, $handler->counters()['delivered']);
    }

    public function testAuthenticatedStreamingIngress(): void
    {
        $loop = new StreamSelectLoop();
        $handler = new EventHttpHandler(
            $loop,
            new LocalHostAuthenticator('host-token', new WorldIdentity('world', 'region')),
            new EventIngestor(new Logger('ingress'), new EventPolicy())
        );
        $stream = new ThroughStream();
        $request = new ServerRequest('POST', 'http://localhost/v1/events', ['Content-Type' => 'application/json','Authorization' => 'Bearer host-token'], $stream, '1.1', ['REMOTE_ADDR' => '127.0.0.1']);
        $response = null;
        $handler($request)->then(static function ($value) use (&$response): void {
            $response = $value;
        });
        $stream->end($this->json('http'));
        self::assertSame(202, $response->getStatusCode());
        $bad = $request->withHeader('Authorization', 'Bearer wrong');
        $handler($bad)->then(static function ($value) use (&$response): void {
            $response = $value;
        });
        self::assertSame(401, $response->getStatusCode());
    }
}
