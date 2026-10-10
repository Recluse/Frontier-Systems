# Access Control, Hacking, and Mechanical Bypass

## Design goal

Lockable systems are obstacles players can diagnose and work around with suitable tools, skills, time, and risk. Hacking is an engineering activity with physical requirements and consequences, not a permission flag that silently changes the object's state. The same capability model should serve airlocks, pressure hatches, vehicle panels, storage, power cabinets, consoles, and other securable equipment.

This is original game design. Tool names, procedures, interface language, and puzzle content must be first-party and must not reproduce another game's code, UI, text, or assets.

## Separate the layers

Keep four responsibilities distinct and composable:

1. **Access policy** decides which authenticated principals may request ordinary actions. Credentials, roles, device ownership, and local overrides belong here.
2. **Security controller** interprets credentials and requests, reports tamper state, and may be powered, damaged, isolated, alarming, or bypassed.
3. **Physical restraint and actuator** represent latches, motors, gears, manual release hardware, and their condition. A working credential bypass does not make a failed actuator move.
4. **Physical simulation** resolves position, sealing, pressure force, flow, damage, and resulting hazards. No software override teleports a door or cancels pressure.

Recommended capability interfaces include `AccessControlled`, `SecurityController`, `TamperEvident`, `PoweredActuator`, `ManualActuator`, `PressureBoundary`, and `SafetyInterlock`. Blueprints declare which capabilities a part has, required ports/power, rated loads, available service access, and compatible tools. A capability describes behavior; it does not grant the actor permission to use it.

## Player approaches

### Electrical intrusion

Players inspect a service panel and use registered diagnostic/electrical tools to learn the controller's condition and available service path. A bypass job may isolate a circuit, alter a replaceable control component, provide a valid maintenance signal, or temporarily reroute a control input. The exact method is device-specific data interpreted by trusted game systems; players and LLMs never execute arbitrary GDScript, shell commands, or uploaded code.

Electrical intrusion depends on tool capability, access to the panel, available power or a compatible independent supply, the controller design/security level, operator skill, and current faults. It can grant a temporary control window, expose an authorized service mode, or disable the access reader while leaving the physical actuator and pressure interlocks in their current state. Failure can consume a fuse or component, trip a breaker, disable the controller, leave an alarm/tamper trace, or create a repair job. A powered circuit can impose a modeled shock/arc hazard when the actor or tool is not rated for it; the simulation must surface the hazard and allow recovery/repair.

### Mechanical bypass

Players use service keys, hand tools, a manual release, a crank, or suitable leverage tools to work around failed or unauthorized control hardware. The job requires access to the correct side/service cover, compatible tools, clearance, time, and sometimes a second operator or stabilization equipment. Mechanical work can be performed without control power where the hardware permits it, but power loss may leave the actuator in a difficult or fail-safe position.

Mechanical bypass can release a latch or move an actuator while leaving the controller locked or alarmed. It is slower and noisier, can damage the latch, gear train, seal, linkage, or frame, and may leave the door unable to close or hold pressure until repaired. Tool strength, access angle, actuator load, component condition, and environmental constraints determine progress and outcome. It never grants broad rights to other equipment.

### Combined intrusion

The routes can combine when a blueprint exposes both interfaces: electrical diagnostics can identify a stuck control or isolate a powered actuator before mechanical service; mechanical access can expose a controller that is otherwise protected. Device configuration declares valid route sequences. Neither route is universally superior, and the server evaluates each stage against the current device, actor, tools, power, access, and damage state.

## Airlock-specific behavior

Manual movement and defeating a lock are distinct actions. The runtime now accepts explicit manual door commands with `airlock.manual_operate` and a server-verified `tool.pry` capability. An intact accessible manual path with a released physical latch can open or close without controller power or even without the controller record. An engaged latch still rejects the crowbar request; a separate unlock/bypass procedure must release it. Jammed/disabled physical assemblies remain blocked. The prototype uses a 1,000 N manual force budget and the actuator's pressure area, then applies the existing airlock pressure/door/valve interlocks. Tool-specific ratings, continuous movement, and separate motor/power components remain later work.

Powered door commands now require a functional powered controller and powered actuator mode. Controller power currently stands in for the demo's control/drive power feed; production wiring must resolve each component's own power supply. An actuator in `manual` mode preserves mechanical use when powered movement is unavailable. Receiver/module availability is handled separately under the modular-control contract and does not determine whether the mechanical door exists.

Controllers may accept replaceable radio, wired-input, alarm, and message modules through the [modular control contract](modular-controls-and-signals.md). Signal-triggered lock/unlock actions and actuator movement remain separate operations. Installing or exposing an unsecured receiver can deliberately create a spoofable in-world input; receiving a pulse does not invent a trusted player principal or grant broad device rights.

An airlock has separate authorization, safety-control, and physical states. A successful access bypass may permit a door request despite denied credentials. A controller hack may suppress or alter an electronic interlock only if the targeted interlock is actually implemented in that controller. A mechanical override can work around a latch or manually actuate a door if the hardware and load allow it.

The pressure solver remains authoritative. The current local implementation only bypasses access to one actuator; it does not force a door against pressure. Door requests still pass through both-door/valve interlocks and the 2 kPa safe-differential check. Once the pressure/actuator model supports forced movement, a physical override may jam, damage restraints, break a seal, or transfer pressure; the bypass must never erase the differential or teleport the door.

