# Active hand and tool feedback

Inventory identifies the host-observed active hand and equipped item by full stable
IDs beside equipment controls and extraction. Selected inventory item and equipment
slot appear separately. Selection alone does not change active equipment. The old
unconditional “Active tool · resource extractor” heading could imply an extractor
was active even with an empty hand or a crowbar.

PlayerInventoryPanel and PlayerInventoryPresentation own this disposable feedback.
They read existing scoped hand IDs, equipment bindings and item records, with the
existing network tick and inventory revision. They claim no capability, operational
condition, reach or readiness; the host decides whether the equipped item can
perform an engineering action. Component inspection remains tied to selection.

Missing hand/binding/item observations, older ticks/revisions and disconnect remove
the corresponding active-equipment claim. Five seconds without an advancing host
tick removes these summaries' claims even before a connection closes. Repeating a
timed-out tick cannot restore them; an advancing observation can. Direct local
fixtures without network ticks refresh on each delivered observation. This local
wall-clock timeout affects only these summaries, not simulation, controls, other
HUDs, command routing or transport policy.

Equipment commands retain exact pending feedback until the matching receipt.
Fresh observations can update equipment while the command remains explicitly
unconfirmed. Acceptance alone does not synthesize equipment state; unrelated
receipts cannot clear pending state. Disconnect retains an unknown outcome, with
no automatic equip, retry or new command. No schemas or canonical owners change.

## Verification

The socket-free active_hand_tool_feedback_test.gd extends the actual client shell.
It activates controls with injected Enter input and applies actual inventory
commands through fixed ticks. Cases include hand switching, selection versus
equipped item, exact/unrelated receipts, acceptance before fresh observation,
real stale-revision rejection, removed/missing observations, older tick/revision,
timed-out/repeated tick, recovery and late receipt after disconnect. Full
128-character active item IDs wrap and accept keyboard focus at 1920×1080,
1100×720 and 900×640. Detached observation/layout rendering must neither mutate
canonical state nor enqueue commands. Captures remain ignored/internal.

The existing Windows/Linux headless CI runner discovers this fixture automatically.
Native ordinary rendering uses tools/ci/capture-client-inventory.ps1 with
`-Fixture active_hand_tool_feedback_test.gd`; no sockets or fixed ports are used.
Local results and exact feature head are reported with the draft PR. Human
usability, controller/VR, live transport, mixed builds, deployment and broader HUD
freshness remain outside this verification scope.
