# Seeded away missions

## Requirement and status

Players can create a seeded procedural planet as a temporary away-mission instance. When the crew leaves and the mission ends, the instance is permanently destroyed. **Anything left inside is lost**, including items, resources, constructions, vehicles, containers and their contents. It cannot later be recovered by returning to the seed.

This is a planned, explicitly disposable lifecycle alongside persistent colonies/planets. Temporary missions use the [procedural generation and streaming abstractions](procedural-planets-and-memory-budgets.md); creating a whole planetary descriptor does not require allocating a whole planet in RAM. No mission runtime is implemented yet.

## Identity and lifecycle

Give every creation a fresh mission instance ID plus the chosen seed, generator/content version, access/crew policy and bounded region/memory budget. The seed reproduces the baseline landscape; it is not an ownership key or a saved planet identity. Reusing a seed creates a new instance and does not restore abandoned assets, inventories, corpses, edits or depleted deposits.

Proposed lifecycle: requested, admitted, active, departure pending, closing, retired. Admission checks server permissions, finite active-instance capacity and available budgets. Multiple players share one instance rather than generating separate copies for the same crew. Party/session membership, authoritative presence and transport dependencies determine occupancy; camera distance alone cannot end a mission.

Normal completion requires all active participants and their chosen transports to have crossed out of the mission, with entry closed and transfers resolved. One player leaving does not delete a mission occupied by others. Leaving the local surface region for an orbital rendezvous inside the same mission does not count as departure. Explicit mission completion, return transport or a configured closure trigger ends the instance; define each entrance/exit in the mission policy.

Disconnection is not a successful evacuation. Use a documented reconnect grace/abandonment policy, then close the abandoned mission under its disposal rules. A forced/admin closure handles remaining participants through an explicit abort/loss outcome, never leaves clients controlling deleted bodies. Player accounts/control identities survive; a body or equipment left behind is lost, and subsequent respawn/recovery eligibility follows campaign rules. Automatic evacuation must not quietly export abandoned possessions.

## Extraction and loss

Travel crosses an ownership boundary. Commit exports atomically: stable entity identity, contents, cargo/material quantities, passengers, motion/frame and request receipt move to the persistent destination before departure is acknowledged. Failed or pending exports remain mission-owned. Retried transfers cannot create duplicate ships/items or credit salvage twice. Imports use the same rule; equipment taken into the mission can be lost if not extracted.

On closing, seal ingress and reject new interaction/build/travel intents into the instance. Resolve or cancel in-flight transfers, jobs, agents and service requests using explicit receipts. Material already exported remains persistent. Everything still owned by the mission at final retirement is discarded under the mission-loss rule, not converted into free salvage or returned to its original owner. Do not infer extraction from a client's location or disconnect.

Destroy remaining structures, inventories, terrain edits, entities and physical state as one logically completed lifecycle outcome. Record bounded aggregate loss accounting and any necessary control/transfer outcomes, not a permanent copy of every abandoned item. Persistent relationships must not reference retired objects; ships, docking links, program targets, PDA references and remotely operated bodies need invalidation or a defined unresolved-reference display.

Players must see that the destination is disposable before committing travel. Mission status should show remaining crew/transport dependencies and the final departure condition. Completion feedback states that remaining property is lost. This is a gameplay boundary, not a per-item approval popup; the final closure rule is part of the mission contract.

## Cleanup and memory guarantees

Retirement prevents re-entry and regeneration under that instance ID, cancels generators/prefetch, stops AI/program execution and removes physics bodies, scene nodes, region owners, caches, decoded data and queued results. Late service/worker results carry the instance lifecycle generation and reject after closure. Cleanup must cover server state and every connected client's presentation; workers hold reservations until they actually exit.

Define cleanup completion as **no remaining mission-owned live state or unaccounted in-flight work/resources**. Verify references, worker counts, residency pins, owner registries and tracked CPU/GPU bytes against the pre-mission baseline. GPU retirement and allocator pools may release later or retain reusable allocations; ending a mission cannot guarantee an immediate drop in OS-reported memory. Bounded reusable pools are allowed, but must not retain the retired mission's gameplay data or grow with every completed mission.

Crash recovery must finish closure. Persist an idempotent retirement marker and essential transfer/control receipts before deleting active-instance storage, so a restart cannot resurrect the mission or duplicate exports. Retain only bounded administrative/accounting records and lifecycle identifiers; compact or garbage-collect markers once no replay/reference can revive them. This metadata is distinct from retaining a playable planet. All mission payloads/edits/checkpoints become deletable after retirement commits.

## Economy and implementation stages

Creating fresh resource-bearing worlds is an intentional supply source. Versioned mission policies can constrain creation frequency, travel costs, contracts, extraction capacity and resource/threat distributions. Record generated imports to the persistent economy explicitly. Repeating a seed may generate a fresh baseline, but cannot replay an earlier extraction receipt or restore the previous instance's cargo.

1. Define versioned instance/seed, crew/presence, ownership, closure and loss contracts with synthetic regions.
2. Implement bounded admission, shared participation, ingress/departure and atomic cargo/body/transport transfers.
3. Add closure/retirement, abandoned-state deletion, client invalidation and cancelled/late-result rejection.
4. Integrate procedural surface streaming, salvage/terrain edits and resource generation within the same budget manager.
5. Add crash-safe retirement, reconnect/forced-abort rules, economic policy and extended create/complete soak profiling.

Acceptance checks include multi-crew departure, orbital rendezvous, imported ship abandonment, cargo extraction retries, nested containers, disconnected bodies, pending saves/LLM/generation jobs, crash during closure, same-seed recreation and hundreds of mission cycles. Verify permanent loss of unexported property, no orphaned identities/references, no resurrection and bounded resident memory after cleanup.
