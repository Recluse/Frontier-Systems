# Machinery paused-batch Cancel recovery milestone

Tests/docs successor to merged PR #96 (`b19923b`). The new `machinery_cancel_recovery_test.gd` inherits PR96's transport helpers and the original finite, paid `machinery_runtime_test.gd` fixture. Neither existing fixture nor the finite-extraction PR97 / inventory-transfer PR98 files changes.

## Observable acceptance

The actual FirstPlayableBootstrap MachineryPanel starts `extract.ice` through authenticated loopback WebSocket ingress. Thirty deterministic ticks leave nonzero progress and spent energy. The actual Save control waits for native worker disk completion; checksum-validated readback retains the entire paid production record. A pending Cancel is deliberately disconnected before host polling. The same running client abandons it with uncertainty, clears its observation, and sends no replay on manual Reconnect to the replacement host.

Replacement loads the native committed checkpoint. Recipe, progress and spent energy survive exactly; only the restore pause flag changes. Another 180 ticks cannot resume or output matter. Choosing an unrelated `refine.iron` dropdown leaves the saved recipe intact. The actual Cancel button sends one exact machine ID / observed revision / request ID without recipe replacement. Navigation preserves the identity and freezes selectors until the matching host receipt settles acceptance. The settled identity and acceptance feedback remain visible.

Accepted Cancel removes the job and advances the production command revision once. All cargo, finite deposits, storage, structures, loose parts, vessel, workstation job/reservations, walls, machinery parts/mounts/links, and complete inventory owner/provenance/revision records remain exact. A genuine restored paused clone executes the identical charging tick: every placement record matches after Cancel, proving no energy refund against ongoing grid charging. Whole-world capture and production mass validation pass. Another 180 ticks cannot output or replay. Fresh Cancel and Resume requests reject absent jobs without matter mutation.

## Existing semantics and authority

Production owns canonical jobs, matter and power on fixed ticks; inventory owns physical parentage and provenance. Production v7 / observation v8 / existing checkpoint schemas remain unchanged. Cancel erases the machinery job, including its progress/energy counter; previously debited energy remains spent rather than surviving as a separate cancellation receipt. Grid generation and charging continue independently.

This extractor recipe has no canister input bill: the finite source and output canister remain unchanged until completion. Machine jobs do not reserve or debit matter at Run ingress. Cancel therefore does not return reserved machine input. The workstation `job` and its reserved-mass accounting are a different contract and remain unchanged. This fixture establishes exact conservation for the paid extractor batch; it does not claim every refinery/chemical recipe was exercised.

Invalid machine IDs, stale revisions and a forged replacement recipe reject with the paused job and physical records unchanged. An identical request while still pending rejects locally without another frame. Deliberately resubmitting the settled original request ID and payload is accepted into transport but fails the now-stale production revision; it does not return cached success. A fresh current-revision repeat rejects because no job exists. Machinery has no durable terrain-style exactly-once receipt/retry contract, and reconnect does not automatically replay machinery requests.

The authority probe moves the existing other authenticated body through inventory commands into reach and successfully cancels a deployed shared frame. After the original owner unwires/packs that frame, the other principal is rejected as neither owner nor operator of a deployed frame. This is physical ownership/reach authority, not a universal foreign-principal prohibition. PR96's existing Resume probes distinguish accepted Resume from later prerequisite stalls; this successor does not change ingress or tick semantics.

## Verification and limits

Pinned Windows Godot `4.7.2.stable.official.ed1daf0bf`, the bounded repository runner import/startup, the new Cancel test and PR96 Resume regression are the focused local checks. Final committed-head results and exact-head Windows/Linux CI are recorded in PR99 and the Coordinator handoff; pending CI remains pending. Existing CI automatically discovers this headless test.

Runtime checks run serially on Coordinator-leased port 27849, with unique temporary checkpoint directories and final-run process profiles; no occupied listener is terminated. Checkpoints and profiles are cleaned up, and the port is released after final verification. Synthetic button signals, disposable loopback transport and in-process host replacement do not establish human input, graphical/controller/VR usability, separate-process crash recovery, tutorial, hardware or public-network acceptance. No media or deployment. Coordinator owns merge; the draft PR and managed worktree remain available for review.
