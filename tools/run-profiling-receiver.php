<?php

declare(strict_types=1);

use Frontier\Profiling\Ingestion\ProfileCaptureIngestor;
use Frontier\Profiling\Persistence\InMemoryProfileCaptureRepository;
use Frontier\Profiling\Validation\RecordGuard;
use Frontier\ProfilingHttp\Development\LocalHostAuthenticator;
use Frontier\ProfilingHttp\Http\ProfileCaptureHttpHandler;
use Frontier\ProfilingHttp\Http\ProfileCaptureServerFactory;
use Frontier\WorldContracts\World\WorldIdentity;
use React\EventLoop\Loop;
use React\Socket\LimitingServer;
use React\Socket\SocketServer;

$root = dirname(__DIR__);
$autoload = $root . '/services/control-plane/vendor/autoload.php';
if (!is_file($autoload)) {
    fwrite(STDERR, "Run composer install in services/control-plane first.\n");
    exit(1);
}
// Development harness uses installed React dependencies and explicit Composer PSR-4 maps.
$loader = require $autoload;
$loader->addPsr4('Frontier\\WorldContracts\\', $root . '/packages/world-contracts/src');
$loader->addPsr4('Frontier\\Profiling\\', $root . '/packages/profiling/src');
$loader->addPsr4('Frontier\\ProfilingHttp\\', $root . '/packages/profiling-http/src');
$path = $argv[1] ?? $root . '/config/development/profiling.json';
try {
    if (!is_file($path) || filesize($path) > 16384) {
        throw new InvalidArgumentException('Missing or oversized local configuration.');
    }
    $config = RecordGuard::object(
        json_decode(file_get_contents($path), false, 16, JSON_THROW_ON_ERROR),
        ['schema_version', 'development_only', 'host', 'authentication', 'receiver', 'uploader']
    );
    RecordGuard::integer($config->schema_version, 1, 1);
    if ($config->development_only !== true) {
        throw new InvalidArgumentException('Receiver requires a development-only profile.');
    }
    $host = RecordGuard::object($config->host, ['world_id', 'region_id']);
    $auth = RecordGuard::object($config->authentication, ['bearer_token']);
    $receiver = RecordGuard::object($config->receiver, ['address', 'maximum_connections', 'maximum_concurrent', 'maximum_bytes',
        'authentication_timeout_seconds', 'body_timeout_seconds', 'retained_captures', 'retained_bytes']);
    if (!is_string($receiver->address) || preg_match('/\A127\.0\.0\.1:([0-9]{1,5})\z/', $receiver->address, $port) !== 1) {
        throw new InvalidArgumentException('Local receiver must bind literal IPv4 loopback.');
    }
    RecordGuard::integer((int) $port[1], 1, 65535);
    $scope = new WorldIdentity(RecordGuard::identifier($host->world_id), RecordGuard::identifier($host->region_id));
    $repository = new InMemoryProfileCaptureRepository(
        RecordGuard::integer($receiver->retained_captures, 1, 128),
        RecordGuard::integer($receiver->retained_bytes, 1, 134217728)
    );
    $loop = Loop::get();
    $handler = new ProfileCaptureHttpHandler(
        $loop,
        new LocalHostAuthenticator($auth->bearer_token, $scope),
        new ProfileCaptureIngestor($repository),
        RecordGuard::integer($receiver->maximum_bytes, 1, 8388608),
        RecordGuard::integer($receiver->maximum_concurrent, 1, 16),
        RecordGuard::number($receiver->authentication_timeout_seconds),
        RecordGuard::number($receiver->body_timeout_seconds)
    );
    $socket = new LimitingServer(new SocketServer($receiver->address, [], $loop), RecordGuard::integer($receiver->maximum_connections, 1, 64));
    $socket->on('error', static function (): void {
        fwrite(STDERR, "Local receiver connection error.\n");
    });
    $server = ProfileCaptureServerFactory::create($loop, $handler);
    $server->on('error', static function (): void {
        fwrite(STDERR, "Local receiver HTTP error.\n");
    });
    $server->listen($socket);
    fwrite(STDOUT, "Local development profiling receiver listening on {$receiver->address}\n");
    $loop->run();
} catch (Throwable $failure) {
    fwrite(STDERR, "Local receiver failed to initialize or run. Check configuration and port availability.\n");
    exit(1);
}
