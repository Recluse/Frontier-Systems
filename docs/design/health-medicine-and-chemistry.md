# Health, medicine and chemistry

## Direction and implementation status

Health and medicine should eventually provide the depth of play the project owner associates with Baystation: diagnosis, stabilization, treatment and chemistry as cooperative crew work. This is an independently authored design requirement, not a specification extracted from upstream source. Follow the repository's Baystation source-use policy; first-party implementation, definitions and assets must remain distributable under MIT.

**Partial runtime foundation:** the [consciousness foundation](../architecture/consciousness-foundation.md) and [atomic owner](../architecture/consciousness-ownership.md) compose into [world health scheduling and checkpoints](../architecture/health-runtime.md). Trusted retained sources and prototype injuries drive bounded assessment and saved recovery. Full physiology, finite chemistry and wider body-control enforcement remain pending. Other contracts below remain planned. Balance values are fictional game tuning, not real treatment instructions.

[Localized injury records](../architecture/localized-injuries.md) now track human part damage and oxygen injury, with queued trusted changes, saved v2 health state and derived knockout effects. Inventory incapacity is enforced. Physics-originated damage, finite treatment resources, full organs/species physiology and wider player controls remain pending.

## Gameplay requirements

[Combat, restraint and body transport](combat-restraint-and-body-transport.md) define the physical rescue/combat counterpart, including prone patients, carrying, stretchers, buckling and occupied containers. Posture and physical restraint remain separate from health and consciousness.

- Model localized body parts and organs, wounds, fractures, burns, bleeding, pain, infection, toxic exposure and loss of function. Avoid relying on a single health bar to represent every condition.
- Track systemic states such as circulating blood, oxygen delivery, temperature and consciousness independently of localized damage. A functioning lung cannot compensate for an unsuitable atmosphere, and fixing a wound does not instantly replace lost blood.
- Make triage and rescue useful: examine a patient, use instruments, control bleeding, protect breathing, transport them, and perform longer treatments with appropriate tools and facilities. Distinguish stabilization from repair and recovery.
- Support bandages, splints, medication, transfusion, surgery, prostheses and organ replacement in stages. Treatments require compatible anatomy, available supplies, capability and elapsed work; interrupted work has explicit consequences.
- Track biological viability, consciousness, action capability and revival eligibility separately. A living body can be unconscious or unable to move; a dead body can remain recoverable. Death does not delete the body, possessions, brain or recoverable materials. Brain transfer, cyborg construction and cloning integrate with a separate player identity/control owner so they cannot duplicate a player or create resources for free.
- Organic species use data-defined anatomy and physiology. Cyborg chassis use repair, power, cooling and module rules; an implanted organic brain can retain its own biological requirements. Station AIs have no assumed organic body. Hybrid bodies compose these capabilities.
- Provide roleplay through medical records, patient notes, diagnosis and specialist work. Examinations reveal observations with instrument limitations rather than automatically exposing every hidden condition or chemical.

## Consciousness, knockout and sustained unconsciousness

Consciousness is an explicit authoritative feature. Proposed states are `alert`, `impaired` and `unconscious`, with cause records and transition ticks. Sleep, physical stun, paralysis, prone posture and death are separate conditions: being knocked over does not automatically knock a player out, and inability to move does not prove unconsciousness.

Physics-derived trauma can cause a knockout through the injury/physiology policy. Injury consequences such as brain impairment, blood loss, inadequate oxygen delivery or systemic failure can keep a player unconscious while their causes persist. Chemicals can produce sedation and maintain unconsciousness through route-specific uptake, active exposure and metabolism. Initial fictional definitions should include a sedating effect with onset, effect strength, clearance and adverse effects; do not implement sedation as a client-supplied duration or a real-world drug/dose recipe.

