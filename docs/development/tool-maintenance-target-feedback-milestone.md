# Tool maintenance target feedback

The inventory panel now separates the inspected item, selected repair component,
selected mount, host-observed installed occupant and selected detached fit/recycle
part. The previous generic mounted-component selector also serves inspection of
an owned detached part; its label now describes both existing uses. Missing or
removed records explicitly make the corresponding target unavailable. A missing
inventory frame clears component observations and recovers on the next frame.
Disconnect removes maintenance and work target claims.

ToolMaintenanceView and PlayerInventoryPanel own disposable presentation only.
Repair details use the existing scoped integrity, material, capability and full
maintenance energy quote. Selection grants no compatibility, repair result,
post-repair capability or reach. Component provenance, conservative completed-work
wear, retained detached parts, partial capability rules, schemas and commands are
unchanged.

Extraction shows intended source, receiving canister and cycle count before the
existing actions. Start uses observed active equipment independently of the
inspected maintenance item. An existing reservation shows its host-bound tool,
source and canister; resume/cancel address that reservation rather than current
picker choices. Completed/reserved counts come only from the host job record.

Repair and extraction join existing component actions in pinning exact submitted
fields and revisions while waiting. Matching receipts retain those targets and
host rejection reasons without synthesizing an after-state. Unrelated receipts
and late receipts after disconnect cannot complete or retry an intent. No extra
command, automatic retry, transport, controller or movement behavior is added.

Maintenance, prerequisite and work summaries wrap and accept keyboard focus.
Existing focus-following scrolling and Up/Down/Page Up/Page Down review apply to
these summaries. Captures are internal, ignored artifacts produced by ordinary
Godot rendering; no new art assets are introduced.

## Verification scope

`tool_maintenance_target_feedback_test.gd` exercises actual panel repair against
an isolated damaged fixture through real fixed host ticks: exact pending amount
and revisions, success, stale paid rejection, removed observation while pending,
unrelated/exact/late receipts and disconnect. The fixture also equips through
the real self-inventory envelope, starts a real reservation, changes the intended
source independently, observes a completed cycle and cancels the original binding. Damage exists only in detached test
snapshot setup. `player_inventory_components_test.gd` covers real fabricate, fit,
detach and recycle transactions, displaced and removed selections, missing-frame
recovery and rendering without canonical mutation or extra commands.
`player_inventory_usability_test.gd` adds keyboard review of the new summaries at
440×900 and 280×640 pane sizes with real paid fit and internal native captures.
Existing maintenance requirements and active-hand feedback checks cover quote
contracts and the separate active-equipment presentation.

The existing Windows/Linux CI Godot runners discover the new fixture automatically.
Local Windows headless and native results, exact commit and CI status are reported
with the draft PR. Linux graphical, human usability, controller/VR, live transport,
mixed builds, deployment and broad HUD freshness are outside this milestone.
