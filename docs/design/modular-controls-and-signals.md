# Modular controls and machine signals

Implementation update: `MachineControlSystem` now ticks one prototype habitat circuit and saves installed parts, board references, wiring and pending pulses. A local debug command drives its receiver-output-to-inner-latch path. See [control circuit runtime](../architecture/control-circuit-runtime.md) for APIs, restore validation and limitations. Multi-host construction, radio propagation and the broader contracts below remain target design.

## Gameplay contract

The prototype now includes an optional [local alarm utility module](../architecture/local-alarm-module.md), installed from a startup spare and wired alongside the latch. One receiver pulse can trigger both independently. Radio propagation and external notification delivery remain future work.

Control panels and machines expose replaceable module slots. A player can assemble a control circuit from radio receivers/transmitters, buttons, sensors, relays, logic modules, timers, alarm modules, message modules, and machine-specific action adapters. Modules add capabilities through declared interfaces and connections. A door controller, fabrication machine, vehicle console, suit, and explosive device can accept different module families while sharing the same signal infrastructure.

This is first-party design inspired by the user's SS13 gameplay examples. No upstream code, text, sprites, or circuit definitions are copied. Module behavior and interfaces must remain usable under MIT.

Example circuits:

| Circuit | Behavior |
|---|---|
| Radio receiver → door control adapter | A receiver tuned to a configured frequency emits a pulse that requests an explicit lock or unlock operation on the connected door controller. Lock state, door position, and the physical latch remain separate. |
| Pressure sensor → threshold module → alarm | A configured low-pressure condition raises a local alarm and can pulse an attached message module. |
| Radio receiver → arming interlock → trigger adapter | A received pulse can request an in-game explosive device's trigger action when that device is armed and its configured trigger conditions hold. The explosive/damage solver owns the result. |
| Button → timer → relay | A button starts a delay; its later output drives a compatible connected input. |
| Fault sensor → message module | A device fault creates a bounded diagnostic message; delivery through DiscordPHP is asynchronous. |
| Door-mounted receiver → utility igniter | A pulse requests a spark at the fitted igniter's actual location. Flammable mixtures within its declared reachable range can ignite through the shared atmosphere/thermal systems. |

Prefer explicit `lock` and `unlock` inputs, and `alarm.raise`/`alarm.clear`, over a toggle for reliable automation. Toggle modules may exist as an intentional circuit behavior; their edge semantics and duplicate-pulse handling must be documented.

## Definitions, installations, and slots

Keep an immutable `MachineModuleDefinition`, a persistent installed `MachineModuleInstance`, and a machine's `MachineModuleSlotDefinition` separate. Definitions declare a stable ID/revision, module family, interface version, occupied size, idle power, required host capabilities, named signal ports, and a trusted behavior-handler ID. Instances hold stable item/module/host/slot IDs, condition, power state, configuration revision, and handler-owned runtime records. Removing a module preserves it for repair, reuse, and salvage.

A slot accepts a module when its physical interface matches, its bay supports the family, its size fits, and the slot is available. A general utility bay declares `allowed_module_families: ["*"]` and accepts any family that fits its interface and space; specialized sockets may retain real card/connector constraints. Host prerequisites are evaluated separately through `evaluate_operability()`: a physically fitting module may be installed with missing power, data, or other services and remain dormant. Reject impossible mounting, not unusual player intent. Additional voltage/rating, shape, cooling, and sealed-connection requirements belong in later versioned interfaces. Matching a family or interface does not confer authority to operate another machine.

The stock PDA radio slot accepts portable transceivers, transmitters, and receivers; the stock door receiver socket accepts its industrial receiver card. These are specific hardware layouts, not permanent device-role bans. Replacing the door board with a compatible expanded layout can add general utility bays for an igniter or other unconventional modules. A transceiver supplies transmit and receive functions, while a receiver supplies only reception. A door gains radio reception only from a fitted, powered, functional receiver; a matching frequency cannot supply a missing component. Examples live in `data/control/modules/`, `data/control/slots/`, and `data/control/boards/`.

Track availability per function using [machine-function-requirement-v1](../schema/machine-function-requirement-v1.schema.json) and `MachineFunctionRequirement`. Evaluate requirements against capabilities of the actual installed, functioning components, not every component the blueprint might permit. Slot compatibility says what can be installed; function requirements say what the current assembly can do. Recompute after removal, installation, faults, or power changes. These pure checks are implemented; integration with live module installation and power graphs remains future work.

| Missing or unavailable component | Capability lost | Function that may remain |
|---|---|---|
| Door radio receiver | Radio reception/control | Local controls or manual movement, if their own requirements hold |
| PDA transmitter/transceiver | Radio emission; reception too if the removed module supplied both | Local PDA notes and other separately supported functions |
| Door controller/control power | Powered electronic commands | Manual opening/closing through an intact mechanical path |
| Door motor | Motor-driven movement | A supported manual drive; represent this separately from a jammed physical assembly |
| Sensor module | Its reading and dependent automatic decisions | Manual controls and independent sensors |
| Physical lock still engaged | Manual movement through that restraint | Diagnosis, authorized unlocking, or a separate supported lock-bypass job |

