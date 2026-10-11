# Authoritative recipe prerequisite observations

## Completed scope

Production derives detached `recipe_requirements` from its actual validated startup catalog, with observation v8 independent of persistence v7. The workstation resource helper replaces all pinned fixture costs with validated host inputs, energy and station information. It retains current shared-stock, owned-cargo, finite-deposit and job distinctions, and leaves capacity/duration quotes unavailable. Commands, permissions, recipes, tick cadence, persistence, terrain, bootstrap and input/target presentation are unchanged.

The remote decoder accepts exact v7 and v8 observations, bounds and validates requirements, and pins catalog identity/requirements within a connection. Legacy v7 cannot provide costs; no assumptions fill the gap. Old v7-only clients cannot consume v8; matched builds are required. Disconnect clears identity through the existing projection teardown. The default scenario's session/task guides are unchanged and do not constitute alternate-catalog quotes. See [contract and limits](../architecture/local-production-guide.md#current-workstation-recipe-requirements).

## Verification

Local Windows Godot 4.7.2 import/startup and `recipe_requirements_test.gd`, `workstation_resource_view_test.gd`, `repair_usability_test.gd`, `first_playable_task_guide_test.gd`, `machinery_runtime_test.gd` and `checkpoint_recovery_test.gd` passed with the versioned bounded runner. The new check exercises serialized host/local parity through actual remote frame receive without sockets, independently validated alternate host catalog costs and identity, read-only state/catalog preservation, malformed records, shared stock versus owned cargo and exhausted deposits, legacy v7, immutable connection identity and disconnect clearing.

The independent schema test validates emitted current/alternate v8 observations, legacy v7 observations, persistent v7 records and rejects observation-as-persistence/version confusion. Twenty-eight malformed records are rejected: 25 by JSON Schema and three by explicit runtime semantic constraints (key equality and total mass). Windows PHP runtime policy and diff whitespace checks passed. Existing main CI covers Windows/Linux PHP, Godot and development exports; the added focused Windows/Linux workflow also validates runtime-emitted schema fixtures.

No fixed ports were used or reserved. No live services, graphical/human/controller/VR acceptance, new art, media/LFS uploads, release, deployment, merge or integration-branch push are claimed. Exact-head PR CI results are reported in the final handoff; local Windows checks alone do not establish Linux acceptance.
