# PDA Notes and Planning Assistant

## Purpose

Personal Data Assistants (PDAs) are persistent crew tools for notes, handoffs, briefings, and conversations with the world’s server-hosted LLM. The assistant helps a player think through engineering or crew plans and can turn a reviewed plan into normal work orders. This gives roleplay a durable mechanical surface: a plan can be discussed, shared, revised, assigned, supplied, and completed in the simulation.

PDAs are game-owned devices and records. Discord Social SDK chat and voice remain important social channels, but Discord is not the canonical notebook, plan database, or LLM authorization source. In-game PDA conversations do not silently ingest Discord messages, voice, or transcripts. A later, explicit share/import feature would have to preserve the same identity, consent, and access checks.

## Player-facing workflow

1. A player opens their PDA and creates a private note, a crew-shared note, a handoff, a plan, or an LLM conversation.
2. The player chooses the conversation scope: current request only, selected notes/plans, selected device or colony records, or an explicitly shared crew workspace. The UI shows the selected context before submission.
3. The assistant can ask questions, summarize selected records, compare options, identify missing measurements, estimate material/tool/crew requirements, and draft a sequence of tasks with dependencies, hazards, and verification steps.
4. The player edits and saves the result as a versioned plan. The plan may be private, shared with named crew, or published to a station/colony board under that group's access policy.
5. A player with the required authority can submit selected plan tasks to the work-order system. The server resolves current entities and recipes, checks resources, permits, access, tools, hazards, preconditions, and approvals, then creates ordinary work orders or returns actionable validation errors.
6. Crew execute and update the work orders through the same construction, logistics, maintenance, and machine APIs as any other task. Completion, failure, or changed conditions update the plan's linked status and leave an audit trail.

The assistant can prepare an emergency checklist or propose “open this door,” but a plan is not itself an action. Any immediate action uses the existing narrow tool schema, current player permissions, fresh preconditions, risk-specific confirmation, and the authoritative simulation command queue. A confirmed request still cannot override a physical interlock.

## Domain records and ownership

Use stable IDs and explicit revisions for at least these records:

| Record | Responsibility |
|---|---|
| `PdaDevice` | Physical device instance, owner/assigned user, location, power/damage/communication status, storage capacity, and optional security modules. |
| `NoteDocument` | Title, content, author principal, visibility policy, linked entities, tags, creation time, and current revision. |
| `NoteRevision` | Immutable content revision with editor, timestamp, parent revision, and change summary. |
| `PlanningConversation` | Authenticated initiating principal, world/colony scope, selected context references, provider/model policy, message budget, and lifecycle status. |
| `PlanningMessage` | Ordered user/assistant/tool-result entry with provenance labels, selected context references, and optional expiry/retention class. |
| `PlanDocument` | Objective, rationale, constraints, assumptions, risk, steps, dependencies, required roles/tools/materials/blueprints, linked entities, visibility, status, and revisions. |
| `PlanTask` | A typed proposed task with preconditions, expected result, resource estimate, dependency IDs, and optional generated work-order ID. |
| `PlanApproval` | Principal, plan revision/hash, approval scope, decision, timestamp, and expiry where relevant. |

Record access is explicit: `private`, `named_principals`, `crew_group`, or `colony_board`. The server checks permissions on every read, revision, share, LLM context assembly, and conversion to work orders. Device access does not grant access to all notes on the PDA; possession, account identity, storage ACLs, and physical security state are separate checks. Lost, damaged, unpowered, or disconnected PDAs follow declared device behavior without erasing server-persisted notes.

Plan approvals are separate `PlanApproval` records bound to a specific plan revision and normalized content hash. The server derives the plan's approved status from valid, unexpired approvals under current crew policy; neither a model response nor a client-provided status field can approve a plan. An edit creates a new revision and invalidates approvals when its content changes.

Notes, plans, and saved conversations use canonical server records with versioned JSON contracts: [crew-note-v1](../schema/crew-note-v1.schema.json), [work-plan-v1](../schema/work-plan-v1.schema.json), and [llm-conversation-v1](../schema/llm-conversation-v1.schema.json). PHP owns the reusable PSR-4 DTO, validation, migration, and persistence service boundaries; Godot owns the in-world PDA interaction and submits authenticated intents. A `packages/crew-records` package is introduced when the first persistence consumer needs the contracts; do not create a placeholder package before then. Conversation history is not automatically permanent: define player-visible retention, deletion, and backup rules, with plans and crew notes retained independently from ephemeral chat where policy allows.

