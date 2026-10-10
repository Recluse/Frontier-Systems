<?php

declare(strict_types=1);

use Discord\Discord;
use Frontier\EventLogging\Discord\DiscordGuildAudienceVerifier;
use Frontier\EventLogging\Discord\DiscordPhpEventBridge;
use Frontier\EventLogging\Discord\GuildAudiencePolicy;
use Frontier\EventLogging\Http\EventHttpHandler;
use Frontier\EventLogging\Logging\ChannelRoutes;
use Frontier\ProfilingHttp\Development\LocalHostAuthenticator;
use Frontier\WorldContracts\World\WorldIdentity;
use React\Http\HttpServer;
use React\Http\Middleware\StreamingRequestMiddleware;
use React\Socket\LimitingServer;
use React\Socket\SocketServer;

/** Call once after the existing bot is ready; keep returned bridge/server/socket for shutdown. */
return static function (Discord $discord, array $config, string $hostToken): array {
    if (strlen($hostToken) < 32) {
        throw new InvalidArgumentException('Host event token must contain at least 32 characters.');
    }
    $loop = $discord->getLoop();
    $routes = new ChannelRoutes($config['channels']);
    $policy = new GuildAudiencePolicy($config['staff_role_ids'], $config['staff_user_ids'], $config['conversations']);
    $bridge = new DiscordPhpEventBridge($discord, $loop, $routes, new DiscordGuildAudienceVerifier($discord, $config['guild_id'], $policy));
    $handler = new EventHttpHandler($loop, new LocalHostAuthenticator($hostToken, new WorldIdentity($config['world_id'], $config['region_id'])), $bridge->ingestor);
    $server = new HttpServer($loop, new StreamingRequestMiddleware(), $handler);
    $socket = new LimitingServer(new SocketServer('127.0.0.1:27841', [], $loop), 8);
    $server->listen($socket);
    return ['bridge' => $bridge, 'server' => $server, 'socket' => $socket];
};
