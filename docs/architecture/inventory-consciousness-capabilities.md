# Consciousness and basic inventory gameplay

## Scope and priority

Basic gameplay takes priority over away missions and full procedural planets. This slice connects the existing logical inventory/body/grip interactions to the registered health system. It does not implement procedural missions, combat injury generation, chemical administration or physical body/VR locomotion.

`WorldRuntime` binds one `HealthSimulationSystem` to `InventorySimulationSystem`. `ConsciousnessOwner.allows_voluntary_actions()` is a constant-size derived read of canonical state; health denies unknown bodies. Neither helper grants access or overrides hand, reach, item, revision or tool checks. Missing health bindings fail closed for voluntary actions.

## Behavior

Inventory authorization separates identity-scoped observation from voluntary capability. Existing own-inventory/status observations retain their principal binding while unconscious. Commands and other-body search reads require voluntary capability. Actor commands include self equipment, hand switching, world pickup/drop, logical movement/resistance, search/take/insert/equip, job resume/cancel and grip join/release/resume. They reject while the body's current canonical consciousness is unconscious.

Health runs at priority 100 before inventory priority 200. On the inventory tick, incapable actors lose active or paused muscular grips, unfinished voluntary jobs cancel without transferring items, and existing external search views revoke. Releasing a cooperative participant preserves the other participants through the existing grip owner's rules. No items, bodies or passive attachments are deleted by incapacity.

An unconscious target remains physically available under the existing reach/access rules. Their voluntary resistance cannot be fabricated. A conscious actor can search/interact with that target's accessible possessions; this is scoped physical access, not unrestricted permission or a remote control grant. Recovery restores the consciousness contribution to action availability without automatically restarting cancelled jobs or grips.

## Tick ordering and persistence

The runner processes queued commands before system ticks. Command checks use consciousness already committed at command execution. A health observation assessed later that tick cancels ongoing jobs/grips before inventory completion; it does not retroactively undo an immediate inventory command processed earlier. Urgent combat/medical integration must specify authoritative event order before promising same-tick hit/action suppression. Bounded health scheduling can also defer a newly observed cause before its assessment.

Health/owner saves remain authoritative after restore, so reconnect does not grant voluntary inventory access. Existing inventory restore pauses jobs/grips; the first inventory tick removes those whose actor remains incapable. No new inventory snapshot version or duplicate persisted capability flag is added. Cached UI state and client-authored booleans cannot enable an action.

## Verification and remaining gameplay

`inventory_consciousness_test.gd` checks capable grip acquisition/search, knockout interruption, hand release, own-observation scope, denied movement/resistance/search, unchanged item ownership, restored incapacity, recovery, conscious searching of an unconscious target and completed-view revocation. CI includes this check on Windows/Linux. Windows import and focused checks passed.

Other action systems remain pending: airlock/PDA development controls currently use independent development principals; desktop capsule and XR tracked presentation are not bound to canonical health bodies. This slice does not claim that all player input is disabled globally. Next connect basic injury/breathing/chemical sources and authenticated player body control, retaining these server-owned capability checks. Away missions remain roadmap work until the basic gameplay loop is ready.
