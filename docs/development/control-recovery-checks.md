# Circuit and maintenance recovery checks

`tests/godot/control_runtime_recovery_test.gd` exercises world composition, commands and JSON restoration. It disables automatic physics scheduling and advances individual runner ticks to check exact boundaries. Direct component changes are limited to controlled damage/power-loss fixtures.

```powershell
& 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' `
  --headless --path . --script res://tests/godot/control_runtime_recovery_test.gd
```

Covered scenarios:

- Optional alarm installation and two-destination saved pulse fanout.
- Remote alarms retain their state, disabled alarms reject activation, and a broken alarm leaves the latch functional.

- Receiver pulses actuate on the next tick and resume exactly once after JSON restore.
- Duplicate/future deliveries and missing reserved boards reject restoration without changing any system.
- Power loss drops due pulses without unlocking.
- Maintenance requires isolation; smaller boards cannot discard utility modules.
- Salvage and reinstallation preserve damaged part identity and integrity.
- Installed/salvaged identity overlap rejects a save.
- Saved board progress stays paused until the initiating actor resumes.
- Board exchange completes at 180 work ticks and returns the old board as a reusable spare.
- Loss of isolation pauses work; cancellation retains both boards despite lost hardware prerequisites.
- Profiling rings return detached, ordered windows with correct nearest-rank statistics.

The local profiling launcher now checks successful fixture ingestion, retained-receipt retries, bad credentials, malformed captures, wrong scope, oversized payloads and stale-frontier rejection. The Godot upload test checks concurrent submission backpressure. Both suites are configured in Windows/Ubuntu CI and passed locally on Windows Godot 4.7.2 with PHP 8.5. Linux CI execution remains pending.

These checks do not establish production multiplayer authentication, global inventory correctness, material consumption, actor reach, durable database commits, full pressure physics or long-duration load behavior.