Degradation must disable only dependent functions. A whole-device operational flag must not erase independent physical capabilities. Player-facing diagnostics should explain the specific missing component, power path, or other unmet condition. Actor tools/permissions, latch condition, and pressure loads remain live action checks rather than static component-presence flags.

Use composition rather than a subclass for every complete panel. A generic chassis supplies mounting/power/service access, modules supply behavior, and machine-specific adapters expose registered actions. Blueprints and construction/refit jobs contain slot/module references and wiring edges. Installing, rewiring, removing, or reconfiguring modules uses server-validated physical work with compatible tools, location/access checks, reservations, and persistent revisions.

The initial definition and slot contracts are [machine-module-definition-v1](../schema/machine-module-definition-v1.schema.json) and [machine-module-slot-v1](../schema/machine-module-slot-v1.schema.json). Their Godot parsers and compatibility checks live in `src/core/control/`. These are foundational data contracts; the running airlock demo does not yet install modules or route signals.

## Construction, upgrades, and unconventional modules

Construction/refit jobs can replace a control board with a compatible version that supplies more slots, different connector interfaces, or new host services. The [machine-control-board-v1](../schema/machine-control-board-v1.schema.json) definition and `MachineControlBoardDefinition.plan_replacement()` now model board mounts, slot layouts, retained modules, explicit relocations, collision checks, and dormant-module diagnostics. The example door board grows from one receiver socket to that same socket plus two general utility bays. This is a pure definition/upgrade planner; no running construction job applies it yet.

The eventual work sequence is inspect/plan → reserve the replacement board and required materials → isolate affected control/power paths → remove and preserve the old board → install/transfer modules → reconnect declared wiring → validate/commission. Preserve assembly/door/module instance IDs and inventory provenance. The old board remains salvageable. Removing slots must create explicit removal/relocation work and storage reservations; it must not delete their occupants. Definition-level planner assignments are translated into instance-ID transfers by the authoritative construction service. Recheck board/assembly/configuration revisions at commit, and pause an interrupted job in a documented repairable state. Commissioning can complete with explicitly diagnosed dormant or disconnected modules when the physical assembly is valid.

Upgrading a board is not an implicit permission grant. Machine-specific operating rules and the installed module's own handler still apply, but a door chassis must not forbid a physically fitting igniter simply because ignition is not a normal door function. Avoid device-name special cases. The module's local effect follows its installed placement and connected input.

For the door igniter, a trusted `thermal.igniter.v1` handler would request an ignition-energy event at the module's actual position, mounting side, exposed environment, and rated range. The atmosphere/thermal systems resolve reachable compartments, shielding/occlusion, fuel/oxidizer mixture, ignition conditions, temperature, consumption, and any fire/damage. In vacuum or without a combustible mixture, the pulse may consume energy/create a spark without starting a fire. Missing electrical service leaves it dormant; an absent trigger wire leaves it idle. Radius, energy, cooldown, active power cost, and condition belong to the handler's versioned configuration. The current igniter fixture declares a pulse input and handler ID; ignition/combustion, module placement, configuration, and live signal handlers remain unimplemented in the isothermal prototype.

Board swaps and module removal invalidate stale signal deliveries by module instance/configuration generation. A queued pulse for an old occupant must never fire a newly fitted module in the same slot accidentally. Preserve retained connections only when their explicit instance/port endpoints still exist; expose broken connections as diagnostics rather than retargeting them by slot name.

## Ports, wiring, and radio

Use separate transports for discrete pulses, boolean/numeric sensor values, and bounded messages. Ports are identified by module-instance ID plus port-local ID. Physical cable attachment and usable signal routing are distinct checks. The prototype's abstract wired connectors can be attached even output-to-output or between incompatible payload types, with an inert-route diagnostic; a radio endpoint is not a cable socket. `assess_wired_attachment()` accepts physical attachment, while `can_connect()` checks directed signal transfer. Later connector shape/rating rules determine actual attachability; electrical faults/shorts belong to their solver. Edges retain stable cable/connection IDs, length/range, integrity, and topology revision. Data messages do not implicitly become pulses or executable commands; converters must be explicit modules.

Radio settings use integer frequency in Hz, an optional address/channel filter, payload type, and optional game-code/authentication settings. Initially use abstract declared bands and receiver range; interference, shielding, antennas, line of sight, propagation delay, and jamming are later fidelity work. Frequency matches alone provide no confidentiality or sender authentication. Unsecured receivers deliberately accept matching broadcasts, allowing a player to discover/tune/spoof a signal with suitable in-game equipment. Coded receivers compare a configured game code; authenticated receivers require a separate in-world trust protocol. Neither uses or exposes a player's Steam/Discord credentials.

