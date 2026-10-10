<?php

declare(strict_types=1);

namespace Frontier\Twitch\Status;

use Frontier\ServerStatus\PublicStatusRepositoryInterface;
use Frontier\WorldContracts\World\WorldIdentity;
use React\Promise\PromiseInterface;

use function React\Promise\reject;
use function React\Promise\resolve;

/** Bindings are operator-authenticated configuration, not viewer-supplied world identities. */
final class ChannelStatusProvider
{
    /** @var array<string, array{identity: WorldIdentity, generation: int}> */
    private array $bindings = [];
    private int $generation = 0;

    public function __construct(private readonly PublicStatusRepositoryInterface $repository, private readonly int $maxChannels = 16)
    {
        if ($maxChannels < 1 || $maxChannels > 128) {
            throw new \InvalidArgumentException('Channel binding capacity must be 1..128.');
        }
    }

    /** Call only after broadcaster and host operator authorization. */
    public function bind(string $broadcasterId, WorldIdentity $authorizedWorld): void
    {
        self::validateId($broadcasterId);
        if (!isset($this->bindings[$broadcasterId]) && count($this->bindings) >= $this->maxChannels) {
            throw new \OverflowException('Channel binding capacity is exhausted.');
        }
        if ($this->generation >= 9_007_199_254_740_990) {
            throw new \OverflowException('Binding generation is exhausted.');
        }
        $this->bindings[$broadcasterId] = ['identity' => $authorizedWorld, 'generation' => ++$this->generation];
    }

    public function unbind(string $broadcasterId): void
    {
        self::validateId($broadcasterId);
        unset($this->bindings[$broadcasterId]);
    }

    /** @return PromiseInterface<array{availability: string, effective_online: bool, status: ?array}> */
    public function publicView(string $broadcasterId, int $nowUnix): PromiseInterface
    {
        try {
            self::validateId($broadcasterId);
        } catch (\InvalidArgumentException $error) {
            return reject($error);
        }
        $binding = $this->bindings[$broadcasterId] ?? null;
        if ($binding === null) {
            return resolve(['availability' => 'unbound', 'effective_online' => false, 'status' => null]);
        }
        return $this->repository->publicView($binding['identity'], $nowUnix)->then(function (array $view) use ($broadcasterId, $binding): array {
            // A future asynchronous repository may resolve after unlink/rebind.
            if (($this->bindings[$broadcasterId]['generation'] ?? null) !== $binding['generation']) {
                return ['availability' => 'unbound', 'effective_online' => false, 'status' => null];
            }
            return $view;
        });
    }

    private static function validateId(string $id): void
    {
        if (preg_match('/\A[1-9][0-9]{0,31}\z/', $id) !== 1) {
            throw new \InvalidArgumentException('A bounded numeric broadcaster ID is required.');
        }
    }
}
