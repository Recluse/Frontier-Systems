<?php

declare(strict_types=1);

$packageAutoload = dirname(__DIR__) . '/vendor/autoload.php';
$workspaceAutoload = dirname(__DIR__, 3) . '/services/control-plane/vendor/autoload.php';
require is_file($packageAutoload) ? $packageAutoload : $workspaceAutoload;
spl_autoload_register(static function (string $class): void {
    $testPrefix = 'Frontier\\EventLogging\\Tests\\';
    if (str_starts_with($class, $testPrefix)) {
        $file = __DIR__ . '/' . str_replace('\\', '/', substr($class, strlen($testPrefix))) . '.php';
        if (is_file($file)) {
            require $file;
            return;
        }
    }
    $prefix = 'Frontier\\EventLogging\\';
    if (str_starts_with($class, $prefix)) {
        $file = dirname(__DIR__) . '/src/' . str_replace('\\', '/', substr($class, strlen($prefix))) . '.php';
        if (is_file($file)) {
            require $file;
        }
    }
}, true, true);
