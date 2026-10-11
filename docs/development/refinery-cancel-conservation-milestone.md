# Refinery Cancel input conservation milestone

Tests/docs successor to PR99 (`5ed939078600303fbf8ac767ba3ee588c45271aa`). The new fixture inherits the paid finite machinery loop and PR99 native recovery/transport acceptance. Two machine/recipe selection hooks keep the original extractor regression intact.

## Acceptance and canonical contract

The fixture transfers the existing extracted 1,000,000 mg ice canister from the extractor into the existing refinery, inserts the existing empty output canister, and reconnects the paid solar generator through authoritative commands. No fixture snapshot edits grant matter or authority. The actor stands clear of the generator envelope while remaining within reach of both cable endpoints. `refine.ice` has a real 1,000,000 mg ice input bill and equal water output over 60 ticks for 500 prototype J.

Production owns machine progress and energy at its fixed tick. Recipe inputs remain in physical canisters until atomic output completion; partial progress consumes energy without reserving or removing inputs. Native whole-world checkpoint validation retains production and inventory provenance; restore pauses the active batch.

The actual client starts the recipe, saves a partly paid job through worker-completed native storage, loses a pending Cancel before host ingress, and manually reconnects the same running client after in-process host replacement. Paused ticks preserve saved recipe, progress, energy, input cargo, physical provenance and inventory revisions. Selecting `refine.iron` cannot replace the saved `refine.ice` intent. Explicit Cancel submits only frozen machine/revision fields, advances revision once, and creates one authenticated-slot-bound receipt. A genuinely paused cloned world supplies the same-tick charging baseline, proving Cancel does not refund spent energy.

Every inherited conservation assertion additionally requires exactly 1,000,000 mg ice remain in its original canister and zero water in either canister. Later ticks, retained identical request replay, changed-intent rejection, fresh absent-job Cancel and Resume cannot produce output or duplicate consumption. Rejection probes cover stale revision, forged replacement recipe, missing machine, reachable shared deployed machinery and foreign packed-frame ownership. Workstation reservations remain a separate unchanged contract.

## Verification and limits

Run the bounded pinned Windows Godot 4.7.2 runner for the new refinery test and inherited extractor Cancel/Resume regressions. CI discovers the new test automatically; exact-head Windows/Linux required CI remains the remote gate. Final local and CI evidence is recorded in the PR and Coordinator handoff. Initial fixture setup iterations failed reach/socket and then body-overlap checks; those runs are not acceptance evidence.

Serial sockets use Coordinator-leased loopback 27849 explicitly configured on both host and client. Unique temporary native checkpoints are disposed by the inherited fixture. Synthetic controls and loopback with in-process host replacement do not establish human input, graphical/controller/VR usability, separate-process crash recovery, tutorial, public network or hardware acceptance. Human tutorial remains `awaiting_human`. No media or deployment. Coordinator owns merge; retain the draft and managed worktree for review.
