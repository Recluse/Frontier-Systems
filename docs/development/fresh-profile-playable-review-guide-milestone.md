# Fresh-profile playable review guide

## Purpose and status

This is a reviewer-assisted procedure for launching the current Windows source playable from an isolated local profile and fresh named world. It gathers current launch commands, controls, finite engineering/inventory steps and save/restart behavior in one place. It is not the final player tutorial and does not establish tutorial readiness.

Automated injected acceptance and a human following this procedure answer different questions. The existing automated route drives the real client UI with injected input and fixture-selected controls. A human reviewer still needs to navigate the actual client using the instructions, note where help was needed, and judge whether the steps are understandable. No human run is recorded by this document.

## Before launch

- Use Windows, PowerShell and Godot 4.7.2. The source launcher defaults to `D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe`; pass `-GodotPath` when it is installed elsewhere.
- Start from a clean repository copy with no existing `override.cfg`. The readiness runner also requires that file to be absent. Do not replace an existing override.
- Choose a unique profile name and world name. The profile separates Godot's local preferences; the world name separates the host save under ignored `config/local/first-playable/worlds/<WorldName>`.
- Invite keys are separate from the Godot profile. `-Initialize` creates the ignored project-local keys only when they do not exist. Reuse the existing keys; do not overwrite them to simulate a fresh player profile.

In a PowerShell window at the repository root, prepare one isolated Godot profile. Keep this window open until the host and both clients have exited:

```powershell
$profileName = 'FrontierSystems-review-' + [Guid]::NewGuid().ToString('N')
$worldName = 'review-' + [Guid]::NewGuid().ToString('N')
$overridePath = Join-Path (Get-Location) 'override.cfg'
if (Test-Path -LiteralPath $overridePath) { throw 'Preserve the existing override.cfg and use a clean checkout.' }
$overrideText = "[application]`nconfig/use_custom_user_dir=true`nconfig/custom_user_dir_name=`"$profileName`"`n"
[IO.File]::WriteAllText($overridePath, $overrideText)
"Profile: $profileName`nWorld: $worldName"
```

The launcher stores invites and world checkpoints in the project-local ignored directory, so the unique world name is what makes the scenario fresh. The custom Godot profile isolates preferences. Neither identifier contains a credential.

## Launch the source playable

Open three PowerShell windows at the repository root. In the host window, assign the exact world name printed during setup; this window keeps the variable for the later restart:

```powershell
$worldName = Read-Host 'Paste the exact World value printed during setup'
if ($worldName -notmatch '^review-[0-9a-f]{32}$') { throw 'Use the exact generated review world name.' }
```

No port lease has been granted and no human run has been performed as of this revision. Request and receive an exclusive lease for port 27840 from Coordinator before launching any host. The listener probe below is an additional fail-fast safety check; it does not acquire or confirm a lease. If a process already listens on the port, stop and contact Coordinator; do not terminate it:

```powershell
function Assert-CoordinatorPortAvailable {
    $listeners = @(Get-NetTCPConnection -State Listen -LocalPort 27840 -ErrorAction SilentlyContinue)
    if ($listeners.Count -gt 0) { throw 'Coordinator-reserved port 27840 already has a listener. Stop and contact Coordinator; do not terminate it.' }
}
Assert-CoordinatorPortAvailable
./tools/launch-first-playable.ps1 -Mode Host -Initialize -WorldName $worldName
```

Initialize invite keys only if this project has not initialized them before. Keep the host PowerShell window open so the same `$worldName` and port-check function are available for restart.

In the second and third windows, start each crew client:

```powershell
./tools/launch-first-playable.ps1 -Mode Client -Slot 1
```

```powershell
./tools/launch-first-playable.ps1 -Mode Client -Slot 2
```

The launcher starts `scenes/first_playable.tscn`; host mode is headless. Both clients connect to the loopback host at `ws://127.0.0.1:27840` by default. Use the first client for the walkthrough. Leave the second client available for a separate crew-body check if useful; it is not required for the finite loop. Do not expose the host publicly as part of this review.

The launch contract is in [`launch-first-playable.ps1`](../../tools/launch-first-playable.ps1). `-CheckOnly` prints the resolved launch arguments and save directory without generating keys, writing saves or starting Godot.

## Reviewer-assisted finite loop

