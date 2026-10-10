# Contributing

## Branch and pull request workflow

- `dev-master` is the primary integration branch.
- Small, cohesive changes may be made directly on `dev-master` when repository access rules allow it.
- For isolated or higher-risk work, branch from the latest `dev-master` using a descriptive name such as `feature/pressure-networks` or `fix/command-validation`.
- Open feature-branch pull requests against `dev-master`. Keep PRs focused and update related design/API documentation with contract changes.
- Do not merge a PR until the PHP quality and Godot project import checks pass. Review the license and asset provenance checklist for any new dependency or asset.
- All runtime systems must work on Windows. Runtime code and production dependencies must not use ReactPHP child processes, `pcntl`, POSIX-only APIs, or shell-based process orchestration; use asynchronous networking and platform-neutral service protocols instead. Development and build tools may have separate requirements but must themselves run on Windows when used by contributors.

## Local checks

Run PHP commands from `services/control-plane/`:

```powershell
composer install
composer validate --strict
composer cs-check
composer unit
composer audit --locked
php ../../tools/check-windows-runtime-policy.php
```

To check the Godot project with the project's configured engine version:

```powershell
godot --headless --editor --path . --import --quit
godot --headless --path . --script res://tests/godot/machine_module_contracts_test.gd
godot --headless --path . --script res://tests/godot/manual_airlock_operation_test.gd
```

On this Windows workstation, the engine is in an extracted directory named `D:\Godot_v4.7.2-stable_win64.exe`. If it is absent from PATH, use its console executable:

```powershell
$godotExe = 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
& $godotExe --headless --editor --path . --import --quit
& $godotExe --headless --path . --script res://tests/godot/machine_module_contracts_test.gd
& $godotExe --headless --path . --script res://tests/godot/manual_airlock_operation_test.gd
```

The same checks run on GitHub-hosted Ubuntu and Windows Actions runners for pushes and pull requests. CI uses read-only repository permissions and does not require project secrets.

## Repository settings for PR enforcement

Workflow files define checks, but GitHub does not infer branch protection from them. After the initial `dev-master` branch is pushed and the checks have run, make `dev-master` the default branch, require pull requests for changes to it, and require these CI status checks:

- `PHP quality (PHP 8.3, ubuntu-latest)`
- `PHP quality (PHP 8.5, ubuntu-latest)`
- `PHP quality (PHP 8.3, windows-latest)`
- `Godot project import (ubuntu-latest)`
- `Godot project import (windows-latest)`

Also enable “Require branches to be up to date before merging” so checks apply to the latest integration branch. Branch protection is a repository setting and must be enabled by an administrator after the initial `dev-master` branch is pushed.
