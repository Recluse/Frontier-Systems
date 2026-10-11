# Selected-target control guidance

Successor to PR48, base 716d24d26671112b11e4a3cc77576103b4dc83c5. Branch selected-target-controls; draft PR targets dev-master. One agent, isolated managed worktree; no merge, deployment, integration push or publication.

## Scope and audit

Existing hover advice already names the live selection binding, mouse double-click request route and keyboard/controller activation difference. The selected row supplies identity but no path to actual panel controls. Add one wrapped selected-only guidance row for source, workstation, wall and inventory targets. Reuse existing native route descriptions and current UI cursor binding. Mouse source/item selection does not perform work; keyboard/controller activation retains its existing request semantics. Construction inspection and the explicit new-wall placement draft remain separate.

HabitatTargetFeedback owns volatile display text, refreshed with ordinary physics-frame presentation sampling. No canonical state, command validation, schema, persistence, tick cadence, input ownership or controller/guide scope changes. No host reach, permission or resource readiness is inferred from local pose. Advice retires with selection clearing, removed routes and unavailable observations. Existing bounded wrapped layout and mouse-ignore remain authoritative.

First-party MIT GDScript/PowerShell/docs, ordinary procedural engine rendering; no creative assets or generative artwork. Captures are ignored internal evidence. No sockets, ports, save loading or media uploads.

## Verification

Windows Godot 4.7.2 import/startup plus selected_target_controls_test, habitat_target_feedback_test and held_look_ui_activation_test pass (five headless gates). The dedicated test uses inherited socket-free domain setup helpers but its own first-person selection sequence; accepted fixtures remain unedited. A paid wall and dropped backpack come from existing commands/ticks before freezing canonical state. Actual Window/SubViewport dispatch picks each stable source/item/workstation/wall once, clears each through an empty-sky click, and preserves byte-identical canonical JSON with zero recorded commands. In-memory keyboard/controller/cursor rebinding and unbound hints are checked without writing preferences. Existing regressions retain native route, focus, removal/unavailable and bounded long-text coverage.

Native Compatibility/OpenGL on RTX 3080 Ti passes the dedicated injected route. Eight ordinary actual-client screenshots cover all four target types at 1440×900 and 1000×700; every screenshot was visually inspected for complete, bounded guidance. The small client has a 424-pixel-wide preview and uses the existing smaller font. Selection uses real native picking; first-person camera pose is positioned by the fixture, not by physical human walking. Hover sampling follows the OS cursor, so hover may differ from retained selection. Captures remain ignored/internal under var/ci/selected-target-controls/captures; no media uploaded.

The versioned tools/test-selected-target-controls.ps1 reuses the shared CI runner, isolates APPDATA/XDG settings and bounds headless/native processes to 60 seconds. Its ignored manifest records source revision, dirty state, engine, timestamps and outcomes; logs/JUnit stay alongside captures. Early dedicated-fixture failures involved camera assumptions, a typed conditional array, inventory proxy lookup and an occluded camera pose; corrected iterations are distinguished from passing evidence. No runtime defect or authority change was needed.

Reproduce from the managed checkout:

```powershell
./tools/test-selected-target-controls.ps1 -Godot 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' -Native
```

Exact pushed head and CI results are supplied in the handoff. Local Windows verification does not establish Linux graphical behavior, Forward+/D3D12, networking, packaged execution, physical mouse/keyboard ergonomics, OS focus switching, controller/VR or unaided tutorial success. Human approval remains with Coordinator. The active managed worktree stays available on its pushed draft branch for review.
