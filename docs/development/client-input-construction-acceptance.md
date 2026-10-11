# Actual-client input, construction and recovery acceptance

Successor to tutorial readiness PR #35. Draft PR #38 targets `dev-master`; base `cc25426897afb8ea44e34f4b803b2fa686b8f35e`. Tests and bounded tooling only; no runtime, authority, schemas, persistence contracts, PlayerInventoryPanel or HabitatTargetFeedback changes. One agent. No merge, deployment, dev-master push or media publication.

**Tutorial gate remains not met.** Automated native-renderer acceptance does not establish physical keyboard/mouse input, discoverability, pointer selection or unaided fresh-user acceptance.

## What the new routes exercise

`client_input_render_check.gd` sends `Input.parse_input_event` events through actual handlers and keeps `read_local_keyboard=true`. It verifies held-W physics, mouse yaw/pitch, RMB capture, Alt handoff/movement suppression/recapture, Escape, focus-loss notifications and recapture, rebinding suppression and canonical-state immutability. It then builds the actual client without connecting (empty invite fails validation before socket use) and activates its visible camera button by focused Enter, walks the nested viewport character, and opens Inventory/Settings by hotkeys. Focus loss is an injected notification, not an OS window switch. Headless Godot cannot support captured mouse mode; both new graphical routes are explicitly excluded from the headless runner.

`client_ui_acceptance_render_check.gd` authenticates the actual client against a fresh temporary host. It steers by injected mouse motion and held keyboard events, uses focused Enter on visible enabled/scrolled buttons, and requires command acknowledgement. It completes the seven-stage guide through the guide **button**, rather than calling the guide method; extracts/refines another two kilograms; fabricates a canister; builds, removes/reclaims and rebuilds a physical wall; clicks Save and checks the displayed disk acknowledgement. It observes real disconnect clearing, restores the host from the durable store, and creates a replacement actual client through normal startup authentication. Depletion, world walls, equipment structures, inventory items and workstation stock must match before/after. It checks exactly four kilograms of finite ore consumed (10 kg to 6 kg).

Selector choices, tab selection for engineering, wall selection/coordinates and restart are injected fixture setup. No pointer/world-picking acceptance, inventory equip/handoff acceptance, user-operated host restart or reconnect-button claim. The client currently has no reconnect button. The guide permits at most three stale-revision retries via its visible button after a newer observation; it does not relax host checks or create resources. Other UI command rejections fail the route.

## Reproduce automated checks

Use a clean isolated source worktree at the chosen commit with Godot 4.7.2. All native captures/logs/manifests remain ignored under `var/ci/`; custom user profiles are unique and retained locally for review. The wrapper refuses an existing `override.cfg`, restores capture configuration, and records source HEAD plus dirty-tree status. The graphical runner restores telemetry environment variables and never sends live telemetry. No imported creative assets or generated artwork are used; any screenshot is ordinary Godot rendering of existing first-party MIT content.

```powershell
# No listeners or reservation needed for actual-handler/native client input.
./tools/ci/run-tutorial-readiness-checks.ps1 -Godot 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' -InputOnly

# Only after Coordinator grants 27849/27850; probes never replace listeners.
./tools/ci/run-tutorial-readiness-checks.ps1 -Godot 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' -PortsReserved

# Reuse passed input/runtime checks after an isolated client fixture correction.
# Requires the Coordinator lease for 27850 only.
./tools/ci/run-tutorial-readiness-checks.ps1 -Godot 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' -ClientOnly -PortsReserved
```

`-PortsReserved` asserts an existing lease; it does not acquire one. Each route is process-bounded, with shorter observed-state waits. World/checkpoint/retry paths are temporary. Remove only the exact retained profile after review, never its parent or a real player's directories. Captures/videos are internal local evidence, never staged, added to galleries/LFS or uploaded.

## Completed versus pending evidence

Windows Godot 4.7.2, Compatibility/OpenGL 3.3, RTX 3080 Ti. Source checkout only. Native input route passed after checking the actual nested client viewport. Existing bounded import/startup, controls help, task guide, character navigation and cooperative acceptance passed: six checks, zero failures; cooperative acceptance 36.71 s. Their ignored manifest/runtime reports are in `var/ci/tutorial-readiness/4579bc9cd44742b9a76ea2bec14590fe/`.

Client route passed after fixture fixes for asynchronous UI refresh, scroll/focus visibility and explicit ore selection. Ignored evidence: `var/ci/tutorial-readiness/914c5a98392f4765890e1d07b7f047d0/` (manifest, stdout/stderr and capture). These iteration runs used a dirty working tree at `193fb0c`; final committed-head evidence is recorded in the PR handoff. A green parse/import check alone does not establish graphical execution. Linux graphical, physical input, controller, VR, packaged builds and human acceptance remain unverified.

Initial reservation messaging was rejected by automatic approval review: it did not recognize the delegated transcript as explicit human authorization to message Coordinator. No bypass was attempted. Coordinator subsequently granted the exclusive recorded 27849/27850 lease directly; local socket tests started only after that grant and immediate probes.

