# Authoritative tool maintenance prerequisites

## Scope and acceptance

Tool observation v3 adds bounded, read-only full-maintenance quotes to existing owned installed and loose components. ToolSimulationSystem derives each quote through ToolPartState.plan_repair, the planner used by existing paid maintenance. The presentation shows restored integrity in ppm, energy in joules, no material stock consumption, observed station reserve and existing workstation capability/power prerequisites. This is the narrow diagnostic prerequisite slice proposed by the Moonbase Alpha inspiration notes.

No new command, damage cause, wear rule, repair settlement, production catalog, world targeting, bootstrap or persistence contract is introduced. Paid partial repair remains available under its existing bounded amount command; the panel continues to request up to 1,000,000 ppm. Zero-integrity records, detached parts, material provenance and useful unaffected functions remain retained.

## Ownership and compatibility

The tool owner emits quotes during scoped observation only for components in the requesting body's own inventory. Each maintenance key matches an observed part ID exactly. A quote contains amount_ppm=1000000, restored_ppm=1000000-integrity_ppm, energy_joules from the pinned planner, and an empty materials object. Healthy components have zero restored integrity/energy and remain blocked for unnecessary repair. No future material-consuming repair is implied.

Bounds inherit 512 global observed parts, 64 assemblies, 16 parts/assembly and 128 loose parts. Quotes do not contain a next ledger, definitions, damage causes, authorization tokens or predicted capability recovery. No owner adoption occurs. Existing bounded part counters cover the owner; no new tick behavior or expensive diagnostics are added.

ToolObservationValidation accepts exact v2 and v3 layouts; v2 omits quotes and presentation explicitly reports unavailable costs. v3 requires exact quote/part coverage, units, missing-integrity parity, paid energy for degraded parts and empty materials. Old clients that accept only v2 require upgrade for v3 hosts; no protocol negotiation is added. Tool-system persistence remains v1 and quotes are recomputed after restore rather than saved.

Production can_operate remains the canonical inventory-derived reach, consciousness/voluntary-action and unreserved-hand advisory. Construction power and station reserve remain production observations. UI blocks observed insufficient energy for its full-maintenance request, but does not authorize commands or imply smaller repairs are unavailable. Both production/tool revisions, ownership, reach, capabilities, supply and power are revalidated on the tick. Costs may become stale after observation; the UI states that success is not guaranteed. Disconnect clears observations through the existing adapter/panel paths. No cross-owner atomic observation promise is added.

## Verification

Focused Windows Godot runner covers maintenance_requirements_test, repair_usability_test, tool_runtime_test, tool_components_test, tool_parts_runtime_test and recipe_requirements_test plus import/startup. The new test exercises detached/planner parity with partial integrity and rounding, private scope, exact schema rejection, legacy fallback, full-request insufficient-energy advisory, real serialized remote receive/local presentation parity, disconnect and restart-derived quote equality without persistent mutation.

Existing tests cover paid partial repair, stale/foreign ownership rejection, insufficient-energy atomic rejection, zero-integrity retention/repair, material conservation and component persistence. No external service or fixed port is used by this focused run. Local Windows import/startup and all six focused scripts passed after correcting the full-frame test identity grants and sorting displayed action keys for transport parity. Logs/JUnit are under ignored var/ci/maintenance-prerequisites and var/ci/maintenance-parity-fixed. Final exact-head CI results are reported with the PR.

No graphical, VR/controller, human usability or release/deployment acceptance is claimed. No art or media is created or uploaded; this change contains first-party MIT code, schemas and documentation.
