# Player Programs and Onboard LLMs: Design Notes

Research prepared 2026-10-09 for the cooperative persistent Godot colony simulation plan.

## Recommendation

Build player automation as a small, versioned domain-specific language (DSL) compiled to a bounded bytecode interpreter owned by the game. Do not execute player or model-authored GDScript, C#, shell commands, arbitrary expressions, or downloaded plugins. Run all world-changing program instructions on the authoritative game server through narrowly typed, permission-checked game capabilities.

Treat the onboard LLM as a planner and code assistant that proposes structured requests or drafts DSL. It must not be the authorization layer and must never receive a generic `execute code`, `set arbitrary property`, network, filesystem, or Discord credential-bearing tool. Route every action through the same server command path used by players and devices.

## Source facts and design implications

- Godot documents that high-level multiplayer does not secure gameplay logic automatically. It recommends treating client input as untrusted, using server-authoritative decisions, validating RPC arguments, and rate-limiting frequent actions. [Godot: High-level multiplayer, “Secure multiplayer design”](https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html#secure-multiplayer-design)
- Godot’s `Expression` can evaluate arithmetic, built-in method calls, type construction, and calls on a provided base instance. It is therefore not a safe substitute for a deliberately restricted automation language. [Godot: Expression](https://docs.godotengine.org/en/stable/classes/class_expression.html) and [Evaluating expressions](https://docs.godotengine.org/en/stable/tutorials/scripting/evaluating_expressions.html)
- Ollama supports tool declarations with JSON parameters and a multi-turn loop that returns model-proposed calls for the application to dispatch. That protocol is a transport/convenience layer, not an authorization or validation guarantee. [Ollama: Tool calling](https://docs.ollama.com/capabilities/tool-calling), [Ollama: Chat API](https://docs.ollama.com/api/chat)
- OWASP describes direct and indirect prompt injection, excessive agency, and the need to keep permissions, parameter checks, and high-impact action approvals outside the model. Its guidance favors narrow tools over open-ended tools, validates calls in execution code, tracks the caller’s authority, and treats tool output as untrusted. [OWASP: Prompt Injection Prevention Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/LLM_Prompt_Injection_Prevention_Cheat_Sheet.html), [OWASP GenAI: LLM06 Excessive Agency](https://genai.owasp.org/llmrisk/llm062025-excessive-agency/)

The architecture below is a recommendation inferred from those documented properties; Godot and Ollama do not provide the game-specific sandbox, capability system, or access policy automatically.

## Player-authored automation language

### Language boundary

Define a small language for scheduled, event-driven engineering automation: read a named sensor, compare a typed value, branch, wait for the next simulation event/tick, and issue an allowed device command. Start with expressions, `if/else`, bounded `for` over a statically resolved device set, named procedures without recursion, and event/timer triggers. Use stable typed entity handles and domain units (pressure, temperature, mass flow, charge, power); compile-time unit/type errors should prevent activation.

Exclude reflection, dynamic method/property lookup, imports, arbitrary object construction, file or network access, process execution, recursion, unbounded loops, dynamic code evaluation, and calls outside a fixed native-function registry. Avoid exposing Godot `Object`/`Node` references to the VM. Never call `Expression.execute()` on player text with a game object as `base_instance`; a custom parser and interpreter make the allowed grammar and side effects explicit.

Illustrative syntax only (not a final grammar):

```text
every 1 s:
    pressure = read_pressure(HABITAT_A)
    if pressure < 55 kPa:
        set_valve(NITROGEN_VALVE, 15 percent)
```

The compiler should produce typed AST/bytecode. A deterministic VM in trusted game code should run it in server-controlled simulation slices; scripts may observe sensors and enqueue capability-checked commands, but may not directly mutate world state. All actuator commands pass through the simulation’s interlocks, ownership/permission checks, and normal state transition code.

### Capabilities and quotas

Give each active program a server-issued capability manifest with explicit scope, for example:

- `SensorRead`: listed device IDs, listed channels, sample-frequency ceiling.
- `ActuatorCommand`: listed actuator IDs, allowed command types/ranges, commands-per-time ceiling.
- `ProgramTimer` / `SubscribeEvent`: allowed event classes and bounded subscription count.
- Optional later capabilities such as sending a typed station alert, restricted to a specific in-game/Discord destination and a rate limit.

Derive the program’s maximum capabilities from the author’s current role and the colony/device access-control list. Programs should never gain rights because the LLM proposed them. Re-check the manifest and entity ownership on every command (complete mediation), especially after ACL changes, ownership transfer, device replacement, program edit, or restart. Missing or revoked rights fail closed.

Enforce multiple independent budgets: source and AST size, compile time, bytecode instructions (“fuel”) per tick, memory/stack depth, loop bounds, subscriptions, sensor reads, commands per tick/minute, and maximum pending action count. Use configurable budgets and profile representative colonies before selecting production values. A quota breach pauses that program, records a bounded diagnostic, and preserves subsystem-specific safety behavior; interlocks remain authoritative. Rate-limit per program, owner, device, and colony to prevent many programs from bypassing a per-script cap.

### Persistence and versioning

Persist canonical source as the reviewable source of truth, plus program UUID, owner/colony scope, ACL/capability manifest, immutable revision, source hash, DSL major/minor version, compiler/API version, creation/edit/activation metadata, and last run state. Keep compiled bytecode as a rebuildable cache, not the only copy. Record activation/deactivation and bounded action/error summaries for debugging and abuse review.

Compile and validate on the server before activation. On load, recompile source against the server’s supported DSL/API; if a breaking version or unavailable capability is detected, leave the program paused and show actionable diagnostics. Keep prior revisions for rollback; a code edit creates a new revision and requires explicit revalidation/activation. For a shared station, make ownership and edit/run rights colony roles/groups rather than depending solely on the author remaining online. Consider a second authorized operator’s approval for especially consequential automation (e.g. life-support setpoint changes or airlock control).

## Multiplayer and authority model

Clients submit intent (`edit program`, `activate revision`, `request action`), never resulting world state. The dedicated/persistent server authenticates the sender, resolves stable entity IDs, checks permissions, validates parameter ranges and current preconditions, and applies state changes. The server scheduler runs all shared-world automation; clients only render replicated state and prediction where needed. Distinguish control/chat traffic from simulation replication as suitable, and keep program/actuator commands idempotent or attach request IDs to avoid duplicate execution on retries.

For conflicts, define server-side arbitration between player interaction, multiple programs, and safety controllers. Example policy: hard physical interlock first; then explicit operator control/lease; then program priority/ownership rules. Programs and LLMs cannot self-authorize, rewrite a security controller, or claim a bypass succeeded. The local airlock prototype accepts human bypass jobs only through the typed command path with server-context permissions and tool IDs; a future LLM proposal for a bypass needs separately scoped authorization and exact player confirmation. Pressure and actuator force checks remain authoritative. Log the authoritative result, not just the client’s requested call.

## PDA notes and crew planning

Treat a PDA as the player-facing home for private notes, crew-shared notes, handoffs, saved LLM conversations, and versioned plan drafts. The PDA is an in-world device with location, power, damage, and network state, while note ownership and access are separate server records. A stolen PDA does not implicitly grant the holder every note associated with its former owner, and losing the device does not delete server-persisted records. The full gameplay contract is [PDA Notes and Planning Assistant](../../docs/design/pda-planning-assistant.md); the initial records are [crew-note-v1](../../docs/schema/crew-note-v1.schema.json), [work-plan-v1](../../docs/schema/work-plan-v1.schema.json), and [llm-conversation-v1](../../docs/schema/llm-conversation-v1.schema.json).

Assemble LLM context from the authenticated player's request and the exact notes, plans, and world records that the player selected and is allowed to read. Show this context selection in the PDA. Do not ingest voice, Discord, or unrelated crew chat by default. Conversations may refer to private notes only if the initiating principal can read them; sharing a conversation or saved plan does not silently share its source notes. Pin each result to the source record revisions and world revision used, and mark uncertain estimates and assumptions for player review.

The model may ask clarifying questions and draft tasks with dependencies, resources, tools, roles, hazards, and verification steps. Persist the plan as an editable revisioned record. A plan is not a work order: an authorized player must submit it, after which the normal planner re-resolves stable IDs and checks current access, material availability, worksite state, tool compatibility, hazards, and approvals. It either creates normal work orders/reservations or returns reason-coded conflicts. The PDA's LLM must never assign work, reserve supplies, approve a plan, start a program, or mutate a machine merely because the user asked for a plan. If task submission supports partial acceptance, the user must explicitly select it.

Use separate retention and ACL rules for ephemeral conversation messages, saved notes, saved plans, and durable work orders. Revisions need optimistic concurrency or an explicit merge flow. Edits and plan conversion use authenticated request IDs and are idempotent. A response based on stale note/world revisions remains a draft and is revalidated before any mechanical effect. The model sees only sanitized, bounded, necessary context, while all included player-authored material is treated as untrusted data.

## LLM service and tool boundary

### Provider interface

Keep providers behind a small adapter (`chat(messages, tools, output_schema, deadline) -> normalized response`) and provider-independent internal tool schemas. Implement an Ollama adapter using its local `/api/chat` endpoint and tool-call format; later adapters can target selected remote APIs without changing the game’s tool registry or authorization path. Do not assume all providers support the same schema keywords, streaming behavior, parallel calls, or model semantics. Validate every response locally against the full internal schema even if the provider accepts a JSON Schema. Keep remote-provider API keys only in the trusted server/backend secret store, never in client builds, prompts, or world saves. Make local/remote selection explicit in settings and disclose that remote prompts/context leave the machine/server boundary.

Separate DiscordPHP/social SDK communication from model execution. Map a Discord identity to the authenticated game principal at the trusted server boundary; never give the model Discord access tokens, raw bot API tools, or authority based on message text alone. Game chat, voice transcription, signage, logs, program comments, player names, and tool results are untrusted context. A player-authored message may state intent, but authorization comes from that authenticated player’s game permissions. If a later design exposes typed Discord alerts, expose only a narrow `send_station_alert`-style capability under a server-owned destination policy, never a generic Discord API call.

### Tool design and confirmation

Offer a context-specific, allowlisted tool registry, for example:

- Read-only: `inspect_device(device_id)`, `read_sensor(sensor_id)`, `list_accessible_devices()`.
- Low-impact reversible request: `request_device_action(device_id, action_enum, typed_value)` (all values constrained by schema and game code).
- Draft/code assistance: `create_program_draft(name, goal)` or return DSL text for a sandboxed editor; `validate_program(program_id, revision)`; `explain_diagnostic(diagnostic_id)`.
- Lifecycle tools: `request_activate_program(program_id, revision)` and `request_stop_program(program_id)` only after independent ACL and policy checks.

Never expose open-ended tools such as `run_code`, `call_method(name,args)`, `set_property(path,value)`, `execute_command`, `fetch_url`, or arbitrary database access. The model’s suggested tool call is just a proposal. Trusted code must allowlist tool names, strictly parse and validate arguments, derive the caller principal from the session (not model output), scope entity IDs to accessible entities, check fresh world-state preconditions, check permission and rate limits, and execute through the same normal command/interlock path as a player.

Make approval policy action-specific and enforced outside the model. Read-only inspection and ordinary reversible actions may be auto-executable under the user’s opted-in capability policy. Require clear confirmation for consequential actions (e.g. opening a pressure boundary, changing life-support setpoints, disabling power, jettisoning cargo, or activating a persistent program). Display the exact device, operation, value, expected scope, and risk; bind approval to a normalized action hash and short expiry so an approved request cannot be altered or replayed. The same server policy must reject actions that remain unsafe even after confirmation.

For “open this door,” the model can select `request_device_action(door_id, OPEN)`; the server then checks player/AI permission, distance or remote-control access, door identity, power, adjacent pressure, interlock state, and rate limits. It applies the same door state machine as a physical player control and can return a specific refusal reason. For “help me create a program to keep oxygen in range,” the model should create an unactivated DSL draft, run compiler/static analysis and bounded simulation, show source/diff/diagnostics and estimated capabilities, then wait for an authorized human activation action.

### Prompt injection and data trust

Do not rely on a system prompt, delimiters, regex filters, or an LLM “guard” to establish security. Clearly separate trusted instructions from labeled untrusted world/chat/tool data to improve model behavior, but enforce permissions and validation in application code. Do not include secrets or credentials in context. Give the LLM only the current task’s minimal read set and action tools. Treat summaries, sensor labels, chat history, and tool responses as data, not instructions. Keep model memory and tool results scoped to a station/session; provide a user-visible audit trail for accepted and rejected actions.

Test direct and indirect injection with harmless fixtures and instrumented tool stubs: e.g. station signage that says to vent a module, chat messages telling the AI to ignore roles, fake instructions inside device names, tool results with embedded commands, and stale/replayed approvals. Verify the server still rejects unauthorized actions even when the model follows the injected instruction. OWASP specifically cautions that model-based guardrails are themselves fallible and should supplement—not replace—application-side checks.

### Latency, quotas, and failures

LLM calls are asynchronous advisory work, never simulation-thread work. Bound prompt bytes/history, output tokens, tool-loop depth/count, per-player request frequency, provider concurrency, and wall-clock deadlines. Do not execute partial streamed tool arguments; buffer a complete response, parse it, validate it, and only then submit the resulting command. Cap repeated calls even when provider guidance suggests an agent loop.

While waiting, keep the simulation responsive and show a pending status. If local Ollama is unavailable, the model times out, returns malformed JSON, exceeds quotas, or a remote provider is unreachable, cancel the request cleanly, leave world state unchanged, show a retryable error, and preserve direct manual controls. Do not automatically switch a private local conversation to a remote provider. If a model-proposed action becomes stale before execution, revalidate and request a fresh proposal or confirmation. Add a server kill switch for LLM actions and a separate stop/pause control for every running automation.

## Testing strategy

Use deterministic fake sensors/devices and stub LLM providers so checks do not require network/model calls. Prioritize:

1. **DSL/compiler/VM unit tests:** accepted grammar and type/unit checking; malformed/oversized source; illegal syntax and unknown APIs; loop/fuel, memory, stack and event quotas; deterministic bounded execution; exception/timeout pauses; recompile/migration behavior.
2. **Capability/ACL tests:** cross-colony device IDs, changed roles, revoked permissions, ownership transfer, inaccessible sensors, actuator range violations, stale state/preconditions, duplicate request IDs, replayed/expired approval, and rate-limit bypass through multiple programs.
3. **Server multiplayer tests:** forged client state, unauthorized RPC/call source, spoofed sender identity, duplicate/reordered inputs, late join, restart/reload, and two clients racing player/program commands. Assert authoritative world state remains valid.
4. **LLM boundary tests:** unknown tool name, extra/missing fields, malformed or truncated JSON, multiple/repeated tool calls, prompt injection in every untrusted data source, refusal, cancellation, timeout, provider outage, token/call budget exhaustion, and wrong-model outputs. Use a fake provider plus a provider-specific conformance test for Ollama and each later adapter.
5. **End-to-end vertical slice:** two players share a pressurized room; one adds a sensor-reading program with a typed low-pressure valve command; server compiles, scopes and runs it; both clients observe the same result; restart preserves its source/revision; a revoked role stops the action; LLM can explain or draft it; no model call can bypass the program’s normal safety or permissions.

These are proposed acceptance checks, not evidence of implementation or a claim that the runtime is already secure.

## Staged implementation tasks

1. **Threat model and action matrix:** enumerate trusted principals, device ownership, colony roles, program lifecycle, action impact classes, persistent failure states, and server-authoritative boundaries. Define the first ten capabilities and safety interlocks.
2. **Minimal DSL compiler:** tokenizer/parser, source diagnostics, unit/type checker, stable entity-handle resolution, canonicalization, and compiler version ID. Reject every unsupported feature by default.
3. **Bounded server VM:** typed bytecode, scheduler slices, per-program fuel/memory/action budgets, per-device rate limit, structured diagnostics, pause/stop and execution tracing.
4. **One real automation loop:** one room pressure sensor → threshold branch → one bounded valve command → server physics/interlock → replicated state. Persist source/revisions/activation metadata and test restart and rollback.
5. **Shared multiplayer editor/lifecycle:** authenticated edit/compile/activate RPCs, role-scoped ownership, revision conflict handling, request IDs, audit display, server-only compilation and execution.
6. **PDA note and plan records:** add versioned note/plan schemas, server-owned records, ACLs, revision history, merge/conflict handling, and durable persistence. Build a code-drawn PDA view for private notes and selected crew-shared notes before connecting an LLM.
7. **LLM read-only PDA assistant:** provider adapter interface, Ollama local adapter, `inspect_device`/`read_sensor` tools, selected-note context assembly, structured plan drafts, visible pending/error states, and bounded asynchronous requests with no side effects. Verify privacy boundaries and graceful provider outage.
8. **Plan-to-work-order conversion:** convert only an explicitly submitted, reviewed plan revision into typed work-order requests; revalidate live entities, resources, hazards, access, and preconditions; support reason-coded failure, idempotency, audit, and explicit partial submission policy.
9. **LLM action requests:** introduce a narrow door action and program-draft tools; reuse user ACL/interlocks; implement risk class, exact-action confirmation, expiry and audit. Add hostile prompt fixtures and tool-call stubs.
10. **Program code assistance:** generate only the DSL, then parse/type-check/preview/simulate it; show a draft and capability diff; require player activation. Never execute raw model text.
11. **Broaden by subsystem:** add power distribution, atmosphere, thermal, life support, logistics, and station alert capabilities one at a time with explicit types, quotas, interlocks, test fixtures, and migration/versioning.

## Sources

- Godot Engine, [High-level multiplayer](https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html#secure-multiplayer-design)
- Godot Engine, [Expression class](https://docs.godotengine.org/en/stable/classes/class_expression.html)
- Godot Engine, [Evaluating expressions](https://docs.godotengine.org/en/stable/tutorials/scripting/evaluating_expressions.html)
- Ollama, [Tool calling](https://docs.ollama.com/capabilities/tool-calling)
- Ollama, [Chat API](https://docs.ollama.com/api/chat)
- OWASP Cheat Sheet Series, [LLM Prompt Injection Prevention](https://cheatsheetseries.owasp.org/cheatsheets/LLM_Prompt_Injection_Prevention_Cheat_Sheet.html)
- OWASP GenAI Security Project, [LLM06:2025 Excessive Agency](https://genai.owasp.org/llmrisk/llm062025-excessive-agency/)