Read the in-client **Controls** help before starting and use the labels shown there. Default bindings are listed below only as a convenience; **Settings** (F10) can remap them and the help reflects current bindings. If mouse focus is captured, hold Left Alt to interact with UI; Escape releases camera capture. WASD moves, Space jumps and Shift sprints. F1/F2/F3 select first-person, third-person and overview cameras. I opens Inventory; X changes the active hand; F uses the active tool.

1. In **Overview**, locate the Iron ore deposit and workstation, then select a comfortable camera view. Approach the ore with the movement/look controls.
2. Use the visible collection guide to collect its requested finite iron in two 1 kg actions into the carried canister. Read the on-screen response and wait for each action to finish before continuing. Do not assume an action succeeded while it is pending or after a rejection.
3. Return to the workstation and follow its guide to unload the 2 kg and complete two refining batches. Wait for each batch to finish; the guide is session assistance, not a saved achievement.
4. Follow the workstation guide to print a plate, collect it as a physical inventory item, recycle it, and print again. Then collect the reprinted plate too. In Inventory, wait for the updated host observation and confirm that the reprinted 1 kg plate is actually owned before continuing; printing alone does not establish that it is in your inventory. Confirm the guide reaches its seven completed stages.
5. Open **Inventory** to inspect carried items and the two hands. Select an owned item before using **Equip** or **Switch hand**; the **Make selected hand active** and visible storage/tray controls operate on observed selections. Wait for the updated observation and matching result before treating an equip, switch or transfer as complete.
6. The base loop extracts 2 kg ore and refines two 1 kg batches into 1.2 kg iron. Printing a 1 kg plate, recycling it, then printing again leaves 0.2 kg iron and one reprinted 1 kg physical plate. If the updated Inventory observation confirms you own that plate, open **Construction**, choose **Place a new wall**, select the observed owned plate, set a valid floor target, and use **Build wall from selected physical plate**; one wall consumes that 1 kg plate. Select the observed wall and use **Remove selected wall and recover plate**; recovery returns the plate for a rebuild if it remains observed and prerequisites still hold. The optional canister blueprint costs 1 kg iron and 1,000 J. The base loop leaves only 0.2 kg iron, so fabricate it only after gathering and refining two additional 1 kg ore batches (600 g iron each) and confirming the observed energy requirement; one extra batch is insufficient. Stop if finite deposit mass, materials, energy or another observed prerequisite is unavailable, or if the host rejects the action, and record the exact reason. Do not treat the base loop as proof that these optional actions are available.

The base loop's quantities and guide stages are described in [`first-playable-running.md`](first-playable-running.md). The current inventory and equipment controls are summarized in its player-inventory section and the [player inventory UI contract](../architecture/player-inventory-ui.md). The injected PR46 route exercised visible fabrication and wall build/remove/rebuild buttons, but chose selectors and wall coordinates in the fixture; a human using these controls is still needed. This procedure is an evaluation aid, not a substitute for fresh unaided discovery: reviewers should log every prompt, rescue hint or step whose target/action was unclear.

## Save, disconnect and restart

At the workstation, activate **Save shared world now** and wait until the client reports **Shared world checkpoint confirmed on disk.** That message follows host disk completion. Do not treat a pending request or a client-side display alone as a durable save.

Close both client processes, then stop the host cleanly. Restart it using the exact same world name and keys:

```powershell
Assert-CoordinatorPortAvailable
./tools/launch-first-playable.ps1 -Mode Host -WorldName $worldName
```

