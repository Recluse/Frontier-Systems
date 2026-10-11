# Closed-container inventory milestone

Scope: canonical item-hosted closures through the authenticated fixed-tick controller queue, shared ledger physical access, bounded interrupted jobs and atomic JSON recovery. See [the access and privacy contract](../architecture/closed-inventory-containers.md).

No client UI, bootstrap, movement, transport, locks, cyborg modules, planet/ship or external-service changes. Existing owned inventory knowledge is preserved; closed ancestors block physical manipulation and other-body search. New schema versions: ledger/shared v2, inventory system v5 and detailed own observation v4. Legacy records migrate to open state at the first closure commit.

Windows Godot 4.7.2 import/startup and the actual `inventory_closed_containers_test.gd` passed. The test exercises nested closed-path insertion/removal/search, reopening, exact final-tick cancellation, same-boundary close/reopen, preserved owned knowledge/mass/provenance, visible closed shell pickup/drop, actor/session/token/revision isolation, retained closure retries, paused JSON recovery and atomic malformed restore, resource-carrier capability denial, and factory/recycler access. The broader inventory/controller/job/grip/checkpoint suite and machinery/terrain/tool regressions run through `tools/ci/run-godot-checks.ps1`; exact counts and CI status are reported with the PR. New JSON schemas parse successfully.

No captures are needed for this domain slice after source review and meaningful runtime coverage; graphical/human/physical-controller/VR and live-network acceptance are outside this slice. CI uses the existing Windows/Ubuntu Godot matrix and automatically discovers the added runtime test.
