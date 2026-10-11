# Workstation resources and recipe prerequisites

## Scope and ownership

`LocalProductionPanel` now delegates resource/status text to `WorkstationResourceView`. The helper owns disposable presentation history only: whether a previously observed job disappeared. Production remains the canonical owner of mass, energy and batches; inventory owns physical item identities and containment. The existing 10 Hz panel poll uses detached observations, validates with `RemoteProductionProjection`, and submits existing fixed-tick commands unchanged. No core, networking, schema, persistence or bootstrap contract changes.

The existing tool diagnosis and maintenance section is preserved. Source reach and remaining mass, station power, vessel contents/pressure and legacy wall counts remain visible. Recipe pickers retain stable IDs across polling/reordering and clip long titles rather than imposing a wide minimum; labels wrap inside the existing scrollable workstation tab. Recipe details sit immediately below the selector and above its action button.

## Observed facts versus fixture hints

The display separates shared station stock from owned carried canister payloads and owned physical plates. Canister material must be unloaded before workstation recipe use. Printed shared plate stock requires collection into a physical inventory item. Counts describe the current observation and can decrease; they do not prove the player's history.

The scoped production v7 observation exposes recipe IDs, not live recipe inputs, costs, durations or output capacity quotes. The UI explicitly reports those quotes unavailable. Seven optional default fixture hints are pinned to `data/production/catalog.v1.json` at `c8f6f145325965b39d827b40eb879a190f853ae3`; displayed shortages, station and energy comparisons explicitly say they use fixture assumptions that may differ from the host. Tests check each hint against that catalog. The helper does not load a local catalog as live authority or enable/disable commands based on its hints. The host continues to validate capability, inputs, energy, power, capacity and revision.

Queued command receipt, active job, paused job and disappeared job have separate wording. Acceptance does not confirm outputs. A disappearing job is described as ended with completion/cancellation unconfirmed; no inferred success is stored. Empty, partial, malformed and disconnected data clear current resource claims. Existing command rejection feedback remains separate. No payload, stock, output or success is invented.

## Verification

Windows Godot 4.7.2, existing `tools/ci/run-godot-checks.ps1`, 120-second test bounds: import/startup, `workstation_resource_view_test.gd`, `repair_usability_test.gd`, and `first_playable_task_guide_test.gd` passed. The new test exercises valid/empty/partial/malformed records, pinned assumptions, ownership boundaries, real extraction/unload/queued acceptance, active/paused/cancelled/rejected work, simultaneous blockers, reversible counts, stable recipe selection/reordering, wrapping/clipping configuration, disconnect clearing and unchanged canonical snapshot/input observation from the helper. Existing maintenance and guide regressions pass.

No fixed sockets were used or reserved. No live service, graphical readability capture, full scroll/human/controller/VR acceptance, media upload, release, deployment, merge or integration-branch push is claimed. Exact-head Windows/Linux CI is required on the attached draft PR before coordinator review/merge; CI results belong in the final handoff, without confusing local Windows success with remote matrix evidence.

## Superseding contract

The fixture hints described above are historical. [Authoritative recipe observations](authoritative-recipe-observations-milestone.md) replace them with validated host inputs, energy and station requirements in observation v8; legacy v7 now displays unavailable costs explicitly. Production persistence remains v7.
