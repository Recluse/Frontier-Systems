# Project instructions

## Architecture

- Godot is the real-time client and authoritative simulation runtime. Keep canonical world state in simulation systems and persistent records, not in UI nodes or cached presentation data.
- Use composition through typed components and data-driven definitions. Prefer small interfaces and explicit ownership over deep inheritance trees or global singletons.
- Tools use independent, repairable, replaceable and upgradable component records and data-driven materials/mounts/capabilities. Space-tier routine wear is conservative; apply wear to completed work rather than simulation ticks. Keep detached parts and their material provenance, and preserve useful partial functionality.
- Ship and component damage should usually degrade or disable capabilities while preserving stable parts for repair and salvage. Do not equate zero integrity with deletion or occupant death.
- Gas and liquid pressure systems share versioned volume/port/network contracts, with documented units, conservation assumptions, and phase-specific behavior. Docking, EVA suits, small craft, and remote bodies use the same authoritative command and capability rules.
- PHP services are separate Composer packages or applications under `packages/` and `services/`. Every PHP namespace must be PSR-4 autoloadable and every PHP file must declare `strict_types=1`.
- Use ReactPHP event loops, promises, HTTP, sockets, and cache interfaces for service work. Never make a simulation tick wait for Discord, Steam, persistence, or an LLM response.
- External asynchronous results must be validated and submitted as commands for a simulation tick. Do not let service callbacks mutate canonical world state directly.
- Keep Steamworks and Discord behind adapter interfaces. The server and database remain authoritative for identities, permissions, world state, and program execution.
- Generated programs and LLM output are untrusted data. Execute only through a bounded, deterministic in-game language and server-owned capability registry.

## Code and documentation

- First-party code, schemas, and created assets must be distributable under MIT. For shipped third-party creative assets, use CC0 by default; do not add fonts or other creative assets under a different license unless the project owner explicitly changes this policy. Track exact provenance and licenses in `THIRD_PARTY_NOTICES.md`; do not include anything until commercial use and redistribution are verified.
- PHP follows PSR-12 and documents public contracts in PHPDoc. Godot scripts use typed GDScript, `class_name` only for reusable types, and XML/Markdown documentation for assets and data definitions.
- Update architecture and API documentation in the same change as a contract change. Prefer machine-readable schemas and explicit versions for data exchanged across PHP and Godot.
- Use descriptive, stable IDs for systems, components, blueprints, and persisted records. Avoid behavior encoded only in display names or scene paths.
- Profiling counters and traces must be available without changing simulation behavior. Keep expensive diagnostics opt-in or bounded.

## Dependencies and workflow

- Pin or constrain dependencies deliberately. Keep third-party code in its own dependency boundary; do not silently fork or modify vendored libraries.
- Build foundational abstractions before feature-specific implementations. Each new system should identify its owner, tick cadence, persistence contract, failure behavior, and profiling signals.
- All runtime systems must run on Windows as well as Linux. Do not use ReactPHP child processes, `pcntl`, POSIX-only APIs, or shell-based runtime orchestration; prefer event-loop I/O and platform-neutral service protocols. Include Windows in CI for PHP and Godot changes.
- Runtime PHP platform restrictions and production dependencies are checked by `tools/check-windows-runtime-policy.php`; keep the scan focused on runtime `src/` code and production requirements so development tooling remains usable.
- Use `dev-master` as the integration branch. Optional feature branches should target it by pull request, and the checks in `.github/workflows/ci.yml` must pass before merge.
- Do not place secrets in the repository. Use ignored `.env` files locally and document required variables in `.env.example`.

## AI-assisted development

- Civ13 is the user's primary reference for later planet-start civilization-to-space progression. The user explicitly authorizes consultation of any Civ13 code/assets as references and reports being a lead developer. Pin reviewed paths/revisions in the reference manifest and express requirements independently. Reference authorization does not replace file-level rights clearance for copying/adapting material into the MIT project; distinguish owner-controlled originals from inherited code and other contributors' assets. Do not import a Civ13 file without verified MIT-compatible redistribution rights.

- Codex is the primary coding and review agent for this project. Claude may be used as a supplemental contributor or reviewer when it is available and useful; both must follow these instructions and the same subsystem contracts.
- Keep AI tasks narrow and reviewable. Give the task its relevant design contract, files and interfaces in scope, non-goals, acceptance criteria, and the checks to run. Avoid simultaneous edits to shared schemas or authority boundaries.
- Treat generated code, plans, schemas, and asset suggestions as proposals. Review every diff for correctness, permissions, persistence, Windows compatibility, documentation, and license provenance before accepting it.
- Use `docs/research/reference-manifest.csv` for pinned source references. The user authorized narrow `/tg/station` code consultation for behavioral or architectural research; do not transcribe upstream code into this MIT project, and record each reviewed path and its independent requirement. Baystation's current README says generative AI is not welcome: never provide Baystation source or source-derived excerpts to AI systems; use only human-written requirement notes. A repository-level license does not authorize code reuse; any proposed reuse needs file-level rights review and explicit approval.
- Keep model use out of runtime authorization. LLM output and player-authored programs must pass the same server-owned schemas, capability checks, limits, and command validation as other inputs.