## Reproducible fresh-profile human acceptance checklist

This is a pending acceptance procedure, not final tutorial instructions. A reviewer must operate the physical keyboard/mouse without script/console commands for gameplay. Record exact HEAD, engine/OS, resolution, controls defaults, reviewer, start/end time, pass/fail and assistance for each row. Stop and record a blocker if any action is undiscoverable, clipped, rejected without recoverable feedback or requires unshown resources. Do not mark a row passed based on this automated route.

Prepare a separate clean worktree at the chosen reviewed HEAD, with no real `config/local` or profile copied in. Reserve launcher port **27840** with Coordinator separately (27849/27850 does not cover it). Before launching any process, fail if `override.cfg` exists, then use this setup once in PowerShell:

```powershell
$acceptanceId = [Guid]::NewGuid().ToString('N')
$acceptanceWorld = "human-$acceptanceId"
$acceptanceProfile = "FrontierSystems-human-$acceptanceId"
if (Test-Path -LiteralPath override.cfg) { throw 'Preserve existing override; choose a clean worktree.' }
$acceptanceConfig = "[application]`nconfig/use_custom_user_dir=true`nconfig/custom_user_dir_name=`"$acceptanceProfile`"`n"
[IO.File]::WriteAllText((Join-Path (Get-Location) 'override.cfg'), $acceptanceConfig)
git rev-parse HEAD
$acceptanceWorld # Record this temporary world name, no keys.
```

Start the existing launcher from that worktree in separate terminals, replacing `human-<id>` with the recorded world name. Host: `./tools/launch-first-playable.ps1 -Mode Host -Initialize -WorldName human-<id>`. Client: `./tools/launch-first-playable.ps1 -Mode Client -Slot 1`. Keys remain in that worktree's ignored local config. The host has a fresh named world; the client uses the fresh custom profile. Keep the same world/keys/profile for recovery.

| Physical reviewer action | Required observation |
| --- | --- |
| Spawn, identify crew body; choose First/Third person | Correct body and camera; no prior saved world/preferences |
| Hold RMB, walk WASD, sprint, jump and look; change cameras | Expected motion/collision, camera orientation and release; legible controls |
| Hold Alt, operate UI, release Alt with RMB held; Escape; switch OS focus away/back | UI cursor works, movement pauses during handoff, no stuck walking/capture; fresh RMB recovers |
| Open I/F10/help; Tab/Shift+Tab, Enter and focused scrolling | Correct tabs/focus and readable reachable controls; gameplay does not consume UI activation |
| Pointer-select ore and intended world targets; try from too far, then approach | Correct stable target and clear authoritative rejection/retry; no reach bypass |
| Extract 1 kg twice, transport, unload ore, refine twice | Deposit 10 kg to 8 kg; cargo/shared stock distinguishable; wait for real completion |
| Print/collect/recycle/reprint a plate | Seven guide stages; no duplicated material; physical inventory item |
| Gather/refine two more kilograms; select/fabricate resource canister | Deposit 6 kg; paid 1 kg shell appears as owned equipment, prerequisites visible |
| Inventory: inspect/equip carried tool, switch active hand, inspect canister/storage | Accurate visible identity/mass/slots; hand/tool feedback; no fixture selection |
| Select plate, choose clear floor wall location, build; pointer-select/remove; recover plate and rebuild | Native wall placement/targeting/collision and retained recovered material; rejection/retry readable |
| Click Save and wait for disk acknowledgement | Explicit disk confirmation, not queued/busy text alone |
| Operator stops only this host; client observes disconnect; restart same host/world and client | Same depletion, cargo, item IDs, wall/equipment and stock; no unexpected reset or duplication |
| Repeat from another fresh profile/world using only reviewed instructions | Record assistance and blockers; this is the remaining human tutorial gate |

After all processes exit, confirm 27840 is no longer listening and report lease release to Coordinator. Remove only the setup's `override.cfg`, retain exact local evidence/profile until reviewed, and do not publish media. Human result fields remain **not performed** until a reviewer completes this procedure. No final tutorial video or public readiness claim is authorized by automated success.

## Integration follow-up after PR #41/#42

Updated from `origin/dev-master` at `2036a8e`. Preserve the upstream detached `production-navigation` capture route and observed guide behavior. The acceptance fixture now searches only the intended panel's button descendants, requires exactly one matching title, and selects the containing workstation task section through its navigation control before checking visibility/focus and activating Enter. No imported runtime or panel changes were edited by this successor.

Focused Windows import/startup, `production_panel_navigation_test` and `first_playable_task_guide_test` passed (four checks, zero failures); the updated graphical fixture passes Godot check-only compilation. Earlier input/runtime evidence is reused within its original scope. A fresh 27850 Coordinator lease is requested here; the recorded reservation currently has no holder and does not grant a lease. Updated native finite-loop/recovery acceptance remains pending that grant. Exact final-head execution evidence belongs in the PR handoff; the previous native pass does not establish compatibility with grouped controls.