Restart the clients with their corresponding slots and confirm they reconnect to their persistent crew bodies. Recheck deposit depletion, inventory items, printed output and any construction state exercised during the session. The source launcher uses the same `config/local/first-playable/worlds/<WorldName>` directory for that name. Periodic checkpoints run every five seconds, so work after the last completed checkpoint can be lost if the host stops unexpectedly. See [first-playable save and restart details](first-playable-running.md#save-and-restart) for alternating checksummed checkpoint behavior and its limits.

After all three processes have exited, report the review session ended to Coordinator and request release of the exclusive port lease. Do not assume the lease was released automatically. Then remove only the `override.cfg` created by this procedure:

```powershell
if (Test-Path -LiteralPath $overridePath) { Remove-Item -LiteralPath $overridePath }
```

The ignored review world and profile may be retained for follow-up or removed separately after confirming the exact generated names. Do not delete the shared invite file or another user's profile/world.

## Evidence map and limits

### Research documentation import boundary

`docs/research/.gdignore` keeps the machine-readable research CSVs out of Godot's resource import pipeline. They are documentation inputs, not runtime resources or localization tables. The documentation validator at [`check-foundational-capability-matrix.ps1`](../../tools/ci/check-foundational-capability-matrix.ps1) reads the CSVs directly from the checkout, so this exclusion does not prevent matrix or reference-manifest validation.

Before adding the exclusion, the source and test search found no references to the research CSVs or `docs/research` resources. The generic dynamic document loader is used by overlay controllers with built-in paths under `res://data/overlays`, and mod/settings paths under `user://overlay-*`; no caller targets `docs/research`. This folder therefore has no identified runtime or test resource dependency.

The exclusion addresses repeated CSV import failures observed during PR47/PR49 CI investigations. PR49's first import attempt terminated with allocator corruption while reimporting the capability matrix CSV, while its second attempt on the same source revision passed. That pattern makes avoiding an unnecessary Godot import plausible mitigation; it does not establish the allocator failure's root cause.

| Procedure claim | Existing evidence | What that evidence does not establish |
| --- | --- | --- |
| Source launch, two crew slots, loopback host, profile/world separation and save directory | [`launch-first-playable.ps1`](../../tools/launch-first-playable.ps1), [`first-playable-running.md`](first-playable-running.md) | A successful launch on this reviewer's machine or a public/network deployment |
| Default controls and live help labels | [`player_controls.gd`](../../src/presentation/input/player_controls.gd), [`first_playable_controls_help.gd`](../../src/presentation/input/first_playable_controls_help.gd), [controls contract](../architecture/player-controls.md) | That a human can discover or comfortably use those controls |
| Finite collection, refining, plate collection/recycling/reprint guide stages | [`first_playable_task_guide_test.gd`](../../tests/godot/first_playable_task_guide_test.gd), [`first_playable_client_render_check.gd`](../../tests/godot/first_playable_client_render_check.gd) | Human pointer/keyboard navigation or unaided instruction clarity |
| Inventory, hands, storage and matching rejection/retry behavior | [`client-inventory-hand-verification.md`](client-inventory-hand-verification.md), [`client_inventory_shell_test.gd`](../../tests/godot/client_inventory_shell_test.gd) | Physical human input or a tutorial pass |
| Current actual-client finite engineering, save acknowledgement and restored reconnect assertions | [`client_ui_acceptance_render_check.gd`](../../tests/godot/client_ui_acceptance_render_check.gd), PR46 final head `6325f4693b30f35281adc2e7f3d9b95686da03f4` | Human-operated save/reconnect, general usability or readiness to publish a tutorial |

The PR46 actual-client route used injected keyboard/GUI activation and a fixture-created host/persistence adapter. It verified the real client UI, finite construction/equipment state, visible save acknowledgement, disconnect clearing and restarted-host state restoration. It did not ask a human to follow instructions. The separate human tutorial gate remains unperformed.

## Reviewer notes and failure report

Use this text template for a human run. Keep it in the review notes; this milestone creates no capture, video or public media.

```text
Date/time and reviewer:
Source commit / branch:
Godot version / renderer / display size:
Fresh profile name / world name (no credentials):
Crew slot(s) used:

Step | Result (pass / blocked / unclear) | Exact visible response | Help needed or guess | Reproduction notes
Launch and spawn:
Controls help / movement:
Finite collection (1 kg action 1 and 2):
Unload and refining batches:
Print / collect / recycle / reprint:
Inventory / hands / storage:
Construction extension (if attempted):
Save acknowledgement:
Disconnect / same-world restart / restored state:

First point where progress stopped:
Expected versus observed:
Exact rejection or error text:
Was the action pending, accepted, rejected, or outcome unknown:
State that changed or did not change:
Can the same issue be reproduced from a fresh profile/world:
Human tutorial acceptance: not assessed / pass with evidence / fail with evidence
```

Do not convert injected acceptance into a human pass, or a successful run by one reviewer into a general tutorial-readiness claim. This milestone does not write final tutorial copy, record/edit media, clear publication rights, or publish anything.
