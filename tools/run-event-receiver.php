<?php

declare(strict_types=1);

use Frontier\EventLogging\Event\EventPolicy;
use Frontier\EventLogging\Http\EventHttpHandler;
use Frontier\EventLogging\Logging\EventIngestor;
use Frontier\ProfilingHttp\Development\LocalHostAuthenticator;
use Frontier\WorldContracts\World\WorldIdentity;
use Monolog\Handler\StreamHandler;
use Monolog\Logger;
use React\EventLoop\Loop;
use React\Http\HttpServer;
use React\Http\Middleware\StreamingRequestMiddleware;
use React\Socket\LimitingServer;
use React\Socket\SocketServer;

require dirname(__DIR__) . '/services/control-plane/vendor/autoload.php';
$token = getenv('FRONTIER_EVENT_TOKEN') ?: '';
if (strlen($token) < 32) {
    fwrite(STDERR, "Set an ignored FRONTIER_EVENT_TOKEN of at least 32 characters.\n");
    exit(1);
}
$loop = Loop::get();
$scope = new WorldIdentity(getenv('FRONTIER_EVENT_WORLD') ?: 'development-world', getenv('FRONTIER_EVENT_REGION') ?: 'local-habitat');
$logger = new Logger('frontier-events');
$logger->pushHandler(new StreamHandler(STDOUT));
$handler = new EventHttpHandler($loop, new LocalHostAuthenticator($token, $scope), new EventIngestor($logger, new EventPolicy()));
$server = new HttpServer($loop, new StreamingRequestMiddleware(), $handler);
$address = getenv('FRONTIER_EVENT_ADDRESS') ?: '127.0.0.1:27841';
if (preg_match('/\A127\.0\.0\.1:([0-9]{1,5})\z/', $address, $match) !== 1 || (int) $match[1] < 1 || (int) $match[1] > 65535) {
    throw new InvalidArgumentException('Event receiver must bind loopback.');
}
$server->listen(new LimitingServer(new SocketServer($address, [], $loop), 8));
$server->on('error', static function (): void {
    fwrite(STDERR, "Event receiver transport error.\n");
});
fwrite(STDOUT, "Local event receiver: http://127.0.0.1:27841/v1/events (no Discord sends).\n");
$loop->run();
