# Checkpoint confirmation feedback

The source-playable save button has a separate, wrapped session-only status beside the control. One latest explicit request reference owns it; only that exact completion confirms disk success. Observations, automatic/shared saves, unrelated commands, duplicated receipts and older requests cannot replace it. A new explicit save clears the previous result and correlation. Disconnect invalidates the reference and ends settled feedback; an unresolved save reports an unknown outcome and is never replayed. Queue rejection reports that no request was submitted. Feedback is bounded to one label and one pending reference, with at most 512 characters of transport-validated failure detail.

No world state, save implementation, wire schema, persistence format, runtime authority or configuration changes. This slice is separate from PR54 error guidance and restore fencing. Base is merged PR53 at efd3bd7ef6d8eb0465065bc0d5529a6c92d8d533; draft PR56 targets dev-master.

## Verification

Windows Godot 4.7.2 import/startup and checkpoint_confirmation_feedback_test.gd, reconnect_workstation_navigation_test.gd, manual_reconnect_adapter_test.gd, client_inventory_shell_test.gd and integrated_panel_layout_test.gd passed via the versioned bounded runner (seven checks). The expanded final checkpoint test then passed with import/startup (three checks). Ignored logs/JUnit are in var/ci/checkpoint-feedback and var/ci/checkpoint-feedback-final.

The new socket-free actual-shell check activates the save button, feeds the actual acknowledgement decoder, delivers completion and observation in the same frame, and verifies confirmation remains fully visible in the workstation scroll area. It covers exact request identity, unrelated failure/success, duplicate completion, stale receipt, replacing settled and pending requests, failure persistence, queue rejection, disconnect both with and without a preceding synthetic transport failure, unknown outcome, late receipt isolation, reconnect observation, exact send count and canonical snapshot preservation.

Existing network/native acceptance assertion consumers now read the dedicated label. Their prior PR53 evidence remains scoped to PR53; these routes were not rerun locally and no port was opened. Exact-head Windows/Linux CI is a separate review gate. No human input, native graphics, controller, VR, public networking, new disk durability, deployment or merge is claimed.
