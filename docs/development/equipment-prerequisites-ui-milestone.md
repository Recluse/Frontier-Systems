# Equipment fabrication prerequisites and component presentation

## Scope

LocalProductionPanel now shows exact observed equipment blueprint material requirements in mg beside actual shared stock and shortfalls, fabrication energy beside current finite station reserve, printer power and workstation access. Carried cargo, physical loose parts and mounted parts are explicitly separate from shared stock. Selected owned fabricated equipment displays its stable ID, current recoverable installed materials, salvage energy, recycler power and receiving-capacity uncertainty. Spent energy is not recoverable material.

Blueprint/equipment pickers require an explicit selection and preserve missing stable IDs as unavailable choices. Reordering, renamed labels and disappearing/reappearing records do not silently choose a replacement target. Commands use existing fabrication/salvage actions and current revisions. Pending commands confirm no output; rejection retains the host reason, and disconnect clears observations and requires a fresh observation to resolve outcome uncertainty.

EquipmentPrerequisiteView also provides an independent component display for validated tool observations: physical loose identities, material grade/integrity, installed mount identities and observed available/disabled capabilities. It describes retained displaced/detached parts, useful partial functionality, capacity and host validation without predicting compatibility, damage causes or future repair outcomes. This helper is **not integrated into PlayerInventoryPanel**: Coordinator assigned that file exclusively to the concurrent inventory milestone. Replacement-control integration is deferred until that work merges. The locally proposed inventory diff is preserved only in ignored `var/proposals/player-component-prerequisites.patch`; it is not part of this PR.

## Authority and compatibility

Canonical production/inventory/tool owners, fixed-tick transactions, cadence, persistence, profiling and failure behavior remain unchanged. The helper owns no state and submits no command. Existing production observation v8 and tool observation v3 are read-only inputs; validated legacy production v7 retains equipment blueprint costs and tool v2 retains physical-part display. No missing repair/fit energy quote is invented. Existing paid maintenance display, recipe requirements, recipes, wear, schemas, network/bootstrap, world targeting and terrain are unchanged. No new fabricated parts or free resource grants are introduced.

First-party GDScript/tests/documentation are MIT; no assets, generated imagery, captures or third-party creative material are added. No media/LFS/public uploads or fixed ports are used.

## Verification

Windows Godot 4.7.2 existing bounded runner import/startup and `equipment_prerequisites_view_test.gd` pass. The test covers exact stock/energy/power/shortage display, v7/v2 compatibility, malformed/unavailable observations, real remote receive parity/disconnect, observed disabled and retained functionality, missing/reappearing stable IDs, pending/rejected existing intents and immutable owner state before the tick. Fixtures remain detached; no live service is contacted.

Existing `equipment_fabrication_test.gd`, `tool_parts_runtime_test.gd`, `maintenance_requirements_test.gd`, `recipe_requirements_test.gd` and `workstation_resource_view_test.gd` pass. Logs/JUnit are ignored under `var/ci/equipment-prerequisites` and `var/ci/equipment-regression`. The latter aggregate includes an earlier failed new legacy fixture, corrected and passed separately; its five existing regression results passed. Diff whitespace checks pass.

Exact feature-head Windows/Linux CI will be reported through the draft PR. Local headless evidence does not establish graphical layout, human/controller/VR acceptance or live multiplayer behavior. No merge, integration-branch push, release or deployment is authorized by this milestone.
