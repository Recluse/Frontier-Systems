# Survival, pressure, docking, and salvage design contract

This document turns the desired SS13 and Barotrauma-like mechanical direction into first-party rules. These are design references, not a request to copy their art, names, maps, code, or other protected content.

## Damage should create work, not erase play

[Health, medicine and chemistry](health-medicine-and-chemistry.md) describe the planned player-health counterpart: localized anatomy, systemic physiology, finite chemicals, staged treatment and recoverable bodies. Ship integrity and player health remain separate composed owners.

Ships, stations, vehicles, and machine parts retain stable assembly and component IDs when damaged. Damage changes condition, capability, reliability, and the surrounding environment. It does not normally delete an assembly, permanently kill an occupant, or make a repairable component unrecoverable. At zero integrity, a component becomes disabled and salvageable: it remains in the world until a player or approved process dismantles it, moves it, repairs it, or recycles it. Catastrophic loss is a rare, explicit scenario rule with warning, a recoverable wreck where possible, and campaign/admin configuration.

The `IntegrityComponent` is the first code contract for this: it tracks operational, degraded, disabled, and salvageable states without owning destruction, occupant death, or recycling. Other components decide their consequences: a damaged pressure boundary leaks, a damaged pump loses flow, a damaged sensor becomes unreliable, and a damaged hull section changes structural limits. Repair, replacement, dismantling, and recycling all use the same blueprint, material-batch, work-order, access, and audit systems.

## One pressure and flow model for gases and liquids

[Breathing mixtures and pressure control](breathing-mixtures-and-pressure-control.md) now define shared constituent quantities for environments, tanks and suit loops, with regulated delivery, partial-pressure assessment and composition-aware airlock readiness. A new pure mixture contract supplements the bulk prototype; it is not yet integrated into runtime airlocks or survival.

Use common typed ports, volumes, conduits, valves, pumps, sensors, leaks, and transfer jobs for both gas and liquid networks. A medium definition declares phase and physical parameters; a volume stores its contents and temperature; a connection defines conductance, direction, and operating limits. Pressure and flow are derived from medium state and the network, rather than authored as free-standing values on each device.

For gas, model species/mixtures, mass or molar quantity, temperature, and volume; derive absolute pressure with the declared equation-of-state approximation and units. For liquids, store mass and temperature, derive density/volume from a medium definition, and include hydrostatic head and local gravity in pressure. Transfers conserve each constituent and energy within the chosen model's stated tolerance. Pumps add work, valves restrict or isolate flow, leaks move contents into the surrounding volume, and damage propagates through the same network model. Safe operating ranges, sensor error, lag, cavitation/boiling limits, and simplifications are documented per device or medium.

Implementation order: gas pressure, leaks, valves, pumps, and simple equalization for the first habitat; liquid storage and powered transfer for water/coolant; then mixed networks, thermal exchange, phase changes, and higher-fidelity atmosphere. Both phases share the same blueprint connector and network-topology contracts from the beginning, so liquid systems do not require a later rewrite.

### First pressure prototype contract

The initial code slice is deliberately smaller than the production model above. It has three fixed-volume gas compartments: a 1,000 m³ habitat initialized to 101.325 kPa absolute, a 10 m³ airlock chamber initialized at vacuum, and a 1,000,000,000 m³ exterior reservoir initialized at vacuum. The large exterior compartment is finite and exists to make transfer conservation explicit while approximating an effectively unpressurized environment.

Each compartment stores moles, volume in m³, and a fixed temperature in kelvin. Pressure is derived in absolute kPa with the ideal-gas equation, `P = nRT / V`. The prototype is isothermal: it transfers gas only between equal-temperature volumes and does not yet model species, heat, phase change, leaks, pumps, or liquid flow. A valve transfers `conductance × pressure difference × fixed-step duration` moles, capped before the pair can pass its shared equilibrium pressure; gas moles are conserved between the connected volumes. Conductance is measured in mol/(s·kPa).

Ideal pressure sensors sample their connected volume once per simulation tick. The airlock has separate inner and outer doors, habitat-equalization and exterior-vent valves, and a 2 kPa maximum door differential. A door cannot open while the other door or either valve is open. Valves require both doors closed. These interlocks are checked when the server applies each typed command. A separate access-control simulation system now stores the prototype airlock's controller, two actuators, staged bypass jobs, and bounded tamper history; it accepts only server-created actor contexts with permissions and verified tool IDs. Local UI contexts receive synthetic development tools. Networking, production actor authentication, authoritative inventory, sensor faults, and physical door animation are not implemented yet.

