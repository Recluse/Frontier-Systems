# Planet-start civilization progression

## Roadmap decision

The project owner specified a later game mode/update where players start on a planet and develop a civilization through successive technological capabilities until reaching the space age. Civ13 is the primary reference for this milestone. The owner reports being one of its lead developers and explicitly authorizes consultation of any Civ13 code and assets as references.

The first playable continues to prioritize environmental extraction, container storage, refining and recycling. Civilization progression builds on that resource loop after it is playable. No civilization runtime or technology unlocks are implemented by this document.

## Gameplay direction

Players establish settlements, collect and process resources, develop tools and infrastructure, organize production, and eventually construct vehicles and spacecraft. Orbital operations then connect to the existing Moon/Mars colony, shipyard and interplanetary roadmap. Early equipment remains reusable, repairable or recyclable as better processes become available.

Initial progression categories for design discussion:

| Stage | Gameplay capabilities |
| --- | --- |
| Settlement | Environmental collection, portable storage, basic tools, shelter, food and water |
| Material processing | Kilns, smelting, alloys, improved extraction and durable equipment |
| Industry | Mechanized production, power generation, transport and scalable logistics |
| Advanced engineering | Electronics, automation, precision fabrication and advanced chemistry |
| Space access | Life support, propulsion, launch infrastructure, orbital construction and navigation |
| Interplanetary civilization | Multiple colonies, shipyards, trade and travel between worlds |

These are proposed capability groupings, not copied Civ13 era definitions or approved balance values. Progress depends on functioning infrastructure and acquired knowledge, rather than replacing the entire world when a global timer changes era. Different settlements may progress at different rates and exchange resources or knowledge. Detailed research, politics, governance and conflict rules remain to be designed with the owner.

## Shared architecture

- Represent progression with stable technology, process and capability IDs and versioned prerequisites. Use composition; avoid parallel ancient/modern versions of every system.
- Recipes and blueprints describe materials, tools, energy, environmental requirements and required knowledge. Player, NPC and LLM operators use the same authoritative capability checks.
- Research grants knowledge or process availability. It does not conjure resources, buildings or electricity. Keep material transactions and physical construction authoritative.
- Separate civilization knowledge from body/species/role permissions and physical machine capabilities. A knowledgeable player still needs an operable tool or machine.
- Keep settlement/organization progression separate from a universal era counter. Persist unlocks, research work, ownership and grants explicitly.
- Reuse the inventory, refining, recycling, power, chemistry and construction systems across stages. Old equipment keeps stable identity and recoverable material.
- Plan explicit data migrations when recipes, prerequisite graphs or technology definitions change. Never retroactively complete research or reset extraction sources on load.
- Servers choose starting capabilities through scenario configuration. Existing space-age colony starts remain possible alongside the later planet-start scenario.

## Starting-world constraints

The origin planet is not yet selected. Its atmosphere, gravity, climate and available resources must support the configured starting equipment and survival model. Do not assume primitive unaided humans can survive on Mars or the Moon. Choose a viable origin world or explicitly provision the infrastructure required by a hostile environment. Era progression must remain separate from procedural planet generation and should work first on a bounded authored planet region.

## Civ13 reference workflow

The [Civ13 README](https://github.com/Civ13/Civ13/blob/0d38999d5f9f987a944493f11c456537f39ac2f6/README.md) identifies a historical SS13 game spanning multiple epochs with roleplay and combat modes. Its [repository LICENSE](https://github.com/Civ13/Civ13/blob/0d38999d5f9f987a944493f11c456537f39ac2f6/LICENSE) declares AGPL-3.0. This review covers those metadata files only; no progression code or creative assets have been reviewed or imported yet.

Use the owner's reference authorization to review relevant code/assets at pinned revisions and record exact paths and independently expressed requirements in `docs/research/reference-manifest.csv`. Candidate future topics include progression prerequisites, extraction/crafting chains, persistent settlement state, resource scarcity and cooperative roles. These are planned review topics, not claims about currently verified Civ13 implementations.

Frontier Systems' MIT requirement remains in force. Reference consultation does not by itself establish MIT redistribution rights for copied or adapted files, including inherited upstream SS13 content. Before importing any code or creative asset, establish its authorship and file-level rights; original owner-controlled material may qualify for separate permission, while contributions and upstream material need their own clearance. No Civ13 dependency or asset is added in this milestone note.

## Later implementation sequence

1. Finish the first playable extraction/container/refining/recycling route and its persistence/multiplayer gates.
2. Review selected Civ13 progression and production paths with the owner, recording their exact revision and independent requirements.
3. Implement a technology prerequisite contract and server-owned knowledge/progression owner, with bounded work and snapshot semantics.
4. Add a small planet-start scenario with one settlement and a short production/technology chain.
5. Expand industry, logistics and cooperative specialization before connecting launch and orbital infrastructure.
6. Integrate the space-age transition with the existing colony/ship systems while preserving world ownership and material conservation.