For the first implementation, preserve the current normal-operation rule: valves require both doors closed, and an ordinary door command cannot open the other door or either valve state. Add bypass work as a separate staged job that changes only its declared security/actuator capability. Its completion produces a new typed request; the simulation rechecks pressure, current hardware state, and force/actuator limits before each movement step.

## Records and job lifecycle

Represent security and work as independent versioned records:

- `AccessPolicyRevision`: access rules and authorized principal/role references.
- `SecurityControllerState`: power, controller integrity, lockout/alarm state, bypassed channels, and current faults.
- `ActuatorState`: powered/manual capability, position, force/load limits, latch condition, seal condition, and damage.
- `BypassJob`: target ID, route (`electrical`, `mechanical`, or `combined`), staged progress, assigned actor(s), consumed tool/part IDs, resource/time costs, and expected result.
- `TamperEvent`: actor principal, target, route, attempt/result code, affected channel, and time. Keep audit retention bounded and visible to authorized operators.

The initial per-device interchange record is [`access-control-v1.schema.json`](../schema/access-control-v1.schema.json); [`access-control-system-v1.schema.json`](../schema/access-control-system-v1.schema.json) wraps those records as a simulation-system snapshot. `AccessControlSystem` now persists the prototype airlock's controller, two actuators, active/completed jobs, and bounded tamper history separately from pressure state. A restore validates IDs, references, value ranges, snapshot ticks, and matching airlock door positions before replacing state. The loader also upgrades earlier pressure-only prototype snapshots by creating locked controller records with no active overrides.

The first local runtime slice uses a server-created command context with permission grants and verified tool instance IDs. Local development supplies synthetic electrical-probe and manual-release tools; a production loadout/inventory service, spatial checks, and actor interruption are not implemented. Electrical or mechanical jobs run for 180 ticks (3 seconds at the prototype's 60 Hz); combined work takes 360 ticks. Completion grants the initiating principal a temporary 1,800-tick (30-second) override for only the targeted door actuator; electrical work records a controller alarm, while mechanical work releases that actuator's latch. The local client panel exposes all three routes for both doors, plus door requests that deliberately omit normal-operation permission to demonstrate the scoped grant.

Job stages are explicit and interruptible: inspect → prepare/access → isolate or stabilize if required → perform → validate result → restore/secure or hand off. A disconnect, power loss, tool removal, actor interruption, alarm, or changing pressure can pause or fail the job into a declared recoverable state. Failed attempts can leave partial damage or evidence; they do not randomly delete the target or kill the player.

Skills can improve diagnosis, speed, or reduce incidental damage, but must not make a required tool or safety precondition disappear. The action system is reproducible from authoritative state and server seed; it does not rely on client rolls. Unauthorized attempts still pass actor, location, range, tool ownership, and rate checks.

## Security, AI, and multiplayer rules

The authenticated server derives the actor, checks current permissions and tool capabilities, resolves stable target IDs, and queues typed commands. The client reports intent only. Bypass permissions are separate from normal operation permissions and may be roleplay-relevant (maintenance, security, emergency response, sabotage) without being hard class restrictions.

An LLM may explain diagnostics, compare lawful repair/bypass options, or draft a work order using only authorized context. It cannot emit arbitrary code, assert possession of tools, write controller state, or bypass access checks. If a future LLM tool requests a high-impact bypass stage, the server binds exact target/route/stage to player approval, verifies live preconditions, then executes the same command as a human-issued request. Approval does not override physical constraints.

Tampering may raise local alarms, add evidence to logs, change faction standing, or trigger configured security events. These outcomes are explicit and configurable. Avoid a binary “hacking always alerts” rule; the system can model controller power, alarm paths, maintenance states, and damaged sensors. Crew roleplay can matter through investigation, repair, access reviews, and authorizing emergency work, without requiring roleplay for basic operation.

## Implementation order and acceptance gates

1. Replace the prototype context's synthetic tool IDs with authoritative inventory/equipment lookups, then add interaction range, panel access, and actor interruption checks.
2. Add blueprint-declared controller/actuator capabilities, per-device ACL evaluation, migrations, and fault/repair workflows.
3. Extend the staged airlock jobs with consumable parts, electrical hazards, repairable faults, and skill/time modifiers while retaining server-side precondition checks.
4. Add actuator force, seal, and pressure-load simulation before allowing a mechanical override to force an unsafe pressure boundary.
5. Reuse the capability contracts for one hatch or service cabinet, then broaden to vehicles, storage, and other devices.

Acceptance examples for the first airlock slice:

- A normal authorized open succeeds only through the current safety checks.
- An unauthorized player with no compatible tool cannot bypass by sending a forged command or changing client state.
- A player with the correct electrical tool can create a staged, auditable, principal-scoped controller override, but it cannot move a disabled actuator or erase a pressure differential.
- A player with the required mechanical equipment can attempt the manual release without controller power where the declared hardware allows it; ordinary pressure interlocks still apply.
- Combining the routes works only when blueprint capabilities permit it; stale, interrupted, duplicated, or out-of-range requests cannot skip a stage.
- A failed attempt leaves a visible, repairable state and does not delete the airlock or immediately kill occupants.
- Saved/restored security, actuator, job, and audit states retain stable IDs and enforce the same rules after restart.
- LLM advice can describe a selected accessible procedure but cannot claim a bypass succeeded or commit any stage without ordinary server checks.
