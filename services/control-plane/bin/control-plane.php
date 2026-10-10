<?php

declare(strict_types=1);

use Frontier\ControlPlane\Diagnostics\RuntimeMetrics;
use Frontier\ControlPlane\Http\ControlPlaneHandler;
use React\EventLoop\Loop;
use React\Http\HttpServer;
use React\Socket\SocketServer;

require dirname(__DIR__) . '/vendor/autoload.php';

$address = getenv('FRONTIER_CONTROL_PLANE_ADDRESS') ?: '127.0.0.1:8080';
$loop = Loop::get();
$socket = new SocketServer($address, [], $loop);
$server = new HttpServer(new ControlPlaneHandler(new RuntimeMetrics()));
$server->listen($socket);

fwrite(STDOUT, sprintf("Frontier Systems control plane listening on http://%s\n", $address));
$loop->run();
