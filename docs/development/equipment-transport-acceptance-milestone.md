# Equipment transport acceptance milestone

Tests/docs successor to PR91, based on merged commit `23e86e3e1275ca3f58dac11d798581cdfda9a4d5`. The runtime, UI, schemas and transport are unchanged; this does not duplicate PR92 equipment explanations or PR93 machinery work.

## Existing contracts and executable acceptance

`player_equipment_loopback_test.gd` extends the existing owned-container loopback fixture, which supplies the actual `FirstPlayableBootstrap` client shell, traced `RemoteWorldRuntime`, authenticated `FirstPlayableHost`, bounded waits and owned-node/checkpoint cleanup. Both invite principals use production WebSockets. Selector/button signals and the fixture's paused tick runner are synthetic; observations, admission, fixed-tick application and acknowledgements are production paths.

Canonical ownership remains with `InventorySimulationSystem` and `SharedInventoryCoordinator`: the host derives body identity, self intents contain only the existing six operation fields, and equipment/active-hand metadata, ledger and retained receipts commit together on simulation ticks. The current persistence contracts are unchanged. The fixture uses disposable presentation records and no terrain retry journal.

The actual owner shell selects the nested crowbar, closes its backpack, observes disabled Equip and submits no local action; a separate explicitly labeled direct transport probe establishes the host's closed-ancestor rejection. Explicit Open restores access. Equip then moves the same crowbar into the owner root and binds the right hand. During a held tick, real observations continue, selection changes and repeated actions retain the original pending payload/request without optimistic binding or replay. Equipping does not select the hand; separate Make selected hand active and Switch hand buttons produce host-observed active-hand changes while preserving bindings and the complete ledger.

Closing the ancestor destination also denies a real wire unequip without mutation. Explicit reopening enables the actual Unequip button to return the crowbar to its nested pouch. The extractor is then equipped from its existing backpack, explicitly selected in the active hand, observed by the hand-tool control and explicitly unequipped back into its original storage. No extraction, deposits, power or work progression are changed or inferred.

The other authenticated principal's equip and unequip attempts against owner storage reject without changing the complete canonical owner, including revisions and receipts. Every successful self intent checks the exact client ID in a successful wire acknowledgement, its arrival before the fresh revision observation, the canonical `net-1-<client-id>` request and independently computed existing self fingerprint (owner, authenticated body, operation, all IDs and expected revision). Receipt history advances by exactly this receipt, the acting body revision increments once, the foreign body remains completely unchanged, and shell bindings/active hand equal canonical observation.

At each accepted self step, all item records are compared with the baseline after normalizing only the two intentional item location changes. Stable IDs, definitions/revisions, condition and every existing provenance field survive; no missing-item projection is used. Exact integer carried mass remains constant. Hand-only operations preserve the entire ledger and bindings. Final item records and equipment bindings exactly match the initial baseline.

## Verification and limits

Pinned Windows Godot `4.7.2.stable.official.ed1daf0bf` passed import/startup and four checks through the unchanged versioned runner, serially with 120-second test deadlines:

```powershell
./tools/ci/run-godot-checks.ps1 -Godot 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' -TestNames 'player_equipment_loopback_test.gd','player_inventory_closure_loopback_test.gd','player_inventory_handoffs_test.gd','self_inventory_runtime_test.gd' -OutputDirectory 'var/ci/equipment-transport' -TestTimeoutSeconds 120
```

Successful execution used a unique temporary Windows APPDATA profile, restored the environment and removed that task-owned profile after fixture-owned nodes/checkpoints were cleaned. Logs/JUnit remain ignored under `var/ci/equipment-transport`. Coordinator-exclusive 27861/27862 lease was obtained; only 27861 is used by the new fixture, while the inherited regression also uses 27862. Both local and remote port searches returned zero TCP entries after the run, and the lease was released. Occupied ports fail without terminating other listeners.

Two initial fixture runs failed due to numeric representation comparisons and an incorrect assumption that the seeded extractor lived directly in the body root; inspecting the existing seed confirmed its backpack location. Corrected assertions and source/destination IDs passed without runtime changes. The first exploratory run used the default profile; subsequent runs and the passing verification used disposable profiles.

CI discovers the test through the existing runner on both Windows and Linux; exact-head results are recorded separately at PR handoff. Local Windows success alone is not Linux evidence. This is in-process loopback and synthetic button evidence, not human input, tutorial, controller/VR, graphical, external network, process-crash, power-loss, media or deployment acceptance. Source review and runtime assertions resolve this tests-only scope without capture. The Coordinator owns review and merge.