Evaluate bounded contributions from all active causes together. Treating one cause or clearing one chemical cannot wake a body still suppressed by another cause. Chemical antagonism/stimulation may affect defined contributors but does not universally cancel trauma, restore circulation or revive a dead body. Further administration consumes finite chemicals and passes treatment/exposure validation. Adverse effects can worsen physiology; sedation is not an automatic safe-preservation state.

Use documented fictional thresholds, hysteresis and a minimum stable recovery interval to avoid oscillating between awake and unconscious every assessment. A player recovers when the remaining causes allow it, after stabilization, healing and/or chemical clearance as applicable. A brief trauma blackout can clear sooner than the injury itself; persist each cause's actual recovery rule. No elapsed timer alone guarantees waking while continuing injury/exposure still suppresses consciousness.

Unconscious bodies cannot intentionally move, attack, grip, resist, administer treatment, manipulate inventory or operate equipment through that body's capabilities. Incapacity transitions interrupt pending voluntary jobs and release active muscular holds through the existing owners; passive straps, supports and confinement remain. Autonomous equipment continues only under its own power, permissions and control owner. Client input, including tracked VR movement, must not move an unconscious canonical body or supply combat impulses. Login, reconnect, camera changes or switching to an agent cannot bypass the body's state.

Being unconscious preserves the player-to-body identity and physical presence. Other players can carry, drag, treat or search the body under their normal physical interaction rules. No resistance input should be fabricated for an unconscious target, and inaction does not grant broad access rights. Breathing, metabolism, bleeding and environmental hazards continue. Player presentation indicates loss of consciousness without exposing otherwise hidden surroundings/medical facts; any spectator policy is separate from body control.

Species profiles determine applicability. Synthetic chassis use explicit shutdown/control-failure states; an organic implanted brain may lose consciousness while independently controlled chassis safety systems remain active. Remote AI control must follow the configured brain/chassis control relationship rather than automatically restoring control to an unconscious player. Health owns cause/state decisions; identity/control and capability owners enforce their consequences.

Persist cause IDs, active chemical quantities/effect state, transition/recovery ticks and physiological scheduling alongside health revisions. Restore without free awakening, repeated dosing or repeated knockout events. Scope examinations to observable responsiveness and available measurements; exact hidden causes require suitable diagnostics. Profile cause evaluations, transitions, interrupted jobs and deferred assessments with bounded counters.

## Chemical gameplay

### Beneficial medicines

Drugs are useful treatment tools as well as possible hazards. The project owner cited Dexalin+ as an example of the desired oxygen-damage recovery role. Implement that role through an independently authored fictional medicine definition, with first-party naming, recipes, effect rules and balance values. This reference does not specify an upstream recipe or exact effect implementation.

Separate **current oxygen deprivation** from **accumulated oxygen-related injury**. An oxygen-recovery medicine can reduce the latter at a bounded rate while active and compatible with the patient's physiology. Continuing deprivation can still add injury during treatment. Resolve new injury and recovery in a documented stable order, clamp to valid bounds, and report both contributions; a medication does not silently repair a suit, refill a tank, remove environmental CO₂ or supply unlimited oxygen.

Define beneficial effects as typed, bounded policies targeting specific health variables:

| Treatment role | Intended gameplay benefit | Important integration rule |
| --- | --- | --- |
| Oxygen-injury recovery | Reduce recoverable injury caused by inadequate oxygen delivery | Check continuing breathing/circulation hazards independently |
| Tissue-repair support | Accelerate recovery of eligible wounds or burns | Severe structural injuries may still require procedures |
| Analgesia | Reduce pain-related impairment | Pain relief does not erase the underlying wound |
| Infection treatment | Suppress compatible modeled infections | Requires a registered infection/effect match |
| Toxin treatment | Neutralize or aid clearance of specific harmful substances | Account for reaction products and waste |
| Stimulation/reversal | Counter a defined suppression effect | Does not guarantee consciousness if other causes persist |