The prototype's pressure state has versioned JSON records for volumes, airlocks, and sensors, and the access-control system has separate versioned device records, all carried inside the world/region/tick envelope. Records contain stable IDs and canonical quantities; pressure display snapshots may include derived values that are not persisted. A restore validates all registered systems, references, sensor ticks, and airlock interlocks before replacing current state. Capture is rejected inside a simulation tick or with queued commands; restore is allowed only before the runner starts. See `docs/schema/world-snapshot-v1.schema.json` and `docs/schema/access-control-system-v1.schema.json`. The codec is ready for a persistence adapter, but no disk or PHP store exists yet.

## Access control, hacking, and bypass

Authorization, electronic security controllers, physical latches/actuators, and pressure simulation are separate layers. Players can use staged electrical tools to diagnose and temporarily override a compatible access controller, or mechanical tools to release a latch or manually move a compatible actuator. Some systems allow both routes. Tool capability, panel access, power, skill, component condition, and device blueprint determine what work is possible and what it can damage. Failed work creates repairable faults and possible tamper evidence instead of deleting the target.

A controller or credential bypass changes only its declared security channel. It never erases a pressure difference or teleports an airlock door. The current local access-control slice supports electrical, mechanical, and combined staged jobs, then grants a temporary override for only the targeted actuator to the initiating principal. Mechanical work releases the latch; electrical work records a local controller alarm. All door requests still pass the pressure differential and interlock checks. The prototype does not yet model electrical injury, hardware damage, continuous actuator dynamics, or forced decompression; those physical consequences require a richer actuator/pressure model. See [Access Control, Hacking, and Mechanical Bypass](access-control-and-bypass.md).

## Docking as a stateful engineering operation

Every ship, station, berth, and compatible small craft exposes versioned docking ports with stable IDs, geometry/approach constraints, attachment type, seal type, and transfer capacities. Docking follows explicit states: `AVAILABLE → APPROACHING → CAPTURED → SEALED → CONNECTED`; undocking first isolates transfers and releases seals, then confirms a safe relative motion envelope before returning to `AVAILABLE`. Invalid alignment, excessive relative speed, occupied ports, structural damage, pressure mismatch, or blocked transfer lines produce visible failures and safe aborts.

Docking creates typed links for collision/support, air transfer, fluid/cargo, electrical power, and data only when each port pair supports and authorizes that link. Connection is not an instant teleport or automatic pressure equalization. Players see seal checks, pressure differential, transfer rate, interlocks, and release readiness. The same state machine supports ship-to-ship, ship-to-station, rover/airlock, and orbital-yard connections.

## Exploration, remote presence, and survival

[Gravity and EVA locomotion](gravity-and-eva-locomotion.md) require working generators for artificial gravity in unsupported/freefall frames, with magnetic boots and propellant-backed jetpacks as separate traversal capabilities. Planetary surfaces, orbital freefall, attachment and suit survival use distinct observations and requirements.

Players can move between protected interiors and hazardous exterior spaces using a pressure suit, tethered or independent life support, or a purpose-built small vehicle. Suit and vehicle life support consume measurable oxygen/gas, water/coolant, power, and thermal capacity; damaged seals, depleted supplies, thermal extremes, radiation/contamination where modeled, and communication loss create staged warnings and rescue opportunities before incapacitation. The exterior remains playable because players can retrieve gear, shelter, repair suits, tow a vehicle, or operate remotely.

Remote-controlled cyborgs and instruments use the same command, capability, authorization, and audit rules as direct player action. Control range and sensor quality depend on powered networks, antennas, line of sight where relevant, relays, bandwidth, and latency. Cyborgs can tolerate environments their current body/modules are rated for, but still depend on power, thermal management, intact sensors/actuators, and communications. Losing a remote link invokes a configured safe/idle behavior and always preserves human takeover when the link returns.

Player life state is separate from ship/component integrity. Ship damage can cause dangerous conditions, but a damaged hull does not automatically kill a player. Pressure loss, fire, suit failure, biological physiology, cyborg power loss, and injury are explicit interacting systems with time to diagnose and respond. Cloning, brain recovery, cyborg embodiment, and rescue preserve player identity through the existing embodiment lease contract.

## Authoritative data contract

Blueprints and saves preserve assemblies, parts, connector graphs, docking links/state, pressure volumes, medium quantities, damage/condition, access policy revisions, security controllers, actuators, bypass jobs, tamper events, repair jobs, and player/body/control state by stable IDs. Godot scene nodes are views/physics adapters; PHP persistence and tools consume versioned records. All network actions and AI/LLM actions become typed commands revalidated by the authoritative simulation before they affect a docking link, fluid transfer, security state, repair, or body state.
