# Observed finite-loop guide next steps

## Scope and ownership

From integration base `7be796d611c971089a23bb4e3f79aa9c065ef88d`, the existing Guide tab now explains seven stages: gather, transport, refine, print, collect, recycle and reprint. Construction remains an optional observed row. This is a list of actions to try, not historical or actor-specific completion. The separate Workstation `LocalProductionGuide` retains its seven-stage paid checklist and confirmed-command/batch-event ownership unchanged.

`FirstPlayableTaskGuide` validates a full projection before describing it and rebuilds nine wrapping, mouse-transparent rows per observation. Invalid/partial data and disconnect clear every old row. ProductionSimulationSystem and InventorySimulationSystem retain canonical state and command validation. This helper owns only bounded presentation text, with no simulation cadence, persistence, schema or protocol change. Existing projection limits bound loops; no additional profiling signals are needed. No inventory/workstation controls, bootstrap/input, habitat target, core or adapter edits.

## What the guide explains

- Gathering needs an owned canister, finite remaining ore and observed extraction capability; capacity is still a host check. Transport names the selected canister, workstation reach/body/free-hand prerequisites and receiving capacity.
- Recipe energy, input and station hints use validated v8 `recipe_requirements`. Legacy v7 records leave recipe costs explicitly unavailable. A single completed ore batch may still leave insufficient iron for a plate; inspect output and repeat refinement as needed.
- Printed stock and carried physical plates are distinct. Collection needs 1 kg stock plus host-validated reach/free hand/capacity. Shared stock never proves who produced it.
- Physical plate recycling is the existing immediate `recycle_component` command, not the `salvage.plate` stock recipe. It consumes the selected carried plate, spends a fixed 500 J and returns 1 kg iron only if accepted; power, ownership and receiving capacity remain host checks. Reprinting spends the observed recipe's resources again.
- An active recipe, including a power pause, is pending work. Acceptance, cancellation and job disappearance do not prove completion. Current outputs are reported as stock, never as a completed tutorial or confirmed session stage.

## Verification

Windows Godot 4.7.2 source checks use the repository's bounded runner, without network ports or local receivers. Focused task-guide checks pass after fixture corrections: real finite extraction/unloading, two refining batches, power pause/resume, printing/collection, rejected/accepted wall placement and recovery, rejected/accepted physical recycling with exact energy debit, cancelled/restarted reprint and observed output. Every runtime refresh compares canonical world snapshots. No resources or progression are granted by the helper.

Synthetic projection variants separately check absent canister despite reach, workstation body/reach/hand unavailability, recycler power and 499/500 J boundary, alternative recipe energy/input requirements, legacy unknown costs, invalid data and clearing. They are presentation fixtures, not evidence of live commands under those conditions. The fixture uses the new observed recovered-plate identity after wall removal.

Final runner evidence and exact-head CI are recorded in the PR handoff. Ignored logs/JUnit live under `var/ci/observed-guide-final/`. No graphical capture, integrated viewport readability, human keyboard/mouse discovery, fresh-user completion, controller, VR, Linux local execution or deployed/exported validation is claimed. Tutorial readiness remains gated on the fresh-user run described in `basic-gameplay-tutorial-readiness.md`. No fixed ports, media, AI imagery, new assets, third-party provenance, gallery/LFS/public upload, release, merge, deployment or dev-master push is included. All first-party changes remain MIT.
