# Local health display

The desktop prototype displays the inventory actor's health in the existing `hud.inventory` section. Overlay themes and section visibility continue to apply. This display is read-only and does not add treatment, injury generation, or another overlay layout requirement.

## Observation boundary

`WorldRuntime.own_health_observation(context)` validates the current world and region, then resolves the local development principal through inventory authorization. Callers cannot supply a target body ID. Missing services, grants or body bindings fail closed. Own observations remain available while unconscious without granting voluntary actions.

The detached version 1 projection contains `schema_version`, `body_id`, `tick_number`, `consciousness`, `last_assessed_tick`, `recovering`, `voluntary_actions_available`, `injury_revision`, `injury_changed_tick`, `parts`, and `oxygen_damage_permille`. Parts and units match the bounded injury record. Internal cause identities, source revisions, receipts, pending changes, and scheduling data are omitted. This is a local presentation contract, not a network endpoint or persisted record.

## Presentation and lifecycle

`LocalHealthPanel` configures once and refreshes at most once per rendered frame, with a 100 ms interval. It retains only label text. It displays six part injury severities, systemic oxygen injury and the latest committed consciousness assessment. An injury newer than that assessment is explicitly marked as awaiting assessment. Values are severity units out of 1000, not percentages of remaining health.

World closure clears all health text and disables polling. Observation failures clear prior values. No simulation commands are submitted, and refreshes do not change snapshots or receipts. Normal per-read work is bounded to one body's six parts and at most sixteen assessed causes in the internal observation.

The fixed actor is `local-inventory-actor` (`body.human-2`). Development controls elsewhere may select the target body, but this display always observes the actor. The logical actor is not yet the capsule walker's health authority. Authenticated multiplayer player/body binding and spatial XR presentation remain future adapters.

## Focused checks

`tests/godot/local_health_panel_test.gd` covers world/region/principal/grant isolation, detached observations, pre-tick visibility, unconscious read access, rendered values, refresh persistence neutrality, and cleanup on world closure. CI runs this check on Windows and Linux.
