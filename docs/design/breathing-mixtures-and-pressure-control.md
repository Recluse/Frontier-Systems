# Breathing mixtures and pressure control

## Gameplay requirement

Organic players need compatible breathing gas at an appropriate local pressure. Habitats, airlocks, suit breathing loops and tanks must share species/pressure contracts. Air mixtures and emergency oxygen supplies are physical resources: tanks contain finite gas, regulators control delivery, and breathing consumes oxygen while producing carbon dioxide and other accounted outputs through species-specific physiology.

Pure O₂ is a hazardous option whose behavior depends on local oxygen partial pressure, exposure and equipment suitability. It can be useful in a configured low-pressure breathing loop while still requiring fire/exposure monitoring. Compressed tank pressure is never the pressure applied directly to a player's lungs. A tank alone supplies neither a pressure boundary nor decompression protection.

## Volumes, supplies and controllers

Use a common volume record for rooms, airlock chambers, tanks and suit loops: constituent quantities, volume, temperature and revision. Derive absolute total pressure and each gas partial pressure. Identity/profile rules determine organism compatibility; cyborgs can instead have chassis-dependent cooling/pneumatic supplies without assuming organic respiration.

Separate these responsibilities:

| Component | Role |
| --- | --- |
| Storage tank | Rated sealed volume containing finite gas mixture |
| Regulator/valve | Bounded transfer controlled by upstream/downstream pressure and device limits |
| Mixer | Combine conserved constituents toward a composition target |
| Breathing loop | Local pressure/composition, oxygen delivery and exhaled-gas handling |
| Scrubber/filter | Remove/retain selected constituents with power and finite consumables |
| Pump/compressor | Add work to move gas against a pressure gradient |
| Airlock controller | Interlock doors/valves and coordinate pressure and composition readiness |

Gas cannot appear from a pressure setpoint. Regulators, pumps and airlock cycling must transfer existing matter. Refill uses compatible sources and rated connectors; tank and line pressure ratings remain separate from breathability. Damaged cylinders, hoses, regulators, seals and sensors should create repairable leaks/faults and staged warnings. Keep constituent releases and exhaust inside the pressure/material ownership model.

Airlocks must check differential pressure independently of composition. Equal pressure can still conceal an incompatible mix. A valid gas mixture can still be unsafe with pressure loss, a missing suit boundary, thermal/radiation hazards or unsuitable external pressure. Emergency bypass and maintenance must retain the existing mechanical/access/pressure rules.

## Implemented foundation and units

`GasMixtureVolume` adds detached species-aware volume records alongside the current bulk-mole solver. Canonical quantities are integer **micromoles** (1,000,000 µmol = 1 mol), bounded in aggregate by the exact JSON integer limit. The prototype accepts oxygen, nitrogen, carbon dioxide and argon; unknown species reject until an explicit species-catalog extension exists.

The class derives pressure using the existing ideal-gas constant and fixed volume/temperature. `partial_pressure_kpa()` derives each constituent's pressure. `plan_transfer()` apportions an exact requested quantity across constituents using integer long division and deterministic largest remainders, avoiding int64 product overflow. Source/destination records and revisions are returned without mutation; every constituent and total quantity conserve exactly.

Transfer plans require distinct volumes and identical fixed temperatures, positive available quantity, remaining revision/quantity capacity and a finite positive destination pressure limit. The destination pressure limit must eventually come from trusted regulator/tank ratings, not a client claim. Plans do not enforce upstream/downstream flow direction, consume compressor energy or perform an atomic commit; the future gas-network owner must do so. Thermal mixing and high-pressure nonideal behavior are not modeled.

Default fixtures include a prototype mixed habitat sample, compressed O₂ tank and evacuated airlock sample. They are not runtime replacements for the existing pressure volumes and are not populated by a refill command. The existing airlock solver still has only total moles, so production mixture migration must assign gas through an explicit approved recipe/source record rather than guessing oxygen from pressure.

`PrototypeBreathingPolicy` evaluates a deliberately fictional engineering envelope using total pressure, oxygen/CO₂ partial pressures and enrichment flags. Its thresholds are game tuning, not physiology or real-world breathing guidance. Low-pressure pure oxygen can pass its provisional envelope with fire/exposure warnings; compressed O₂ and vacuum do not. Time-dependent exposure, flammability reactions, metabolic consumption, species-specific profiles and injury are not implemented by this pure assessment.

The mixture schema is `gas-mixture-volume-v1.schema.json`; code additionally checks aggregate quantity and finite derived state. Full regulation, breathing, tank inventories and mixture-aware airlock commands remain pending.

## Implementation stages

1. **Implemented:** constituent-volume contract, exact isothermal transfer plans, prototype breathing assessment and default fixtures.
2. Add an authoritative gas-network owner and rated tank/regulator components with atomic constituent transfers, saved revisions and power/work accounting.
3. Integrate mixture-aware airlocks and room sensors; migrate bulk volumes without inventing constituent matter. Add leaks, pumping, fill/vent limits and sensor faults.
4. Add inventory-backed gas tanks, suit boundaries/loops, breathable profile policies, consumption/exhalation and scrubber consumables. Preserve oxygen and carbon accounting with the material model.
5. Add exposure/fire/pressure-transition hazards, species/chassis physiology and rescue/status UI. Every player/script/LLM action passes the same capability, source quantity and device rating checks.

## Verification

Windows Godot headless editor import and `tests/godot/gas_mixture_test.gd` passed. Scenarios cover mixed habitat gas, vacuum, compressed oxygen, low-pressure oxygen warning flags, destination pressure limits, exact constituent conservation, unchanged input records, invalid species/fractional quantities, incompatible temperatures, large integer apportionment and JSON recovery. The focused script is included in the Windows/Ubuntu CI workflow; remote CI and Linux execution have not been verified locally.
