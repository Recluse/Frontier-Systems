<?php

declare(strict_types=1);

namespace Frontier\ControlPlane\Http;

use Frontier\ControlPlane\Diagnostics\RuntimeMetrics;
use Psr\Http\Message\ResponseInterface;
use Psr\Http\Message\ServerRequestInterface;
use React\Http\Message\Response;

final class ControlPlaneHandler
{
    public function __construct(private readonly RuntimeMetrics $metrics)
    {
    }

    public function __invoke(ServerRequestInterface $request): ResponseInterface
    {
        if ($request->getMethod() === 'GET' && $request->getUri()->getPath() === '/health') {
            return Response::json($this->metrics->snapshot());
        }

        if ($request->getMethod() === 'GET' && $request->getUri()->getPath() === '/metrics') {
            return Response::json([
                'runtime' => $this->metrics->snapshot(),
                'note' => 'Detailed simulation metrics are collected by the Godot profiling layer.',
            ]);
        }

        return Response::json(['error' => 'not_found'], Response::STATUS_NOT_FOUND);
    }
}
