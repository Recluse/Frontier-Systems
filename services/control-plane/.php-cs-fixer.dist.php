<?php

declare(strict_types=1);

use PhpCsFixer\Config;
use PhpCsFixer\Finder;

return (new Config())
    ->setRiskyAllowed(false)
    // The fixed PSR-12 rules are version-neutral; allow running the formatter on PHP 8.5+.
    ->setUnsupportedPhpVersionAllowed(true)
    ->setRules([
        '@PSR12' => true,
    ])
    ->setFinder(
        (new Finder())
            ->in(__DIR__ . '/src')
            ->in(__DIR__ . '/tests')
            ->in(__DIR__ . '/../../packages/world-contracts/src')
            ->in(__DIR__ . '/../../packages/profiling/src')
            ->in(__DIR__ . '/../../packages/profiling-http/src')
            ->append([
                __DIR__ . '/bin/control-plane.php',
                __DIR__ . '/build/build-phar.php',
                __DIR__ . '/../../tools/check-windows-runtime-policy.php',
                __DIR__ . '/../../tools/run-profiling-receiver.php',
            ]),
    );
