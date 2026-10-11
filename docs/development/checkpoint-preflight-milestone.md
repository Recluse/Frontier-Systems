# Checkpoint recovery preflight milestone

Operators can validate one explicitly selected backup before choosing or creating a recovery destination. The bounded `preflight` action reuses the [history selection](checkpoint-history-milestone.md), [startup recovery](checkpoint-recovery-milestone.md) and [operator CLI](checkpoint-operator-milestone.md) contracts. It performs the same descriptor, identity, domain and cross-system validation as recovery in a fresh stopped disposable world.

## Operator procedure

Stop the source host and keep it stopped throughout preflight and recovery. Import the project after checkout with `--headless --editor --path . --import --quit`. Use the pinned Godot 4.7.2 executable on Windows or Linux. List history with the existing `list` action, then copy exactly one complete seven-field candidate object into a private descriptor JSON file. Neither a slot alone nor an instruction to select the latest backup is accepted.

```powershell
$engine = 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
$source = Join-Path (Get-Location) 'config/local/first-playable/worlds/main'
$descriptor = 'D:\Private\selected-checkpoint.json'
& $engine --headless --xr-mode off --audio-driver Dummy --path . --script res://tools/godot/checkpoint_operator.gd -- preflight --source $source --descriptor $descriptor
```

`preflight` accepts exactly `--source` and `--descriptor`, each once; both paths must be absolute and at most 4096 UTF-8 bytes. Destination flags, omitted/duplicate flags and relative paths reject with exit 2. Descriptor reads retain the 4096-byte bound. The fixed history scan and selected-envelope re-read retain existing nine-entry, 16 MiB envelope and 8 MiB snapshot bounds. Integral JSON metadata normalization and full exact-descriptor comparison remain in the existing operator/selection boundary.

The helper restores the selected snapshot through `WorldRuntime` into its fresh initialized stopped world. It validates world/region identity, catalog/system records, migrations and cross-system ownership links using the same restore owner as recovery. It never seeds/configures storage, creates a destination, writes/removes/promotes source files, runs simulation or starts a listener. Adapter durable acknowledgement remains unset. The disposable world is discarded after success or failure; a populated preflight world must never be used as a running host.

Success prints one bounded JSON report with `exit_status: 0`, `action: preflight`, original `source_sequence`, restored `tick_number` and fixed guidance. It prints no raw snapshot, descriptor input, file paths or keys and makes no destination sequence/durable acknowledgement claim. Exit 3 means descriptor read/parse failure; exit 4 means selection/precondition/domain rejection, with the existing stable error code and fixed guidance. Nonzero captured ticks are valid. No backup is silently substituted when the chosen descriptor changes, disappears or becomes corrupt.

Success describes only the bytes re-read and validated during this invocation. This is no cross-process lock or proof that another host exited. Recovery must revalidate the same explicit descriptor, and may still reject changed storage or fail while writing its fresh destination. Preflight does not reserve a destination or prove destination write permissions, free space, hardware durability, future startup success, or external exclusivity.

## Shared implementation and verification

`WorldRuntime` remains canonical state owner. `WorldPersistenceAdapter` shares `_backup_startup_ready` and `_restore_backup_selection` between `preflight_from_backup` and `configure_from_backup`; destination checks/seeding remain exclusive to recovery. The operator owns bounded parsing and detached reports; the existing CLI owns disposable world/adapter lifetime. There are no bootstrap, terrain, machinery, network/schema, cadence, or storage-format changes.

```powershell
./tools/ci/run-godot-checks.ps1 -Godot 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' -TestNames 'checkpoint_preflight_test.gd','checkpoint_operator_test.gd','checkpoint_history_test.gd','checkpoint_recovery_test.gd','control_runtime_recovery_test.gd' -OutputDirectory 'var/ci/checkpoint-preflight-final'
./tools/ci/test-checkpoint-operator.ps1 -Godot 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
```

After a clean rebase onto `origin/dev-master` at `59613f1a17e3b78d244572713da0557cd8bbb5e4`, Windows Godot 4.7.2 verification passed all seven final checks: import, startup, preflight, operator, history, checkpoint recovery and control-runtime recovery. The native CLI checker also passed. Exact head/PR/remote CI are reported with draft PR #10. Logs/JUnit remain under ignored `var/ci/checkpoint-preflight-focused` and `var/ci/checkpoint-preflight-final` and `var/ci/checkpoint-preflight-rebased` in the managed worktree.

The dedicated test uses disposable storage and injected read-only I/O that fails/counts directory creation, writes, removals and promotions. It covers valid nonzero ticks, unchanged durable status, no destination, missing/corrupt/replaced selections, replacement between scanning and re-reading, codec-valid identity/domain/cross-system rejection, running/previously started/configured guards, argument/descriptor bounds and safe diagnostics. Raw byte trees compare every source filename and byte before/after success and rejection, including unknown files and uncommitted staging. The native PowerShell checker verifies real preflight process exits 2/3/4 and one JSON report; successful restoration is verified through the operator/helper in the dedicated Godot test.

The existing Windows/Linux CI discovers the dedicated test and runs the extended native checker without workflow changes. Local Linux, graphical, live service, real save, device power-loss and packaged local acceptance are outside local evidence. No verification images were supplied or generated, so no docs/gallery or Git LFS additions or graphical claims are made. This implementation chat does not merge or push dev-master.
