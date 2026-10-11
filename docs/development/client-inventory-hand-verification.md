# Actual-client inventory and hand verification

## Scope and acceptance

This successor starts from integrated PR38/PR43 at `71c7052673b194c5dfaa5fc67517ef14f1428280`. It verifies presentation over existing inventory authority: owned tool equip, active-hand switching, storage transfer, matching rejected-command feedback, explicit retry and item/material conservation. No tutorial readiness, physical human input, world picking, controller or VR acceptance is implied.

The canonical owner remains `InventorySimulationSystem` and its shared coordinator at fixed ticks; UI nodes render detached observations and submit existing commands. Inventory v4, existing principal/body ownership, revision validation and bounded receipts remain unchanged. Failed requests must conserve state; successful operations relocate one item without duplication. Matching pending command IDs and revisions must control rejection/receipt reveal. External callbacks do not mutate canonical state.

## Ordered verification

1. Obtain an exclusive Coordinator lease for loopback 27850. A null reservation holder is not a grant. Re-probe before binding; never stop another chat's listener.
2. Reuse the unmodified PR38 `run-tutorial-readiness-checks.ps1 -ClientOnly -PortsReserved` on the integrated baseline to check PR43 focus/receipt interaction. Capture ignored native output and immutable source revision; preserve profile isolation and cleanup.
3. Extend a dedicated inventory/hand fixture using the real client shell and injected external-effect adapter. Exercise GUI event activation, owned-tool equip, hand changes and transfer; separately identify fixture-selected controls and injected observations. Verify matching rejection/retry feedback and exact before/after canonical item/material conservation.
4. Run only affected versioned checks. Inspect native captures internally. Commit/push the final feature head and report exact CI and graphical evidence; no gallery, upload, deployment or merge.

## Current status

Managed worktree: `C:/Users/valza/.codex/worktrees/client-inventory-hand-verification/Frontier Systems`.
Branch: `client-inventory-hand-verification`, targets `dev-master`.

**Lease completed:** Coordinator granted exclusive 27850 at 2026-10-11T07:01Z. The integrated ClientOnly result is recorded below. Its process exited, override was removed and a final listener check found no 27850 listener. Lease release is reported in final chat status for Coordinator bookkeeping. The dedicated fixture binds no sockets.

Cross-chat send is unavailable without direct human messaging authorization: the messaging tool explicitly says an orchestrator's received request does not itself authorize replying. This request is exposed through chat status for Coordinator polling; no owner approval is requested here. This is an authorization prerequisite, not a demonstrated client failure.

No runtime, schema, authority, shared runner or creative asset changes have been made. Dedicated ordinary engine captures remain ignored/internal; configuration examples are unchanged.

## Integrated native prerequisite result

At clean `c78c3bd3a62b1ab7a31a1f640507ab5ab2c75baa`, the exclusive Coordinator 27850 lease was confirmed and a listener probe succeeded. Windows Godot 4.7.2 Compatibility ClientOnly **failed** after the guide's explicit stale-revision retry: the subsequent "Collect printed plate into inventory" command received "The production revision is stale or exhausted." Logs/manifest remain internal at `var/ci/tutorial-readiness/6b0933d3116441edbb9520fa9e6dfc8c`. No successful capture was produced. Shared PR38 scripts remain unchanged. This result requires Coordinator triage in its owning scope; it is not waived by the dedicated fixture.

## Dedicated fixture

`client_inventory_shell_test.gd` embeds the actual `FirstPlayableBootstrap` with its real tabs, theme/header, inventory panel and scroll containers. A recording transport avoids sockets/persistence; a fresh canonical world uses the existing owned nested crowbar as the tool. Fixture-selected item/storage/hand IDs, injected Enter events, explicit observer delivery and command receipts are labelled. No physical human input or live-network acceptance is claimed.

The fixture exercises equip, selected hand, switch, unequip into root, move into pouch, unrelated receipt immunity, real intervening hand command causing stale-move rejection, matching rejected feedback reveal and refreshed explicit retry. Checks cover exact unique item identity/definition/condition, carried mass and production stocks/cargo/deposits/energy/structures/components; failed move conserves inventory owner/ledger/receipts. The simulation tick itself advances normally. No runtime fixes or authority changes were needed.

Native capture command: `tools/ci/capture-client-inventory.ps1 -Godot 'D:/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe'`. Headless fixture is included automatically by the existing Windows/Linux runner; graphical capture remains a separate local command. Output is ignored under `var/ci/client-inventory-render`, with clean source head and renderer in the manifest.

Five baseline Windows headless checks passed at c78c3bd: import/startup, integrated_panel_layout, player_inventory_feedback and player_inventory_handoffs. Focused dedicated import/startup/fixture checks passed during iteration; final immutable execution evidence is recorded in chat/PR status. Native/CI final results must be checked separately.

## Native dedicated result

Clean immutable 76d0755fb0a732b13de91636ea6a4a9e6d940416 passed Windows Godot 4.7.2 Compatibility native execution: zero fixture failures. Rejected and accepted captures were visually inspected: full matching host message fits the narrow actual shell; no private data or generated artwork. Profile override removed and child process exited. This verifies the logical inventory body supplied by the injected observer; it does not verify physical habitat-body binding or real network transport. Integrated ClientOnly failure above remains unresolved and requires owning-scope triage. Later documentation-only head retains identical fixture/runner bytes.

## Coordinator-authorized integrated fixture correction

Coordinator narrowly authorized editing the merged ClientOnly script after the initial failure. Static diagnosis: `FirstPlayableHost._process` emits queued batch-completed events before its periodic 100 ms observations; `LocalProductionGuide.note_batch_completed` immediately clears the requested recipe and sets recrafted. The prior fixture's guide predicate could therefore finish with an earlier revision that already exceeded the pre-start revision, before the completion observation arrived. Production increments revision on batch completion, so immediate collection correctly rejects the older expected revision. This is an observation-timing defect in the fixture; no core changes are proposed.

Collection now waits for an actual observation with no job and at least 1 kg printed stock. It requires a successful host receipt; at most three same-button attempts are permitted only for the exact production stale/exhausted message, with the rejection still visible and both client/panel observations newer than the submitted revision before retry. Every attempt records request ID/revision. Non-stale failures remain fatal. Original finite depletion, construction, item and durable-recovery assertions remain intact; no injected resources or host bypass.

Godot 4.7.2 check-only compilation passed without a socket. **Fresh exclusive 27850 Coordinator lease requested** for the corrected immutable ClientOnly rerun. Historical native failure is retained; correction is not accepted as a graphical pass until that rerun. Unaffected dedicated-native and baseline results are reused within their original scopes.