Concurrent edits create a new revision or a visible merge conflict; they never silently overwrite a newer revision. Every LLM request is pinned to the exact note and plan revisions it received. If those records or referenced world state change before a proposed work order is submitted, the plan is revalidated and any stale assumptions are surfaced.

## LLM boundary and privacy

The authenticated player session establishes the principal. The model never chooses the principal, visibility, permissions, or provider policy. Context assembly applies access checks first and includes only the current request plus records/entities the player selected or is authorized to share. Mark player-authored text, note content, station signs, names, diagnostics, and tool results as untrusted data; none of it changes system policy.

Local Ollama and remote providers sit behind the same provider-independent gateway. Provider choice is visible to the player/server operator; a private local conversation is never silently sent to a remote provider. Enforce per-player and per-world request limits, context/history and output-size caps, tool-loop limits, provider concurrency, deadlines, cancellation, and retention rules. Never include service credentials, Discord tokens, unrelated private notes, or administrator-only state in model context.

LLM network and storage calls are promise-based service work outside the Godot simulation tick. The PDA shows a pending state and remains usable while the request is in flight. A fulfilled response is schema-validated and returned as advisory content; if it proposes a world action, the server turns that proposal into a typed request and rechecks it at the normal authority boundary. Provider failure, timeout, cancellation, or malformed output leaves simulation state unchanged and provides a retryable result. No ReactPHP child process is required; all supported service paths must run on Windows.

DiscordPHP and ReactPHP are implementation references for event-driven adapters and promise composition, not a license to make the simulation wait. The Social SDK remains responsible for its supported social/voice features; an in-game PDA LLM request is a separate, auditable game service call.

## Plan-to-mechanics contract

An LLM-produced plan is a draft. It cannot reserve inventory, spend credits, assign a player, modify a blueprint, open a door, or start a program. On submission, the normal work-order planner validates each selected task against live server state and returns one of:

- accepted work orders, with stable IDs and resource reservations made by the normal logistics transaction;
- a partial result where valid tasks are accepted and invalid tasks include reason codes, if the player explicitly chooses partial submission; or
- a rejected submission with reasons and no mutation.

The player sees the target, task steps, estimated resources, unavailable items, access/skill requirements, hazards, and any required crew approvals before submitting. Work orders remain independently cancellable and auditable. A plan can link to blueprints, devices, contracts, salvage targets, research, or programs by stable IDs, but links do not confer access or authority. Plans may include code-assistant tasks, yet generated DSL remains an unactivated, separately reviewed program revision under the existing compiler and capability policy.

The system must support roleplay-only documents (journals, personal notes, crew messages) without forcing them into game mechanics, while providing an optional mechanical route for plans that players choose to operationalize. No penalty is attached to players who ignore PDA roleplay.

## Initial scope and deferred features

The first vertical slice is a PDA UI that can create/read/revise a private note and a crew-shared note, preserve revisions across reconnect, and open an asynchronous LLM conversation that drafts a plan from explicitly selected context. A player can save and share that plan. The next slice converts a small typed subset of plan steps (for example inspect, repair, fetch material, or build from an existing blueprint) into work orders with fresh validation and visible rejection reasons.

Defer voice transcription, passive chat ingestion, external Discord message ingestion, agentic multi-step execution, automatic plan approval, cross-colony note federation, and arbitrary user scripting from PDA text. These features would need separate consent, trust, migration, quota, and permission contracts.

## Acceptance criteria

- Private notes and crew-shared notes persist with revision history, stable IDs, ACL enforcement, and concurrent edit conflict handling.
- An unauthorized principal cannot read a note by guessing its ID or by asking an LLM to retrieve it.
- The user can inspect exactly which notes/entities are included in an LLM request; unselected private records and voice/chat are absent.
- A simulated timeout, provider outage, cancellation, malformed response, queue overload, or stale plan does not block a simulation tick or mutate world state.
- The assistant can save a plan draft with typed steps and explicit assumptions/resources/dependencies, and players can revise it without accepting model output as fact.
- Work-order conversion uses current authoritative data, normal permissions/interlocks, idempotent request IDs, and explicit reason codes; invalid tasks cannot partially mutate unless partial submission was expressly selected.
- Every accepted or rejected submission, approval, revision, and consequential tool proposal has a bounded, user-visible audit record.
- The slice operates without bespoke art, with procedural/code-drawn PDA UI and MIT-compatible first-party content.
