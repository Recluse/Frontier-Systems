<?php

declare(strict_types=1);

namespace Frontier\ProfilingHttp\Http;

use React\EventLoop\LoopInterface;
use React\Http\HttpServer;
use React\Http\Middleware\StreamingRequestMiddleware;

/** Returns an unbound server; application owns socket, TLS, connection caps and errors. */
final class ProfileCaptureServerFactory
{
    public static function create(LoopInterface $loop, ProfileCaptureHttpHandler $handler): HttpServer
    {
        return new HttpServer($loop, new StreamingRequestMiddleware(), $handler);
    }
}
