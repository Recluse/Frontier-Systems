<?php

declare(strict_types=1);

/**
 * Rejects runtime PHP APIs and production dependencies that require POSIX process management
 * or spawn OS child processes. Development and build tooling is outside this policy check.
 */

$repositoryRoot = dirname(__DIR__);
$runtimeRoots = array_merge(
    glob($repositoryRoot . '/packages/*/src') ?: [],
    glob($repositoryRoot . '/services/*/src') ?: [],
);
$forbiddenFunctions = [
    'exec',
    'passthru',
    'pcntl_*',
    'popen',
    'posix_*',
    'proc_open',
    'shell_exec',
    'system',
];
$forbiddenPackages = ['react/child-process', 'ext-pcntl', 'ext-posix'];
$violations = [];

$composerManifests = array_merge(
    glob($repositoryRoot . '/packages/*/composer.json') ?: [],
    glob($repositoryRoot . '/services/*/composer.json') ?: [],
);
foreach ($composerManifests as $manifestPath) {
    $manifest = json_decode((string) file_get_contents($manifestPath), true, flags: JSON_THROW_ON_ERROR);
    foreach (array_keys($manifest['require'] ?? []) as $packageName) {
        if (in_array(strtolower($packageName), $forbiddenPackages, true)) {
            $violations[] = sprintf('%s requires Windows-incompatible package %s', $manifestPath, $packageName);
        }
    }
}

$composerLocks = glob($repositoryRoot . '/services/*/composer.lock') ?: [];
foreach ($composerLocks as $lockPath) {
    $lock = json_decode((string) file_get_contents($lockPath), true, flags: JSON_THROW_ON_ERROR);
    foreach ($lock['packages'] ?? [] as $package) {
        if (strtolower($package['name']) === 'react/child-process') {
            $violations[] = sprintf('%s locks Windows-incompatible package %s', $lockPath, $package['name']);
        }
    }
}

foreach ($runtimeRoots as $runtimeRoot) {
    $files = new RecursiveIteratorIterator(
        new RecursiveDirectoryIterator($runtimeRoot, FilesystemIterator::SKIP_DOTS),
    );

    foreach ($files as $file) {
        if (!$file->isFile() || $file->getExtension() !== 'php') {
            continue;
        }

        $tokens = token_get_all(file_get_contents($file->getPathname()), TOKEN_PARSE);
        foreach ($tokens as $token) {
            if (!is_array($token)) {
                continue;
            }

            [$tokenId, $tokenText] = $token;
            if (!in_array($tokenId, [T_NAME_FULLY_QUALIFIED, T_NAME_QUALIFIED, T_STRING], true)) {
                continue;
            }

            $name = strtolower(ltrim($tokenText, '\\'));
            $functionName = str_contains($name, '\\') ? substr($name, strrpos($name, '\\') + 1) : $name;
            $isReactChildProcess = $name === 'react\\childprocess'
                || str_starts_with($name, 'react\\childprocess\\');
            $isForbiddenFunction = in_array($functionName, $forbiddenFunctions, true)
                || str_starts_with($functionName, 'pcntl_')
                || str_starts_with($functionName, 'posix_');

            if ($isReactChildProcess || $isForbiddenFunction) {
                $violations[] = sprintf('%s:%d uses forbidden runtime API %s', $file->getPathname(), $token[2], $tokenText);
            }
        }
    }
}

if ($violations !== []) {
    fwrite(STDERR, "Windows runtime policy violations:\n" . implode("\n", $violations) . "\n");
    exit(1);
}

fwrite(STDOUT, "Windows runtime policy passed.\n");