Radio used for machine control is part of the simulation. Discord/Social SDK player voice and chat remain their own asynchronous social adapter. A message module may enqueue a reviewed notification to that adapter, but a Discord message is not an electrical pulse unless a separately authorized game integration creates the typed signal request.

Disconnected wiring, absent/broken modules, missing power, incompatible ports, and unreachable receivers produce explicit diagnostic results. Define fail-open, fail-closed, latching, and reset behavior per module/device; loss of a signal must not universally unlock doors or detonate devices. Already armed countdowns follow the device's declared behavior when a module is removed or power is lost.

## Signal authority and execution

The authoritative host owns topology, receiver configuration, pulses, and module state. Client transmissions are intent: the server verifies the actor's actual transmitter/tool, location, power, parameters, and allowed interaction before creating a signal. A received broadcast can be unauthenticated within the world; it never supplies a trusted player principal or arbitrary action name.

An installed action adapter maps a declared input to a fixed registered action and stable target. Installation/configuration establishes its permitted device scope and explicitly selected operating mode. A player cannot remotely widen that scope by adding an actor ID, permission, target, or command type to a radio payload. Access checks for circuit configuration and an intentionally exposed trigger input are distinct: an unsecured, enabled trigger must be usable as designed without requiring the transmitting player to own the target. Record both the transmitter principal when known and the installed device/module provenance; unknown radio origins remain unknown.

At the tick boundary, the module handler checks live installation/condition, power, wiring, configuration revision, operating limits, and device interlocks, then submits a typed request to the target system. The target reports success/failure. Electronic door locks can be controlled by a compatible module, but pressure/force/seal consequences remain in the physical simulation. Triggering explosives uses the same in-game device arming, damage, scenario, and event rules as other triggers.

LLMs and player programs use these same installed endpoints and typed intents. They cannot register new handlers or insert arbitrary GDScript, PHP, shell code, or hidden permissions into module configuration. A handler ID selects trusted server code; unknown handlers fail explicitly.

## Scheduling, persistence, and profiling

The future `MachineControlSystem` will own module installations, wiring/radio endpoints, and pending signal deliveries. Delivering a signal schedules downstream work for a subsequent fixed tick; callbacks cannot recursively walk an unbounded circuit in the current tick. Give each pulse a stable pulse ID, root/correlation ID, emitting port, emitted/due ticks, bounded payload, and remaining hop budget. Deduplicate `(pulse ID, destination port)` before delivery, cap pending work and fan-out, and count rejected/expired deliveries. Clock/oscillator modules create new bounded pulses; graph cycles remain usable within declared budgets.

Persist module instances/configuration, connections, timers, latches, sequence counters, and pending durable deliveries in a versioned system record. Restore validates all references and due ticks; due deliveries resume in tick order instead of firing an uncontrolled catch-up burst. Exact ordering uses due tick, stable module/port IDs, and a persisted sequence. Save canonical module state, not Godot signal connections or scene nodes. Power-network and target-device checks must be included in cross-system restore validation.

Cache adjacency/radio indexes by topology/configuration revision; caches are disposable and are rebuilt after restore. Profile active modules, wire edges, transmissions, queue depth/age, deliveries per tick, fan-out, expired/deduplicated/rejected signals, handler costs, timers, and alarm/message backlog. External message delivery uses bounded promises, timeouts, rate limits, and backpressure; server ticks never wait for Discord or an LLM.

## Implementation sequence and acceptance

1. **Foundation implemented in source:** module/slot/function/board parsers, handler allowlist registry, separate mounting/operability checks, board replacement planning, and physical-wiring versus signal-route assessment. A prototype circuit is now registered with world ticks and snapshots.
2. Add stable module instances and occupied slots, blueprint references, configuration handlers, installation/removal/board-upgrade work, and revisioned saves; integrate authoritative inventory and power.
3. Implement a bounded wired pulse queue and a button/relay/door-lock adapter slice. Prove one input can request a lock/unlock action while physical interlocks and component condition still apply.
4. Add radio receivers/transmitters with frequency/address/code configuration, declared range, and spoofable unsecured inputs. Reuse the wired pulse path after receiver filtering.
5. Add timers, sensors/logic, alarms, and message sinks; then reuse machine-specific adapters for a second machine family and an in-game armed trigger device.

Acceptance scenarios include impossible physical family/interface/size mismatch; physically fitting but dormant modules; unusual modules in general bays; duplicate port IDs; attachable but inert wiring; occupied slots; board mount mismatch, module retention/relocation, slot collisions, smaller-board removal jobs, and interrupted upgrades; powered/unpowered and damaged modules; frequency/address/code mismatch; a valid unsecured spoof; authenticated receiver rejection; duplicate broadcasts; multi-receiver fan-out; cyclic circuits within budgets; stale configuration, removed/replaced modules, and forged target/principal fields; scoped door actions; a door-mounted igniter with/without reachable combustible gas; unarmed trigger rejection; external message outage; and restart of a pending timer/pulse without duplicate action.
