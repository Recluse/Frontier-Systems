# Consciousness record and pure assessment

## Implemented scope

`ConsciousnessState` and `ConsciousnessPolicy` under `src/core/health/` provide detached v1 state records and pure plans. They do not register a simulation system, mutate world state, administer chemicals, apply injuries or enforce player input. This is the first code foundation for [health and consciousness](../design/health-medicine-and-chemistry.md).

State includes body ID, revision, `alert`/`impaired`/`unconscious`, last assessment tick, last transition tick, recovery start tick and up to sixteen current cause records. Each cause has a stable unique ID, a registered kind and integer suppression 0..1000 permille. Kinds are injury, chemical, oxygen delivery, circulation and temperature. These values are fictional tuning observations, not medical measurements or drug quantities. The future physiology/exposure owners must derive them from canonical injuries and finite chemicals.

Records validate exact fields, bounded integral numbers, timing order and state/cause consistency. JSON integer-valued floats normalize to integers. Cause order canonicalizes by ID; observations and plans are detached. The schemas describe causes, state and plan v1. Default alert and combined injury/sedation fixtures live under `data/health/`.

## Assessment rules

Combine suppression by addition, saturated at 1000. Cause replacement represents a full fresh trusted observation set, not an instruction to clear injuries or chemicals. Distinct IDs must refer to genuinely distinct physiological contributors; the future owner must prevent duplicate exposures under different IDs. Clients, scripts and LLMs cannot supply trusted suppression or omit remaining causes.

| Rule | Prototype behavior |
| --- | --- |
| Knockout | Combined suppression >=750 enters/remains unconscious |
| Unconscious hold | Suppression >500 prevents recovery and clears progress |
| Recovery | Suppression <=500 for 60 ticks of sufficiently frequent assessments permits waking |
| Assessment gap | More than six ticks between assessments restarts the recovery interval |
| Wake state | Suppression >=250 wakes impaired; lower suppression wakes alert |
| Impairment | Alert enters impaired at >=250; impaired returns alert at <=150 |

At the existing 60 Hz world rate, these provisional values correspond to one second of recovery and a maximum 0.1 second assessment gap. Tick intervals are contract values; the policy itself neither reads nor changes the engine rate. Intervening observations must represent the configured health scheduler; it cannot detect an injury that an upstream owner failed to report.

Assessment requires a strictly newer bounded tick and revision capacity. Each plan advances revision once, even if posture/state is unchanged; transition tick changes only on an actual consciousness transition. Recovery uses -1 when inactive. Plans return before/after records, bounded suppression, transition flag and `consciousness_allows_voluntary_actions`. That flag is one capability input, not blanket permission: alert or impaired bodies may still be dead, restrained, injured or otherwise unable to act.

## Authority, persistence and limitations

[Consciousness ownership](consciousness-ownership.md) provides a single-body atomic owner with revision checks and saved receipts, now composed inside [world health scheduling](health-runtime.md).

The health adapter must validate trusted fresh causes and current revision/tick before committing. Body/life applicability and real physiology remain future integration. Do not accept plans as client mutations. World snapshots now preserve owners, source causes and recovery scheduling; skipped assessments do not grant free recovery.

Consciousness is separate from death, sleep, paralysis, posture and synthetic shutdown. This pure policy does not heal oxygen injury, metabolize sedation, consume supplies, release grips, interrupt jobs, alter identity or suppress VR poses. Those integrations are required before exposing gameplay knockout or sedation. The existing linear motion/physical grip and inventory systems remain unchanged. No PHP service call or external wait occurs here.

## Verification and next steps

The focused Windows script `consciousness_policy_test.gd` checks combined causes, retained injury after chemical removal, interrupted and completed recovery, hysteresis boundaries, JSON recovery, detached inputs, missing-assessment gaps, repeated/old ticks, duplicate/unknown causes, invalid numbers/fields/timing/state, bounded cause capacity, saturation and revision exhaustion. Windows/Linux CI includes the script. Runtime authority, production input gating and physiological integration remain pending.

Next implement canonical injury/physiology records and transactions, then finite chemical exposure, voluntary-job/hand release and desktop/VR/agent capability enforcement. The registered scheduler already exposes bounded diagnostics; keep the pure policy free of mutable global counters.
