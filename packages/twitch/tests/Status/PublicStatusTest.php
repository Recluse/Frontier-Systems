<?php

declare(strict_types=1);

namespace Frontier\Twitch\Tests\Status;

use Frontier\ServerStatus\InMemoryPublicStatusRepository;
use Frontier\ServerStatus\PublicServerStatus;
use Frontier\ServerStatus\PublicStatusIngestor;
use Frontier\Twitch\Status\ChannelStatusProvider;
use Frontier\Twitch\Tests\Fixtures\DeferredStatusRepository;
use Frontier\WorldContracts\World\WorldIdentity;
use PHPUnit\Framework\TestCase;
use React\Promise\PromiseInterface;

final class PublicStatusTest extends TestCase
{
    public function testAuthenticatedProjectionAndFreshness(): void
    {
        $repository = new InMemoryPublicStatusRepository();
        $ingestor = new PublicStatusIngestor($repository);
        $world = new WorldIdentity('world.private-id', 'region.private-id');
        self::await($ingestor->ingest($world, self::json(), 100));
        $channels = new ChannelStatusProvider($repository);
        $channels->bind('123', $world);
        $view = self::await($channels->publicView('123', 101));
        self::assertSame('fresh', $view['availability']);
        self::assertTrue($view['effective_online']);
        self::assertArrayNotHasKey('world_id', $view['status']);
        self::assertArrayNotHasKey('region_id', $view['status']);
        self::assertArrayNotHasKey('tick_number', $view['status']);
        $view['status']['public_name'] = 'edited';
        self::assertSame('Example colony', self::await($channels->publicView('123', 101))['status']['public_name']);
        self::assertSame('stale', self::await($channels->publicView('123', 130))['availability']);
        self::assertFalse(self::await($channels->publicView('123', 130))['effective_online']);
        self::assertSame('unbound', self::await($channels->publicView('456', 101))['availability']);
        $channels->unbind('123');
        self::assertNull(self::await($channels->publicView('123', 101))['status']);
    }

    public function testScopeAndPrivateFieldsReject(): void
    {
        $ingestor = new PublicStatusIngestor(new InMemoryPublicStatusRepository());
        $failure = null;
        $ingestor->ingest(new WorldIdentity('another-world', 'region.private-id'), self::json(), 100)
            ->catch(static function (\Throwable $error) use (&$failure): void {
                $failure = $error;
            });
        self::assertInstanceOf(\InvalidArgumentException::class, $failure);
        $this->expectException(\InvalidArgumentException::class);
        PublicServerStatus::fromJson(self::json(['medical_records' => ['secret']]));
    }

    public function testFrontierRetryAndRetentionBounds(): void
    {
        $repository = new InMemoryPublicStatusRepository(1);
        $first = PublicServerStatus::fromJson(self::json());
        self::await($repository->store($first, 100));
        self::assertSame($first, self::await($repository->store($first, 101)));
        $failure = null;
        $repository->store(PublicServerStatus::fromJson(self::json(['tick_number' => 9, 'observed_at_unix' => 101])), 101)
            ->catch(static function (\Throwable $error) use (&$failure): void {
                $failure = $error;
            });
        self::assertInstanceOf(\InvalidArgumentException::class, $failure);
        $failure = null;
        $repository->store(PublicServerStatus::fromJson(self::json(['players_online' => 2])), 100)
            ->catch(static function (\Throwable $error) use (&$failure): void {
                $failure = $error;
            });
        self::assertInstanceOf(\InvalidArgumentException::class, $failure);
        self::await($repository->store(PublicServerStatus::fromJson(self::json(['world_id' => 'second-world'])), 100));
        self::assertSame(1, $repository->metrics()['regions']);
        self::assertSame(1, $repository->metrics()['evictions']);
        self::assertSame('unavailable', self::await($repository->publicView($first->identity(), 100))['availability']);
    }

    public function testInvalidCountsAndTimestamps(): void
    {
        foreach ([['players_online' => 9], ['online' => false], ['players_online' => 1.5], ['public_name' => "bad\nname"]] as $change) {
            try {
                PublicServerStatus::fromJson(self::json($change));
                self::fail('Invalid fields must reject.');
            } catch (\InvalidArgumentException) {
                self::assertTrue(true);
            }
        }
        $repository = new InMemoryPublicStatusRepository();
        foreach ([99, 130] as $now) {
            $failure = null;
            $repository->store(PublicServerStatus::fromJson(self::json()), $now)
                ->catch(static function (\Throwable $error) use (&$failure): void {
                    $failure = $error;
                });
            self::assertInstanceOf(\InvalidArgumentException::class, $failure);
        }
    }

    public function testLateResultCannotSurviveUnlinkAndRebind(): void
    {
        $repository = new DeferredStatusRepository();
        $channels = new ChannelStatusProvider($repository);
        $identity = new WorldIdentity('world', 'region');
        $channels->bind('123', $identity);
        $view = null;
        $channels->publicView('123', 100)->then(static function (array $result) use (&$view): void {
            $view = $result;
        });
        self::assertNull($view);
        $channels->unbind('123');
        $channels->bind('123', $identity);
        $repository->pending->resolve(['availability' => 'fresh', 'effective_online' => true, 'status' => ['public_name' => 'old response']]);
        self::assertSame('unbound', $view['availability']);
        self::assertNull($view['status']);
    }

    public function testByteBudgetEvictsBeforeGrowingWithoutLimit(): void
    {
        $repository = new InMemoryPublicStatusRepository(128, 4096);
        for ($index = 0; $index < 100; $index++) {
            self::await($repository->store(PublicServerStatus::fromJson(self::json(['world_id' => 'world-' . $index, 'public_name' => str_repeat('🪐', 128)])), 100));
            self::assertLessThanOrEqual(4096, $repository->metrics()['encoded_bytes']);
        }
        self::assertGreaterThan(0, $repository->metrics()['evictions']);
    }

    private static function json(array $changes = []): string
    {
        return json_encode(array_replace(['schema_version' => 1, 'world_id' => 'world.private-id', 'region_id' => 'region.private-id', 'tick_number' => 10,
            'public_name' => 'Example colony', 'online' => true, 'players_online' => 1, 'player_capacity' => 8, 'observed_at_unix' => 100], $changes), JSON_THROW_ON_ERROR);
    }

    private static function await(PromiseInterface $promise): mixed
    {
        $value = null;
        $error = null;
        $settled = false;
        $promise->then(
            static function ($result) use (&$value, &$settled): void {
                $value = $result;
                $settled = true;
            },
            static function (\Throwable $failure) use (&$error, &$settled): void {
                $error = $failure;
                $settled = true;
            }
        );
        self::assertTrue($settled, 'In-memory operations must settle synchronously without I/O.');
        if ($error !== null) {
            throw $error;
        }
        return $value;
    }
}
