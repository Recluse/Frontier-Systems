# Paid wall lifecycle durable recovery

## Narrow gap and existing coverage

`spatial_wall_runtime_test.gd` already covers owned finite plates, pose/reach/overlap rejection, retained construction retry, JSON restoration, shared dismantling and recycling. `first_playable_acceptance.gd` already covers native durable construction, original client transport reuse, retained build receipts and a competing removal race. `engineering_loop_shell_test.gd` covers paid shell controls with injected transport.

The remaining gap was a completed removal receipt carried through native durable storage and a replacement host, followed by the same running client's explicit reconnect control and no second material return. `paid_wall_lifecycle_recovery_test.gd` reuses the cooperative acceptance transport, movement, production and native save helpers in a focused single-client route. The existing host's two-slot invite policy remains intact. No runtime, schema or UI contract changes are introduced.

## Automated acceptance

The test authenticates the existing crew and carrier, approaches the finite iron deposit using bounded canonical movement commands, extracts two separate 1 kg batches, unloads, refines, prints and materializes one physical plate. It checks its exact inventory catalog/condition/container record and carried mass. Canonical `wall_build` consumes that plate into one wall; presentation never grants resources or ownership.

Three native worker checkpoints and in-process replacements cover the built wall, removed wall with returned plate, and recycled returned plate. Each native disk readback equals the complete captured world at the saved tick. Each replacement restores every world record exactly before ticks, including wall identity/pose, production receipts, stock, component provenance, inventory records, revisions and mass. The same shell observes transport loss, does not reconnect automatically, and reconnects through its actual manual button using its original invite. Reconnect queues no automatic command or refund.

The built-wall checkpoint acknowledges the exact original build request without another consumption. Explicit removal returns exactly 1,000,000 mg of the original material bill once. The returned plate has a new stable identity derived from the removal receipt, as specified by the existing runtime; this test does not claim the consumed item ID is resurrected. Its definition, definition revision, condition and receiving container match the original plate exactly. The ten-kilogram iron source budget closes with 8 kg remaining deposit, 0.2 kg refined stock, 0.8 kg tailings and 1 kg returned plate. Unrelated tool component provenance remains unchanged.

Before and after completed checkpoints, the test submits the exact removal ID/operation/payload again, changes the target under that ID, changes the operation under that ID, and submits a fresh ID for the absent wall. Only the exact retained receipt succeeds. These probes compare complete production, inventory, tools and terrain records, normalizing only each system's advancing `last_tick`; they cannot add receipts, revisions, components or refunds. Scheduled health assessment is not frozen or compared as an idle invariant. Full-world equality is required at durable restore and immediate reconnect before simulation resumes. Recycling returns exactly the original 1 kg refined matter once; after the recycled checkpoint, retained removal cannot recreate a plate, and fresh recycling of the absent returned plate rejects.

## Verification and limits

Run the existing bounded runner with pinned Godot 4.7.2:

```powershell
./tools/ci/run-godot-checks.ps1 -Godot '<pinned-console-executable>' -TestNames 'paid_wall_lifecycle_recovery_test.gd' -TestTimeoutSeconds 120
```

The versioned runner discovers the new test by filename. `.github/workflows/ci.yml` runs that runner on Windows and Ubuntu with pinned Godot 4.7.2; tests change the CI scope to full. Exact-head remote results must be checked separately from local execution and the earlier prose-only draft checks.

Local final result and remote CI evidence are recorded in the PR/coordinator handoff. Temporary checkpoint files are removed on successful test completion. Local port 27849 must be exclusively reserved with the Coordinator before execution; no unrelated host is terminated.

This is automated headless WebSocket loopback, native filesystem I/O and in-process host/world replacement. It does not prove abrupt process death, power-loss durability, remote network behavior, human keyboard/controller/VR acceptance or graphical usability. No captures are required for these test-only assertions: the exact records and meaningful runtime checks establish the scoped behavior. No public media, deployments, live external services or generative art are involved.
