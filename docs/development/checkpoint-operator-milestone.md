# Checkpoint operator milestone

Operators can enable bounded local backup history at host startup and explicitly inspect/recover it while the source host is stopped. This integrates the existing [history contract](checkpoint-history-milestone.md) and [recovery contract](checkpoint-recovery-milestone.md); their storage names, checksums, limits, source-path guards and domain validation remain authoritative.

## Opt-in host configuration

History remains disabled by default. The PowerShell launcher accepts host-only options:

```powershell
./tools/launch-first-playable.ps1 -Mode Host -BackupHistory -BackupEntries 3 -BackupBytes 33554432
./tools/launch-first-playable.ps1 -Mode Host -BackupHistory -BackupEntries 8 -BackupBytes 67108864 -CheckOnly
```

Enabling without explicit limits uses three entries and 32 MiB. Explicit limits require `-BackupHistory`; counts are 1-8 and retained bytes 1-67108864. Values must be canonical decimal integers, without fractional, signed or zero-padded forms. Client history options reject. `-CheckOnly` reports the effective policy without keys, storage writes or starting Godot.

Native hosts on Windows/Linux can set both `FRONTIER_BACKUP_ENTRIES` and `FRONTIER_BACKUP_BYTES` before starting `scenes/first_playable.tscn -- --host`. Both empty means disabled; one missing or either malformed fails startup with exit 2 before persistence configuration or a listener. The launcher scopes these two variables to its child, explicitly disables inherited history settings when opt-out is selected, and restores the caller's previous values.

The policy is passed to `WorldPersistenceAdapter.configure`, which already detaches it into bounded checkpoint work. Autosave remains five seconds and storage stays on its existing worker. Host output reports policy admission, active checkpoint acknowledgement, and the separate backup sequence/error code. Backup failure never changes an active success into failure or changes network status.

## Explicit local inspection and recovery

Stop the source host before recovery and keep it stopped until recovery finishes. One operator/writer owns a save directory; this helper does not acquire a cross-process filesystem lock or prove that another host has exited. Read-only listing may run while a host exists, but a descriptor is a point-in-time selection and is always revalidated.

Use the pinned executable (or your full Godot 4.7.2 executable on Linux). Import the source project once after checkout or rebase with `--headless --editor --path . --import --quit` before invoking scripts. All CLI paths must be absolute. The command has at most seven arguments, each limited to 4096 UTF-8 bytes. The engine may print its startup banner; the helper prints exactly one JSON report.

```powershell
$engine = 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
$source = Join-Path (Get-Location) 'config/local/first-playable/worlds/main'
& $engine --headless --xr-mode off --audio-driver Dummy --path . --script res://tools/godot/checkpoint_operator.gd -- list --source $source
```

Listing returns only `candidates` (slot, sequence, tick, checksum, world/region identity and bytes) and `rejected` (slot and reason code), even when some entries are rejected. It scans the existing fixed-name nine-entry history surface. No raw snapshot, parser input, invite keys or file paths are printed. A missing source rejects; an existing source without history returns an empty list.

Copy **one complete candidate object**, with exactly its seven fields, into a private local JSON descriptor file. This deliberate step chooses the backup: a list report, slot number alone, or a request for “latest” is not a selection. The descriptor must be at most 4096 bytes.

```powershell
$descriptor = 'D:\Private\selected-checkpoint.json'
$destination = Join-Path (Get-Location) 'config/local/first-playable/worlds/recovered1'
& $engine --headless --xr-mode off --audio-driver Dummy --path . --script res://tools/godot/checkpoint_operator.gd -- recover --source $source --descriptor $descriptor --destination $destination
# After exit 0, explicitly start the recovered world with the existing private keys:
./tools/launch-first-playable.ps1 -Mode Host -WorldName recovered1
```

The helper initializes a disposable first-playable world with the same resource-carrier setup as host startup, leaves simulation stopped, and disables adapter processing. It calls `configure_from_backup` with the exact descriptor and no history policy. That owner rejects running/previously started/queued worlds, configured adapters, existing destinations and destinations inside the source tree. It re-reads all selected metadata, validates identity/system/cross-system domain records, and seeds only a new destination at active sequence 1 while preserving the captured tick. There is no fallback if the selection changes, disappears or fails validation.

Recovery never starts a listener or simulation and does not modify source active slots/history. Future host startup into the destination uses normal active-slot recovery; history is still opt-in for that host. On failure, discard the CLI's startup world. Preserve any partial destination evidence and choose another absent destination for a retry. Never start a failed recovery world. The helper does not delete failed seeds, corrupt entries or source evidence.

## Exit status and diagnostics

| Exit | Meaning |
| --- | --- |
| 0 | Inspection without rejected entries, or successful explicit recovery seed |
| 2 | Invalid action, flags, duplicate/missing options, relative/oversized paths, or host history configuration |
| 3 | Inspection has rejected entries/source failure, or descriptor cannot be read/parsed within its bound |
| 4 | Selection changed, recovery precondition/domain validation rejected, or destination seed failed |

Every JSON report includes `exit_status`; failures include an existing stable `error_code` and fixed readable guidance. Parser/source/seed input is never interpolated into diagnostics. Inspection exit 3 can still carry valid selectable candidates; the report's rejected reasons remain visible. Recovery success reports only source sequence, new sequence and restored tick. Active save/backup diagnostics are local console output, outside game UI and network messages.

## Ownership, failure and verification

`WorldRuntime` remains canonical state owner and validates startup restore. `CheckpointOperator` owns only bounded configuration parsing and detached metadata reports; `tools/godot/checkpoint_operator.gd` owns the CLI's disposable startup world/adapter lifetime. No simulation tick invokes operator storage work, and no persistence/schema/terrain/production/network contracts change. Existing snapshot v1 and autosave/profiling signals remain intact; operator outcomes are separate local diagnostics.

Reusable verification:

```powershell
./tools/ci/run-godot-checks.ps1 -Godot 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' -TestNames 'checkpoint_operator_test.gd','checkpoint_history_test.gd','checkpoint_recovery_test.gd','control_runtime_recovery_test.gd','sustained_extraction_test.gd' -OutputDirectory 'var/ci/checkpoint-operator-final'
./tools/ci/test-checkpoint-operator.ps1 -Godot 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
# Reserve port 27849 through the Coordinator's live reservation file first:
./tools/ci/run-godot-checks.ps1 -Godot 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' -TestNames 'first_playable_acceptance.gd' -OutputDirectory 'var/ci/checkpoint-operator-acceptance'
```

Operator tests use disposable directories and injected seed I/O. They cover opt-out, min/max/invalid options, exact descriptor selection, metadata replacement between listing/recovery, rejected entries without raw data, descriptor size/parser bounds, source/destination preservation, running/previously started/configured/identity rejection, failed seed, nonzero-tick success, and distinct readable diagnostics. The native launcher/CLI checker uses check-only launch configuration and an empty temporary source, with 30-second child deadlines; it verifies real process exits and JSON for 0/2/3/4. Existing history tests retain deeper queued-world and domain/system/worker failure coverage.

CI discovers the native Godot test and runs the PowerShell CLI checker on Windows and Linux. Exact final SHA, rebase baseline, local JUnit results and remote CI are reported on draft PR #8. Graphical, VR/controller, hardware power-loss, real save manipulation, live services, packaged local verification, journal/SQL, upload, automatic rollback, merging and deployment are outside this milestone.