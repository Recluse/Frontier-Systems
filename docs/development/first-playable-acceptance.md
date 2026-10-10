# First playable acceptance evidence

> Revision scope: these results precede the subsequent player inventory UI, handheld extractor and 1080p layout update. That update has editor import/script parsing evidence only; gameplay acceptance should be rerun when requested.

Verified on **2026-10-10**, Windows, Godot 4.7.2. This milestone is a two-player runnable source prototype. It is not a packaged Steam release.

## Automated cooperative acceptance

Run from the repository:

```powershell
& 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --headless --xr-mode off --path . --script tests/godot/first_playable_acceptance.gd
```

Result: exit 0. The test uses real TCP/WebSocket connections and checks:

- Two authenticated invites control distinct persistent bodies; invalid authentication is rejected.
- Observations expose each player's own cargo; foreign carrier access fails.
- Movement reaches the source and returns to the workstation through bounded host commands.
- Two extraction requests against the same revision have exactly one winner. An overfull canister cannot accept more material.
- Missing inputs and unpowered processing are rejected. A power outage pauses reserved work; cancellation returns exactly the reserved feedstock without refunding energy.
- Two refining batches, plate printing, physical item collection and recycling preserve the closed resource budget.
- A snapshot containing a physical plate retains its identity and payload after restore.
- Remote save acknowledgement follows worker completion; a corrupt alternate slot falls back to the valid checkpoint.
- An active batch survives restart and completes once. Reconnecting to the replacement host retains depletion and output.
- Replaying a retained extraction request after restart returns its receipt without extracting again.

Final log: `FIRST PLAYABLE ACCEPTANCE: two authenticated clients, scoped cargo, competing extraction, refinement, physical crafting/recycling, checkpoint and restarted batch passed.`

## Graphical route

```powershell
& 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --xr-mode off --path . --script tests/godot/first_playable_client_render_check.gd
```

The check drives local CharacterBody physics to the ore source and back, invokes the authenticated guide actions, completes all seven stages, then collects and drops a physical plate. Screenshot: [client.png](../../reports/first-playable/client.png). Both Compatibility/OpenGL and Forward+/D3D12 ran successfully on an RTX 3080 Ti. Separate host and client processes also authenticated successfully as crew one and crew two.

## Regression coverage and limits

The focused inventory_runtime_test, self_inventory_runtime_test, world_inventory_runtime_test, inventory_consciousness_test, control_runtime_recovery_test and health_runtime_test suites passed on Windows during this milestone work. They are regression evidence, not proof of all planned gameplay.

Windows/Ubuntu CI includes the cooperative acceptance check; the remote Linux workflow has not been run locally. No independent human usability study, Quest 3 verification, public TLS deployment, Steam identity flow, stress benchmark or standalone export was completed for this milestone. Detailed movement collision authority remains future work. Checkpoints may lose activity since the last completed save after abrupt termination.
