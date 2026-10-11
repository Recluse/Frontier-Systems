# Machinery paused-batch recovery milestone

Successor to PR #93 (`380c22878937bbde17f96a1c6f8355913814154e`). Tests and documentation only; the new `machinery_resume_recovery_test.gd` extends the existing paid `machinery_runtime_test.gd` fixture without modifying it or the equipment transport / InventoryPanel successors.

## Observable acceptance

The actual `FirstPlayableBootstrap` MachineryPanel starts a finite `extract.ice` canister batch through authenticated WebSocket ingress on the exclusively leased loopback endpoint. The fixture pays for its frame, components, sockets, wiring and canisters from finite mined/refined stock. Thirty further deterministic ticks leave nonzero progress and spent job energy. The actual Save control receives a worker-completion acknowledgement; native checksum-validated readback equals the entire captured production record.

A pending Resume is deliberately disconnected before the host polls it. The same running client clears its observation and reports uncertainty. Replacement loads the native checkpoint and manual Reconnect reauthenticates the invite; neither transition sends abandoned Resume or automatic machinery replay. The saved canonical recipe, progress and paid energy survive, with only `paused` changed on restore. Another 180 ticks cannot complete the job or alter cargo, deposits, material records or inventory owner/provenance/revisions. Grid generation and charging may continue; conserved job energy is distinct from local buffer totals.

The actual Resume button submits exactly one machine ID / observed production revision / request ID, without a client replacement recipe. Navigation freezes selectors and identity while awaiting the host tick. Choosing an unrelated recipe does not retarget the saved job. Explicit acceptance continues only remaining work; progress/energy reaches the final tick, and an identical genuine paused replacement provides the grid-charge baseline for checking the final remaining-energy debit. Exactly 1,000,000 mg ice transfers from the finite source to the fitted canister once. Whole-world codec and production mass validation pass; later ticks cannot replay output, and Resume on a completed batch rejects.

## Runtime boundary and remaining gap

`ProductionSimulationSystem` owns jobs, matter and power and advances them on fixed ticks; inventory owns physical parentage and provenance. Production v7 / observation v8 and the existing world/checkpoint versions remain unchanged. Host ingress reconstructs authenticated context from its invite policy rather than accepting client authority. Worker I/O never advances jobs.

Current `machine_resume` checks job existence and access, then clears the pause flag. Missing canister, missing work head and machine isolation do **not** reject Resume: subsequent ticks recheck prerequisites and stall. Three genuine restored-world probes exercise those faults through existing production commands, verifying unchanged progress, spent job energy, cargo and deposits over 180 ticks. Stale production revisions reject without unpausing. A conflicting Run cannot replace the existing recipe. Foreign owned packed frames reject at physical authority ingress; deployed frames are shared within authenticated reach, so this is not a universal foreign-principal prohibition. Requiring prerequisites to reject at Resume ingress would be a separate runtime change; Coordinator directed this milestone to record existing behavior.

## Verification and limits

Pinned Windows Godot `4.7.2.stable.official.ed1daf0bf`, repository bounded runner import/startup, the new acceptance test and `machinery_operation_feedback_test.gd` establish the behavior above. The final committed-head run and exact-head Windows/Linux CI are recorded in PR #96 / Coordinator handoff. Existing CI automatically discovers the new headless test; no workflow changes are needed.

Synthetic button signals, loopback transport and in-process host replacement establish runtime behavior, not human input, graphical/controller/VR usability, separate-process crash recovery, hardware or public-network acceptance. Captures are skipped because meaningful runtime conservation/recovery assertions resolve this tests/docs scope; no public media or deployment. Coordinator owns merge. The open draft PR and managed worktree remain available for review.
