# Local profiling defaults

The shared preset is `config/development/profiling.json`. It binds the PHP receiver to **127.0.0.1:8081**, authenticates uploads for `development-world` / `local-habitat`, captures 120 ticks, and uses a one MiB request limit with two active uploads. The committed token is a public **test fixture**, usable only with the loopback-only development authenticator. Normal game startup does not enable uploads or consume this preset.

## One-command Windows smoke test

Install the existing control-plane dependencies first if needed (`composer install` in `services/control-plane`). From the project root in PowerShell 7:

```powershell
& .\tools\test-local-profiling.ps1 `
  -PhpExecutable 'C:\php\php.exe' `
  -GodotExecutable 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
```

The launcher starts its own hidden receiver on Windows, waits for readiness, runs the Godot upload scenario and stops its receiver even on failure. It refuses an occupied port, avoiding an unrelated receiver or stale in-memory capture frontier. Logs are under ignored `var/profiling-tests/`. With executable names on PATH, the default `php` and `godot` parameters work on PowerShell 7 for Windows/Linux; Linux has not been exercised locally.

## Manual two-terminal flow

Terminal one, from the project root:

```powershell
& 'C:\php\php.exe' .\tools\run-profiling-receiver.php
```

Terminal two:

```powershell
& 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' `
  --headless --path . --script res://tests/godot/local_profiling_upload_test.gd
```

Success prints `PASS: local profiling upload received a validated stored receipt.` Stop the receiver with Ctrl+C. Restart it before an independent smoke run because a fresh Godot world starts its tick counter over and the repository rejects older frontiers.

The PHP harness uses the control-plane vendor autoloader plus explicit Composer PSR-4 mappings for the new first-party packages. It neither changes the production dependency graph nor opens a public interface. Startup file I/O is outside its event loop; runtime network work uses ReactPHP.

## Overrides and HTTP fixtures

The one-command launcher also validates identical-capture retry receipts and rejection of invalid credentials, malformed captures, wrong scope, oversized payloads and delayed captures. The Godot scenario checks one-upload backpressure. See [circuit recovery checks](control-recovery-checks.md) for the independent maintenance/snapshot suite.

Copy the preset into ignored `config/local/` for private adjustments. Pass its absolute path using `-Configuration` on the launcher; the manual receiver accepts it as its first argument. The Godot test accepts `-- --profiling-config=D:/path/to/profiling.json`. Keep the uploader endpoint and receiver port aligned, host scope identical, and request byte limits aligned. The versioned configuration schema is under `docs/schema/`.

`tests/fixtures/profiling/empty-capture.v1.json` is an additional valid zero-sample HTTP payload for a fresh receiver. Its frontier is zero, so sending it after a newer capture should reject as stale. The authenticator checks the actual socket peer and token, not forwarded headers or payload identity.

## Verification performed

Windows Godot 4.7.2 import, headless startup, module contract tests, manual airlock tests and a real Godot-to-PHP upload passed. Negative HTTP probes returned 401 for bad credentials, 422 for malformed capture/wrong scope and 413 for oversized input. PHP used the installed 8.5 runtime. This does not cover production authentication, TLS, durable storage, load behavior or Linux execution.

The checks also found and repaired a missing bracket in the profiling panel and a promise lifetime bug: queued reactions now retain their settled source promise until the deferred callback executes.
