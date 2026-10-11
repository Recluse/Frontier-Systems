# Civilization and station gameplay capability parity

Owner direction (2026-10-11, America/New_York): almost everything a player can do in Civ13 and Space Station 13 should eventually be possible in Frontier Systems. This is a long-term gameplay capability milestone family, not a claim of current implementation or a single feature PR. Preserve the current basic-gameplay/tutorial priorities.

## Target and coverage

Track player capabilities and their outcomes, not identical controls, names, assets or internal code. Aim for broad coverage of both civilization progression and station life; record every gap and any proposed exclusion explicitly. Do not silently narrow this direction to engineering alone. Features may use Frontier's own design while preserving comparable player agency and emergent combinations.

Create a versioned capability matrix through staged research. Each row needs a stable ID, reference project/version/path or human-authored requirement source, independently expressed player action/outcome, Frontier subsystem owner, dependencies, status, acceptance evidence and any unresolved design decision. Statuses: unresearched, planned, implementing, verified, or exclusion proposed/owner-approved. Unknown capability coverage must not be presented as a percentage completed. Space Station 13 encompasses multiple codebases; identify the variant for each reference instead of assuming one universal feature list.

Initial research categories (planning taxonomy, not an audited exhaustive inventory):

- Character movement, anatomy, hands, inventory, equipment and interaction.
- Materials, mining, fabrication, tools, construction, deconstruction, repair and salvage.
- Settlement development, technology progression, agriculture, food, crafting and trade.
- Power, atmosphere, fluids, temperature, infrastructure, machinery and maintenance.
- Health, injuries, treatment, contamination and biological/environmental hazards.
- Roles, cooperation, communication, governance, access, records and social play.
- Transport, logistics, vehicles, navigation and eventual space travel.
- Conflict, security, emergencies, recovery and persistent consequences.

These categories become concrete capability rows only after source verification. Do not treat the taxonomy as a promise that any particular unreviewed upstream mechanic already exists.

The first bounded research slice is the [foundational capability matrix v1](foundational-capability-matrix-milestone.md), with pinned source excerpts, current owner/test pointers and explicit gaps. It does not establish full parity or fresh runtime verification.

## Milestone sequence and acceptance

1. Build the research matrix and coverage baseline, starting with Civ13 and a pinned owner-relevant SS13 variant. Prioritize ordinary basic actions and independently authored requirements.
2. Map foundational owners and contracts; implement bounded basic capability gaps before their advanced dependents. Serialize shared authority/schema work and keep each milestone narrow.
3. Deliver capability clusters with explicit scenarios: authorized success, unavailable prerequisites, stale/foreign rejection, conservation, partial damage/functionality, recovery and multiplayer effects where relevant.
4. Verify cross-system combinations and emergent use, not only isolated happy paths. Reconcile the matrix against integrated evidence and propose remaining gaps/exclusions to the owner through Coordinator.

Every runtime system retains Frontier's Godot authority, fixed-tick commands, typed composition, stable IDs, bounded work/profiling, versioned persistence and Windows/Linux compatibility. Async services cannot directly mutate world state. Use finite resource/inventory conservation and recoverable parts; do not import an upstream shortcut that breaks these contracts. Human usability and graphical acceptance stay separate from domain/transport tests.

## References and rights

Follow AGENTS.md: Civ13 consultation is authorized, but copying/adapting files requires verified file-level MIT-compatible rights. Narrow `/tg/station` consultation is authorized for behavioral/architectural research; independently express requirements and do not transcribe upstream code. Never feed Baystation source or source-derived excerpts to AI systems; use human-written requirement notes only. Other sources need applicable authorization/rights review. Pin reviewed paths/revisions in `docs/research/reference-manifest.csv`.

No upstream art, branding, fonts, audio or footage is imported by this milestone. First-party work is MIT; third-party creative assets require the existing CC0 policy/clearance. No AI image generation at any art stage. This direction authorizes roadmap planning and narrow successor selection, not releases, external services or public media uploads.