Each definition declares its valid targets, onset, active exposure range, maximum recovery rate, duration derived from metabolism, stacking rules, contraindications and adverse effects. Multiple doses combine through one exposure/effect policy with explicit caps; adding more containers or effect instances cannot multiply recovery without limit. Overdose risks are definition-specific, not an automatic penalty attached to every helpful medicine. Effects stop or change when cleared, incompatible, exhausted or blocked by physiology.

Medicine-assisted oxygen recovery may allow consciousness to return when oxygen-related suppression clears, but other trauma or sedating chemicals can still keep the body unconscious. Assess recovery and consciousness through the health owner rather than letting a drug directly force the player awake. Basic recovery medicines do not recreate destroyed organs, reverse death or replace cloning/brain-transfer workflows.

Acceptance fixtures should include injury recovery in a restored breathable environment, treatment during continuing deprivation, mixed injury/sedation, clearance ending an effect, repeated-dose caps, appropriate adverse effects, incompatible species/chassis, full-health bounds and restart/retry without duplicate healing. Quantitative values remain fictional tuning to be authored when the chemical/health runtime exists.

### Containment, exposure and reactions

Use one bounded chemical inventory contract for bottles, syringes, dispensers, machines, blood and other body compartments. Stable substance IDs refer to versioned definitions rather than names with hardcoded behavior. Containers declare capacity, compatible contents, seals, connectors and contamination state. Equipment may measure, mix, transfer, heat, filter or administer contents through shared ownership rules.

Substance definitions declare phase, material/species mappings, valid exposure routes, absorption and clearance rules, effects and compatibility. Route matters: swallowed, injected, inhaled and topical exposures use different pathways. Treatment effects, adverse effects, cumulative exposure, tolerance and interactions belong in bounded declarative policies. A chemical must not act as an unconditional instant health increment.

Reactions use explicit stoichiometry, required equipment, temperature/pressure envelopes, catalysts, duration and products/byproducts. Process sources and destinations atomically. Heating and synthesis require power/work and finite inputs. Declare every matter sink or output, including excretion, exhaust and waste; do not silently discard a dose after applying its effect. Medications, poisons, cleaning products, fuels and hydroponic nutrients can share chemical storage without sharing physiological behavior.

For the first chemistry contract, use integer micromoles for substances with known composition and explicit molar mass; derive mass through the material catalog. Complex biological fluids need separately defined conserved constituents or material batches, not a pretend molecule called blood. Do not convert all chemicals to volume with one arbitrary density. Capacity and phase handling require declared density/mixture approximations. Gas mappings must explicitly integrate with `GasMixtureVolume`; its current four-species catalog must not silently accept new chemicals.

Chemistry is deterministic authored gameplay, not an unrestricted molecular simulator. Initially permit only registered recipes/effects. Later mod packages may add validated definitions with limits and dependency checks, never arbitrary callbacks or executable code inside chemical records.

## Proposed ownership boundaries

Names below are proposed contracts, not existing classes or schema files.

| Owner/component | Responsibility |
| --- | --- |
| Anatomy definition | Stable part/organ slots, connections, species and replacement compatibility |
| Body health owner | Injuries, physiology, life state, exposure compartments and body revisions |
| Consciousness policy | Pure cause aggregation, hysteresis and recovery plans; committed by the body health owner |
| Chemical quantity owner | Finite contents, containment, revisions and atomic transfers/reactions |
| Exposure/metabolism policy | Pure bounded plans for uptake, transformation, clearance and effects |
| Treatment job owner | Reserved tools/resources, progress, interruption and completion receipts |
| Identity/control owner | Which player or agent controls a body, brain, cyborg or clone |
| Medical observation policy | Permission-scoped measurements, instrument error, records and disclosure |

Compose body capabilities rather than creating a deep species inheritance tree. Inventory items reference container/chemical owners without holding a second authoritative copy of their contents. Health references the existing stable body IDs; loss of a limb changes usable hands/equipment capabilities through an explicit transaction. Existing grip reservations, equipment and timed inventory jobs must be reconciled when body capability changes.

