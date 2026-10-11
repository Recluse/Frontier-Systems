# Inventory feedback lifetime fix

Base: `20702c0d749eddfaa4c4e688d194d6d4e264b7c3`.

The inventory panel previously suspended `_reveal_feedback()` across two layout
frames. Removing the panel between those frames could resume the coroutine after
its node was detached or freed. On the baseline, the real closure/disconnect
fixture completed its domain assertions and exited zero, but Godot reported a
resumed function whose class instance was gone. The bounded test runner correctly
rejected those diagnostics rather than treating the exit code as a pass.

Feedback now uses two one-shot frame callbacks bound to the panel. Godot removes
these connections when the node is freed. Each phase checks tree membership,
queued deletion, the current pending request ID, the scroll parent and the feedback
control before proceeding. Repeated scheduling for the same request and phase
shares the existing callback. Living panels retain the two-frame layout delay and
scroll their feedback into view; stale requests cannot scroll a replacement action.

This changes disposable presentation scheduling only. Canonical world state,
commands, host receipts, permissions, persistence and network contracts are
unchanged.

## Verification

The new presentation-only fixture fails against the old implementation with a
null-tree error when a panel is detached between layout frames. It covers freeing
before the first frame and between frames, queued deletion, detachment, repeated
scheduling, stale request IDs in both phases, the two-frame delay and successful
scrolling for a living panel. It creates no world, sessions or commands.

Focused Windows Godot 4.7.2 verification uses the bounded runner with task-private
APPDATA and LOCALAPPDATA:

```powershell
./tools/ci/run-godot-checks.ps1 -Godot C:/Godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe -TestNames player_inventory_feedback_lifetime_test.gd,player_inventory_closure_disconnect_test.gd,player_inventory_feedback_test.gd,client_inventory_shell_test.gd,player_inventory_transfer_layout_test.gd,player_inventory_transfer_preview_test.gd -OutputDirectory var/ci/f6-final -TestTimeoutSeconds 120
```

Import, startup and all six focused tests pass without engine error diagnostics.
The existing disconnect fixture supplies real isolated loopback coverage; the new
lifetime fixture and adjacent shell/layout tests supply headless presentation
coverage. This does not establish human usability, native graphics, Linux execution
or full-suite acceptance. No production save, external service or deployment is
involved. Exact-commit remote CI remains a separate review gate.
