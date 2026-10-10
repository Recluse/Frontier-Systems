# Control circuit runtime API

`MachineControlCircuit` owns one host board, installed `MachineModuleInstance` parts, physical wires and a bounded wired pulse queue. `MachineControlSystem` now registers one prototype habitat-airlock host with `WorldRuntime`, ticks after access control, and includes its circuit in world snapshots. Storage I/O and durable database persistence remain external work.

## Installation and ownership

Only authoritative host code invokes this API. Commissioning, installation, rewiring, handler registration and emission are not player commands or external service callbacks. A future command layer must validate tools, location, materials, inventory ownership and configuration permissions.

- `commission(board, capabilities)` validates and copies the board and host capabilities.
- `install(instance_id, slot_id, definition, integrity)` checks socket fit and occupancy, preserves supplied part condition and copies the definition. Missing functional capabilities and unbound handlers leave physically fitted parts dormant. The default integrity is for a newly constructed part; salvage must supply its existing integrity.
- `replace_board(replacement, slot_moves)` validates the entire transfer plan before changing anything. It retains part identity, condition, definition, wiring and pending receipts while changing slot placement. Construction work, isolation and materials are not implemented.
- `remove(instance_id)` returns salvage inspection state, disconnects wires and cancels all receipts involving the part. Reinstallation with the same identity cannot revive canceled signals. Inventory ownership must later prevent identity duplication across circuits.
- `set_integrity` disables zero-integrity parts without deleting them or their wires. `set_powered` updates the host's supplied power availability; there is no load solver yet.

The part inspection record has a schema in `docs/schema/machine-module-instance-v1.schema.json`. Circuit records remain v1; system records emit v3 with module salvage, board ownership and reserved board work, accepting v1/v2 records. See [board replacement work](board-replacement-work.md). `capture_record` saves board/catalog references, capabilities, supplied power, parts, wires, tick, emission sequence and queued receipts. Diagnostics are disposable. Handler callables and definition bodies are never loaded from saves: restore resolves pinned server catalogs and reconstructs bindings from code. Integral JSON numbers are normalized in the world codec before strict domain decoding.

Restore builds a detached circuit, rejecting unknown revisions, invalid or duplicate identities, occupied slots, oversized collections, dangling wires, duplicate receipts, inconsistent emissions, nonmonotonic ordering, future deliveries beyond the next tick, and non-pulse routes. The runner validates all systems and cross-system actuator membership before any restore mutates state. Backlogged pulses resume within the ordinary per-tick delivery bound. Power is refreshed from the actual access controller after restore and each tick; a saved boolean cannot grant power.

## Wired delivery

`attach_wire` accepts either endpoint ordering, including physically attachable inert wiring. Radio ports cannot accept wires. Duplicate endpoint pairs are rejected. Geometry, connector ratings and electrical shorts are not solved here.

`emit_pulse(module_id, output_port_id)` requires an operable wired pulse output. A trusted receiver adapter may call it after validating reception; spatial radio reception is not implemented. Each emission gets a circuit-local sequence and carries no arbitrary payload, target selection or player credentials. Endpoints use installed part IDs, never slot IDs.

Fanout follows sorted wire IDs and deduplicates destination endpoints. Overload rejects the complete emission atomically. Limits are 64 installed parts, 256 wires, 256 pending receipts, 32 recipients per emission and 64 delivery attempts per tick. Excess due work stays queued. `advance_tick` requires sequential tick numbers starting at one and rejects recursive advancement. Handler-generated emissions are due on a subsequent tick.

Delivery checks that the wire still joins the original endpoints, both parts remain operable, and host capabilities and power are available. Removal or wire detachment cancels relevant receipts; reusing the wire ID cannot resurrect them. Due receipts fail during a power outage rather than replaying automatically after recovery.

Handlers are explicitly bound trusted first-party callables returning `ServiceResult`. The owner must retain their adapter objects; the prototype system retains its latch adapter. Handlers must be bounded and synchronous; no external I/O runs here. Unbound handlers return failure. Relay modules, root correlation, hop limits and radio repeaters remain unimplemented; add loop limits before introducing relays. Persisted circuit-local sequences are not globally unique world identifiers.

`advance_tick` returns bounded per-delivery outcomes. `diagnostics` reports tick, queue length, part/wire counts and cumulative delivered, dropped and overload-rejected counts.

## Door-latch integration

`data/control/modules/door_latch.v1.json` declares utility-bay `lock` and `unlock` pulse inputs and requires `power.consumer`, `control.wired` and `door.latch` capabilities. A stock receiver's `pulse_out` can connect to either input on an expanded door board.

Trusted construction code creates `DoorLatchPulseAdapter(access_system, installed_latch_id, device_id, actuator_id)` and binds `receive_pulse` to `door.latch.v1`. The adapter accepts only its commissioned part ID and fixed inputs. This prototype supports one commissioned latch adapter per handler per circuit; an incoming pulse cannot widen its target scope.

The host ticks access control first and then advances the circuit in the same authoritative tick. `AccessControlSystem.apply_circuit_latch_request` checks tick equality, device and actuator membership, controller power/integrity and an intact powered actuator/latch. Locking an open door fails. Success changes only the latch; it does not move the door, grant credentials or bypass privileges, or alter gas. A released latch permits the existing manual interaction to enforce its own tool, force and airlock interlocks.

New worlds commission an expanded board, receiver, latch module and receiver-output-to-unlock wire. The client panel has a local debug pulse button and circuit counters. `DebugControlPulseCommand` requires a debug build, local-development origin and `control.debug_pulse`; it has no transmitter, frequency or arbitrary target fields. Commands queue bounded requests; the control tick emits them after advancing existing deliveries, so they reach the latch on the following tick. Queue acceptance does not mean successful emission or actuation. Delivery diagnostics and latch state show outcomes. This probe is not a production radio interaction.

Older world saves without `machine_control` migrate to an empty commissioned board at the saved tick, with no modules, wiring or pending pulses. Migration never adds the prototype unlock path. Such worlds cannot use the debug probe successfully until future construction installs the required equipment.

## Remaining integration gates

1. Extend the [local maintenance commands](machine-maintenance.md) with production location, inventory and construction-work authority.
2. Generalize host catalogs, multiple device bindings and region-wide part identity ownership.
3. Add actual transmitter interactions and validated fixed-tick receiver ingress.
4. Add relay correlation limits, spatial radio propagation and electrical load accounting.
5. Implement ignition after atmosphere resolves fuel, oxygen, range and occlusion.

This circuit integration has not been executed in Godot or covered by new tests. Previously recorded successful checks predate these additions.
