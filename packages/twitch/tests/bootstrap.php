<?php

declare(strict_types=1);

$packageAutoload = dirname(__DIR__) . '/vendor/autoload.php';
$workspaceAutoload = dirname(__DIR__, 3) . '/services/control-plane/vendor/autoload.php';
require is_file($packageAutoload) ? $packageAutoload : $workspaceAutoload;

spl_autoload_register(static function (string $class): void {
    foreach (['Frontier\\Twitch\\Tests\\' => '/tests/', 'Frontier\\Twitch\\' => '/src/', 'Frontier\\ServerStatus\\' => '/../server-status/src/', 'Frontier\\WorldContracts\\' => '/../world-contracts/src/'] as $prefix => $directory) {
        if (str_starts_with($class, $prefix)) {
            $file = dirname(__DIR__) . $directory . str_replace('\\', '/', substr($class, strlen($prefix))) . '.php';
            if (is_file($file)) {
                require $file;
                return;
            }
        }
    }
});