All gameplay changes occur through validated Godot fixed-tick commands. A deterministic bounded scheduler can assess physiology less frequently than the 60 Hz world tick, initially targeting 10 Hz with saved next-due ticks and fractional remainders. Event changes such as injury or administration apply at the accepting tick. Resolve simultaneous jobs in stable order. Limit bodies, compartments, active effects, recipes and work per tick; report deferred work rather than permitting unbounded reaction chains.

Commands validate identity, access, anatomy, reach, available hands/tools, patient movement/resistance, quantities and expected revisions. An inactive patient does not grant unrestricted persistent medical access. Server/LLM medical assistants receive scoped observations and may propose or queue allowed actions through the same registry; model output never determines canonical diagnoses, effects or permissions. PHP medical record/service integrations use PSR-4 packages and ReactPHP promises; callbacks enqueue commands without blocking simulation ticks.

## Persistence, documentation and profiling

Before implementation, define exact versioned schemas for anatomy, injuries, physiology, chemical definitions/contents, exposure and treatment intents/jobs/receipts. Specify units, ranges, ordering, integer overflow protections and migration behavior. Save canonical state, definition versions, quantities, owner revisions, job reservations and scheduler remainders together. A restart must not replay a dose, duplicate a transfusion or grant a free recovery interval. Unknown or incompatible definitions reject/quarantine explicitly rather than healing patients or deleting substances.

Player references should document observable symptoms, equipment capabilities and fictional chemical behavior. Internal API references additionally document ownership, tick costs and validation. New first-party effects and recipes must be authored independently; importing source-derived medical definitions is subject to the same provenance policy as code/assets.

Expose bounded counters for active patients/injuries/exposures/jobs, processed/deferred metabolism steps, reaction evaluations, transfer rejections and subsystem time. Keep detailed per-patient traces opt-in, permission-scoped and bounded.

## Staged implementation and acceptance checks

1. **Anatomy and health records:** human, synthetic and hybrid fixtures; localized wounds and separate life states; pure injury/capability plans. Check bounds, stable IDs, incompatible parts and detached JSON recovery.
2. **Runtime injury and stabilization:** authoritative owner and command/job integration; bleeding, basic bandaging/splints, injury-driven knockout and capability loss. Check interrupted jobs, reserved hands, competing treatments, conscious-but-immobile versus unconscious bodies, multiple continuing causes, recovery hysteresis and saved recovery.
3. **Chemical containment:** registered substances, sealed containers and exact atomic transfer plans integrated with inventory/material ownership. Check capacity, conserved quantities, contamination policy, revision conflicts and retry idempotency.
4. **Exposure and medication:** route-specific compartments, bounded metabolism and a small independently authored set of fictional treatments/adverse effects, including sustained sedation and oxygen-injury recovery. Check beneficial effects versus continuing injury, onset/clearance, repeated-dose caps, continued sedation from finite supplies, combined injury/chemical suppression, adverse effects, species/chassis compatibility, stable scheduling and restart without double dosing, duplicate healing or free awakening. Verify unconsciousness blocks desktop/VR/agent voluntary actions without removing passive restraints or halting physiology.
5. **Environmental physiology:** integrate mixture-aware breathing, suits, hypoxia, temperature and pressure hazards. Check finite gas consumption/exhaust, misleading sensor readings and rescue before irreversible harm. Depends on the future authoritative gas-network owner.
6. **Advanced medical work:** instruments, transfusion compatibility, infection, surgery and prosthetics with scoped records. Check failed/interrupted operations, resource use and observation permissions.
7. **Revival and automation:** brain/chassis transfer, cloning and approved AI-assisted medical workflows. Check single control identity, finite construction inputs, no duplicate bodies/resources and revoked agent capabilities.

At each stage add focused Windows/Linux checks when implementing the feature, default fixtures and profiling scenarios. Broader medical systems remain later work; this requirement does not change the current VR or engineering foundation's runtime behavior.
