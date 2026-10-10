<?php

declare(strict_types=1);

/**
 * Builds bin/build/control-plane.phar with production dependencies.
 * Run with: composer phar
 */

$repositoryRoot = dirname(__DIR__, 3);
$serviceRoot = dirname(__DIR__);
$output = $serviceRoot . '/bin/build/control-plane.phar';
$stagingRoot = sys_get_temp_dir() . DIRECTORY_SEPARATOR . 'frontier-control-plane-' . bin2hex(random_bytes(6));
$stagingService = $stagingRoot . '/services/control-plane';

$remove = static function (string $path) use (&$remove, $stagingRoot): void {
    if (!is_dir($path)) {
        return;
    }
    $resolved = realpath($path);
    $resolvedRoot = realpath($stagingRoot);
    if ($resolved === false || $resolvedRoot === false || (strtolower($resolved) !== strtolower($resolvedRoot)
        && !str_starts_with(strtolower($resolved), strtolower($resolvedRoot . DIRECTORY_SEPARATOR)))) {
        throw new RuntimeException('Refusing cleanup outside the checked build staging directory.');
    }

    $items = new RecursiveIteratorIterator(
        new RecursiveDirectoryIterator($path, FilesystemIterator::SKIP_DOTS),
        RecursiveIteratorIterator::CHILD_FIRST,
    );

    foreach ($items as $item) {
        if ($item->isDir() && !$item->isLink()) {
            rmdir($item->getPathname());
        } else {
            unlink($item->getPathname());
        }
    }

    rmdir($path);
};

$copy = static function (string $source, string $destination) use (&$copy): void {
    if (!is_dir($destination)) {
        mkdir($destination, 0777, true);
    }

    foreach (new DirectoryIterator($source) as $item) {
        if ($item->isDot()) {
            continue;
        }
        if (in_array($item->getFilename(), ['vendor', 'var', '.git', 'node_modules'], true)
            || str_starts_with($item->getFilename(), '.env')
            || (basename($source) === 'bin' && $item->getFilename() === 'build')) {
            continue;
        }

        $target = $destination . DIRECTORY_SEPARATOR . $item->getFilename();
        if ($item->isDir() && !$item->isLink()) {
            $copy($item->getPathname(), $target);
        } else {
            copy($item->getPathname(), $target);
        }
    }
};

if ((bool) ini_get('phar.readonly')) {
    fwrite(STDERR, "phar.readonly is enabled. Run: composer phar\n");
    exit(1);
}

try {
    mkdir($stagingService . '/src', 0777, true);
    $copy($serviceRoot . '/src', $stagingService . '/src');
    $copy($serviceRoot . '/bin', $stagingService . '/bin');
    foreach (['LICENSE', 'THIRD_PARTY_NOTICES.md'] as $notice) {
        copy($repositoryRoot . '/' . $notice, $stagingService . '/' . $notice);
    }
    $locked = json_decode(file_get_contents($serviceRoot . '/composer.lock'), true, flags: JSON_THROW_ON_ERROR);
    foreach ($locked['packages'] as $package) {
        if (($package['dist']['type'] ?? null) !== 'path') {
            continue;
        }
        $source = realpath($serviceRoot . '/' . $package['dist']['url']);
        $workspacePackages = realpath($repositoryRoot . '/packages');
        if ($source === false || $workspacePackages === false
            || !str_starts_with(strtolower($source), strtolower($workspacePackages . DIRECTORY_SEPARATOR))) {
            throw new RuntimeException('Locked local dependencies must resolve inside workspace packages.');
        }
        $copy($source, $stagingRoot . '/packages/' . basename($source));
    }

    foreach (['composer.json', 'composer.lock'] as $file) {
        if (is_file($serviceRoot . '/' . $file)) {
            copy($serviceRoot . '/' . $file, $stagingService . '/' . $file);
        }
    }

    $command = sprintf(
        'composer install --no-dev --prefer-dist --optimize-autoloader --no-interaction --no-scripts --working-dir=%s',
        escapeshellarg($stagingService),
    );
    passthru($command, $status);
    if ($status !== 0) {
        throw new RuntimeException('Composer production dependency installation failed.');
    }

    $remove($stagingRoot . '/packages');
    if (!is_dir(dirname($output))) {
        mkdir(dirname($output), 0777, true);
    }
    if (is_file($output)) {
        unlink($output);
    }

    $phar = new Phar($output);
    $phar->startBuffering();
    $phar->buildFromIterator(
        new RecursiveIteratorIterator(
            new RecursiveDirectoryIterator($stagingService, FilesystemIterator::SKIP_DOTS),
        ),
        $stagingService,
    );
    $phar->setStub(Phar::createDefaultStub('bin/control-plane.php'));
    $phar->stopBuffering();

    fwrite(STDOUT, "Built {$output}\n");
} finally {
    $remove($stagingRoot);
}
