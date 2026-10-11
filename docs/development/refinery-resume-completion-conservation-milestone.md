# Refinery Resume completion conservation milestone

Tests/docs successor to merged PR102 (`041080b5af6853712ca3376a74818f15e32fb264`). Reuse the finite paid refinery setup and native checkpoint/manual reconnect transport helpers. No runtime, schema or UI changes are intended.

## Acceptance

A native partially paid `refine.ice` checkpoint restores paused without automatic replay. Explicit Resume must preserve the saved recipe and finish only the remaining work, atomically consuming 1,000,000 mg ice and producing 1,000,000 mg water. Assert complete input/output canister records, physical inventory provenance, production revisions/receipts, and energy accounting against genuine paused charging baselines.

Idle ticks, retained identical Resume intent, conflicting retained intent, fresh absent-job Resume and completed checkpoint restore must not duplicate water, consume more input or refund paid energy. Preserve unrelated extraction retry PR103 and inventory presentation PR104.

## Verification and limits

Use the repository bounded pinned Godot runner; new tests are discovered by Windows/Linux CI. Loopback 27849 requires an exclusive Coordinator lease before sockets. Final exact-head local and remote evidence belongs in the PR and Coordinator handoff.

Synthetic controls and in-process host replacement are not human input, crash recovery, graphical/controller/VR, tutorial, public network or hardware acceptance. Human tutorial remains `awaiting_human`. No media or deployment. Coordinator owns review and merge; retain the draft/worktree until that handoff.
