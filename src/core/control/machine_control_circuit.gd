extends RefCounted
class_name MachineControlCircuit

## One trusted host circuit with versioned state; not a network ingress.
## Mutations belong to the authoritative tick owner. No asynchronous callbacks.
const MAX_MODULES: int = 64
const MAX_WIRES: int = 256
const MAX_PENDING: int = 256
const MAX_FANOUT: int = 32
const MAX_DELIVERIES_PER_TICK: int = 64

var _board: MachineControlBoardDefinition
var _capabilities := PackedStringArray()
var _powered: bool = false
var _modules: Dictionary = {}
var _wires: Dictionary = {}
var _handlers: Dictionary = {}
var _pending: Array[Dictionary] = []
var _tick: int = 0
var _sequence: int = 0
var _advancing: bool = false
var _metrics: Dictionary = {"delivered": 0, "dropped": 0, "rejected": 0, "peak_pending": 0, "last_delivery_attempts": 0}


## Commissioning is server-owned; definitions and capabilities are copied.
func commission(board: MachineControlBoardDefinition, capabilities: PackedStringArray) -> ServiceResult:
	if _board != null or board == null:
		return ServiceResult.failure(&"invalid_commissioning", "A circuit needs one initial board.")
	var parsed: ServiceResult = MachineControlBoardDefinition.from_record(board.to_record())
	if not parsed.is_success:
		return parsed
	var checked: ServiceResult = ControlContractValidation.decode_ids(Array(capabilities), 0, 64)
	if not checked.is_success:
		return checked
	_board = parsed.value
	_capabilities = capabilities.duplicate()
	return ServiceResult.success()


## Handler bindings are first-party code, never supplied by players or definitions.
func bind_handler(handler_id: String, handler: Callable) -> ServiceResult:
	if not ControlContractValidation.is_id(handler_id) or not handler.is_valid() or _handlers.has(handler_id) or _handlers.size() >= 64:
		return ServiceResult.failure(&"invalid_circuit_handler", "A unique trusted handler binding is required.")
	_handlers[handler_id] = handler
	return ServiceResult.success()


func install(instance_id: String, slot_id: String, definition: MachineModuleDefinition, integrity: float = 1.0) -> ServiceResult:
	if _board == null or definition == null or not ControlContractValidation.is_id(instance_id) or not is_finite(integrity) or integrity < 0.0 or integrity > 1.0:
		return ServiceResult.failure(&"invalid_module_installation", "A commissioned board and stable part ID are required.")
	if _modules.has(instance_id) or _modules.size() >= MAX_MODULES:
		return ServiceResult.failure(&"module_installation_limit", "The part ID is already used or the board is full.")
	var slot := _board.slots.get(slot_id) as MachineModuleSlotDefinition
	if slot == null:
		return ServiceResult.failure(&"unknown_module_slot", "The board has no such socket.")
	for part: MachineModuleInstance in _modules.values():
		if part.slot_id == slot_id:
			return ServiceResult.failure(&"occupied_module_slot", "Remove the current part before installing another.")
	var fit: ServiceResult = slot.accepts(definition)
	if not fit.is_success:
		return fit
	var parsed: ServiceResult = MachineModuleDefinition.from_record(definition.to_record())
	var instance := MachineModuleInstance.new()
	instance.instance_id = instance_id
	instance.slot_id = slot_id
	instance.definition = parsed.value
	instance.integrity = integrity
	_modules[instance_id] = instance
	return ServiceResult.success(instance.to_record())


## Removal returns salvage state, disconnects wires, and cancels queued deliveries.
## Reinstalling the same salvaged part cannot revive its canceled deliveries.
func remove(instance_id: String) -> ServiceResult:
	var part := _modules.get(instance_id) as MachineModuleInstance
	if part == null:
		return ServiceResult.failure(&"unknown_installed_module", "The installed part does not exist.")
	var record: Dictionary = part.to_record()
	_modules.erase(instance_id)
	for wire_id in _wires.keys():
		var wire: Dictionary = _wires[wire_id]
		if wire["first_module"] == instance_id or wire["second_module"] == instance_id:
			_wires.erase(wire_id)
	for index in range(_pending.size() - 1, -1, -1):
		if _pending[index]["source_module"] == instance_id or _pending[index]["target_module"] == instance_id:
			_pending.remove_at(index)
			_metrics["dropped"] += 1
	return ServiceResult.success(record)


func replace_board(replacement: MachineControlBoardDefinition, slot_moves: Dictionary = {}) -> ServiceResult:
	var plan: ServiceResult = plan_board_replacement(replacement, slot_moves)
	if not plan.is_success:
		return plan
	var parsed: ServiceResult = MachineControlBoardDefinition.from_record(replacement.to_record())
	for part: MachineModuleInstance in _modules.values():
		part.slot_id = plan.value["slot_assignments"][part.slot_id]
	_board = parsed.value
	return plan


func plan_board_replacement(replacement: MachineControlBoardDefinition, slot_moves: Dictionary = {}) -> ServiceResult:
	if _board == null or replacement == null:
		return ServiceResult.failure(&"missing_control_board", "Both installed and replacement boards are required.")
	var installed: Dictionary = {}
	for part: MachineModuleInstance in _modules.values():
		installed[part.slot_id] = part.definition
	return _board.plan_replacement(replacement, installed, _capabilities, slot_moves)


## Physical attachment accepts inert wiring; routing is evaluated separately.
func attach_wire(wire_id: String, first_module: String, first_port: String, second_module: String, second_port: String) -> ServiceResult:
	if not ControlContractValidation.is_id(wire_id) or _wires.has(wire_id) or _wires.size() >= MAX_WIRES:
		return ServiceResult.failure(&"invalid_wire_id", "A unique wire ID within the circuit limit is required.")
	var first: Dictionary = _port(first_module, first_port)
	var second: Dictionary = _port(second_module, second_port)
	var assessment: ServiceResult = ControlContractValidation.assess_wired_attachment(first, second)
	if not assessment.is_success:
		return assessment
	for wire: Dictionary in _wires.values():
		var forward: bool = wire["first_module"] == first_module and wire["first_port"] == first_port and wire["second_module"] == second_module and wire["second_port"] == second_port
		var reverse: bool = wire["first_module"] == second_module and wire["first_port"] == second_port and wire["second_module"] == first_module and wire["second_port"] == first_port
		if forward or reverse:
			return ServiceResult.failure(&"duplicate_wire_endpoints", "These endpoints already have a wire.")
	_wires[wire_id] = {
		"first_module": first_module, "first_port": first_port,
		"second_module": second_module, "second_port": second_port,
	}
	return assessment


func detach_wire(wire_id: String) -> ServiceResult:
	if not _wires.has(wire_id):
		return ServiceResult.failure(&"unknown_wire", "The wire does not exist.")
	_wires.erase(wire_id)
	for index in range(_pending.size() - 1, -1, -1):
		if _pending[index]["wire_id"] == wire_id:
			_pending.remove_at(index)
			_metrics["dropped"] += 1
	return ServiceResult.success()


func set_powered(powered: bool) -> void:
	_powered = powered


## Zero integrity preserves the part and its wires, but disables pulse operations.
func set_integrity(instance_id: String, integrity: float) -> ServiceResult:
	var part := _modules.get(instance_id) as MachineModuleInstance
	if part == null or not is_finite(integrity) or integrity < 0.0 or integrity > 1.0:
		return ServiceResult.failure(&"invalid_module_integrity", "An installed part and integrity between zero and one are required.")
	part.integrity = integrity
	return ServiceResult.success()


## Trusted receiver adapter entry point after reception validation, not raw radio.
## Atomic fanout: overload rejects the whole emission before any deliveries queue.
func emit_pulse(instance_id: String, port_id: String) -> ServiceResult:
	if _sequence >= 9007199254740990 or _tick >= 9007199254740990:
		return ServiceResult.failure(&"circuit_sequence_exhausted", "Circuit counters reached their exact JSON integer limit.")
	var source: Dictionary = _port(instance_id, port_id)
	if not _operable(instance_id) or source.get("direction") != "output" or source.get("transport") != "wired" or source.get("signal_type") != "pulse":
		return ServiceResult.failure(&"pulse_source_unavailable", "The source needs an operable wired pulse output.")
	var deliveries: Array[Dictionary] = []
	var destinations: Dictionary = {}
	var wire_ids: Array = _wires.keys()
	wire_ids.sort()
	for wire_id in wire_ids:
		var wire: Dictionary = _wires[wire_id]
		var target_module: String = ""
		var target_port: String = ""
		if wire["first_module"] == instance_id and wire["first_port"] == port_id:
			target_module = wire["second_module"]
			target_port = wire["second_port"]
		elif wire["second_module"] == instance_id and wire["second_port"] == port_id:
			target_module = wire["first_module"]
			target_port = wire["first_port"]
		else:
			continue
		if not ControlContractValidation.can_connect(source, _port(target_module, target_port)).is_success:
			continue
		var key: String = JSON.stringify([target_module, target_port])
		if destinations.has(key):
			continue
		destinations[key] = true
		deliveries.append({"wire_id": wire_id, "source_module": instance_id, "source_port": port_id, "target_module": target_module, "target_port": target_port, "due_tick": _tick + 1})
	if deliveries.size() > MAX_FANOUT or _pending.size() + deliveries.size() > MAX_PENDING:
		_metrics["rejected"] += 1
		return ServiceResult.failure(&"pulse_queue_full", "The bounded circuit cannot accept this complete fanout.")
	_sequence += 1
	for delivery in deliveries:
		delivery["sequence"] = _sequence
		_pending.append(delivery)
	_metrics["peak_pending"] = maxi(int(_metrics["peak_pending"]), _pending.size())
	return ServiceResult.success({"sequence": _sequence, "queued_deliveries": deliveries.size()})


## Invoke exactly once per host tick. New emissions never execute recursively.
## Handlers receive payload-free receipts; they return a typed domain result.
func advance_tick(tick_number: int) -> ServiceResult:
	if _advancing or tick_number != _tick + 1 or tick_number > 9007199254740990:
		return ServiceResult.failure(&"invalid_circuit_tick", "Circuit ticks must be sequential and non-reentrant.")
	_advancing = true
	_tick = tick_number
	var results: Array[Dictionary] = []
	var count: int = 0
	while not _pending.is_empty() and _pending[0]["due_tick"] <= _tick and count < MAX_DELIVERIES_PER_TICK:
		var delivery: Dictionary = _pending.pop_front()
		count += 1
		var outcome: ServiceResult = _deliver(delivery)
		_metrics["delivered" if outcome.is_success else "dropped"] += 1
		results.append({"sequence": delivery["sequence"], "target_module": delivery["target_module"], "target_port": delivery["target_port"], "success": outcome.is_success, "error_code": String(outcome.error_code)})
	_advancing = false
	_metrics["last_delivery_attempts"] = count
	return ServiceResult.success(results)


func diagnostics() -> Dictionary:
	var result: Dictionary = _metrics.duplicate()
	result["tick_number"] = _tick
	result["pending_deliveries"] = _pending.size()
	result["installed_modules"] = _modules.size()
	result["wires"] = _wires.size()
	result["oldest_pending_age_ticks"] = maxi(0, _tick - int(_pending[0]["due_tick"])) if not _pending.is_empty() else 0
	return result


func module_record(instance_id: String) -> ServiceResult:
	var part := _modules.get(instance_id) as MachineModuleInstance
	if part == null:
		return ServiceResult.failure(&"unknown_installed_module", "The installed part does not exist.")
	return ServiceResult.success(part.to_record())


## Callables and definition bodies are never persisted. Restore uses trusted catalogs.
func capture_record() -> ServiceResult:
	if _advancing or _board == null:
		return ServiceResult.failure(&"circuit_snapshot_unavailable", "Capture a commissioned circuit between ticks.")
	var modules: Array[Dictionary] = []
	var ids: Array = _modules.keys()
	ids.sort()
	for id in ids:
		modules.append((_modules[id] as MachineModuleInstance).to_record())
	var wires: Array[Dictionary] = []
	ids = _wires.keys()
	ids.sort()
	for id in ids:
		var wire: Dictionary = _wires[id].duplicate(true)
		wire["wire_id"] = id
		wires.append(wire)
	return ServiceResult.success({
		"schema_version": 1, "board_definition_id": _board.definition_id,
		"board_revision": _board.revision, "host_capabilities": Array(_capabilities),
		"powered": _powered, "tick_number": _tick, "sequence": _sequence,
		"modules": modules, "wires": wires, "pending": _pending.duplicate(true),
	})


## Parses into a detached circuit; validation cannot mutate the active host.
static func from_record(record: Dictionary, board: MachineControlBoardDefinition, catalog: MachineModuleRegistry, capabilities: PackedStringArray, snapshot_tick: int) -> ServiceResult:
	if snapshot_tick < 0 or snapshot_tick > 9007199254740990:
		return ServiceResult.failure(&"invalid_circuit_tick", "Saved ticks must be exact non-negative JSON integers.")
	var fields := PackedStringArray(["schema_version", "board_definition_id", "board_revision", "host_capabilities", "powered", "tick_number", "sequence", "modules", "wires", "pending"])
	if not ControlContractValidation.has_exact_fields(record, fields) or board == null or catalog == null:
		return ServiceResult.failure(&"invalid_circuit_snapshot", "Circuit fields and trusted catalogs are required.")
	if not ControlContractValidation.is_integer(record["schema_version"], 1, 1) or not ControlContractValidation.is_integer(record["tick_number"], snapshot_tick, snapshot_tick) or not ControlContractValidation.is_integer(record["sequence"], 0, 9007199254740990):
		return ServiceResult.failure(&"invalid_circuit_sequence", "Circuit version, tick or sequence is invalid.")
	if record["board_definition_id"] != board.definition_id or not ControlContractValidation.is_integer(record["board_revision"], board.revision, board.revision):
		return ServiceResult.failure(&"unknown_circuit_board", "The saved board is not commissioned by this host.")
	var caps: ServiceResult = ControlContractValidation.decode_ids(record["host_capabilities"], 0, 64)
	if not caps.is_success or caps.value != capabilities or typeof(record["powered"]) != TYPE_BOOL:
		return ServiceResult.failure(&"invalid_circuit_capabilities", "Saved capabilities must match the server-owned host.")
	for field in ["modules", "wires", "pending"]:
		var limit: int = MAX_MODULES if field == "modules" else (MAX_WIRES if field == "wires" else MAX_PENDING)
		if typeof(record[field]) != TYPE_ARRAY or record[field].size() > limit:
			return ServiceResult.failure(&"circuit_snapshot_limit", "Circuit collections exceed their bounds.")
	var circuit := MachineControlCircuit.new()
	var commissioned: ServiceResult = circuit.commission(board, capabilities)
	if not commissioned.is_success:
		return commissioned
	for value in record["modules"]:
		if typeof(value) != TYPE_DICTIONARY:
			return ServiceResult.failure(&"invalid_saved_module", "Saved modules require exact inspection records.")
		var parsed: ServiceResult = MachineModuleInstance.from_record(value, catalog)
		if not parsed.is_success:
			return parsed
		var part: MachineModuleInstance = parsed.value
		var installed: ServiceResult = circuit.install(part.instance_id, part.slot_id, part.definition, part.integrity)
		if not installed.is_success:
			return installed
	for value in record["wires"]:
		var wire_fields := PackedStringArray(["wire_id", "first_module", "first_port", "second_module", "second_port"])
		if typeof(value) != TYPE_DICTIONARY or not ControlContractValidation.has_exact_fields(value, wire_fields):
			return ServiceResult.failure(&"invalid_saved_wire", "Saved wires require exact endpoint records.")
		for field in wire_fields:
			if not ControlContractValidation.is_id(value[field]):
				return ServiceResult.failure(&"invalid_saved_wire_id", "Wire endpoints must be stable strings.")
		var attached: ServiceResult = circuit.attach_wire(value["wire_id"], value["first_module"], value["first_port"], value["second_module"], value["second_port"])
		if not attached.is_success:
			return attached
	var previous_sequence: int = 0
	var previous_due: int = 0
	var seen: Dictionary = {}
	var fanouts: Dictionary = {}
	var emission_signatures: Dictionary = {}
	for value in record["pending"]:
		var pulse_fields := PackedStringArray(["wire_id", "source_module", "source_port", "target_module", "target_port", "due_tick", "sequence"])
		if typeof(value) != TYPE_DICTIONARY or not ControlContractValidation.has_exact_fields(value, pulse_fields):
			return ServiceResult.failure(&"invalid_saved_pulse", "Saved pulses require exact delivery records.")
		for field in ["wire_id", "source_module", "source_port", "target_module", "target_port"]:
			if not ControlContractValidation.is_id(value[field]):
				return ServiceResult.failure(&"invalid_saved_pulse_id", "Pulse endpoints must be stable strings.")
		if not ControlContractValidation.is_integer(value["sequence"], 1, int(record["sequence"])) or not ControlContractValidation.is_integer(value["due_tick"], 1, snapshot_tick + 1):
			return ServiceResult.failure(&"invalid_saved_pulse_time", "Pulse timing or sequence lies outside the saved frontier.")
		var sequence: int = int(value["sequence"])
		var due: int = int(value["due_tick"])
		var key: String = JSON.stringify([sequence, value["target_module"], value["target_port"]])
		if sequence < previous_sequence or due < previous_due or seen.has(key):
			return ServiceResult.failure(&"invalid_saved_pulse_order", "Pending pulses must be ordered and deduplicated.")
		seen[key] = true
		var signature: Array = [value["source_module"], value["source_port"], due]
		if emission_signatures.has(sequence) and emission_signatures[sequence] != signature:
			return ServiceResult.failure(&"invalid_saved_emission", "All receipts in one emission require the same source and due tick.")
		emission_signatures[sequence] = signature
		fanouts[sequence] = int(fanouts.get(sequence, 0)) + 1
		if fanouts[sequence] > MAX_FANOUT or not circuit._wires.has(value["wire_id"]):
			return ServiceResult.failure(&"invalid_saved_pulse_path", "A pulse exceeds fanout or references missing wiring.")
		var wire: Dictionary = circuit._wires[value["wire_id"]]
		var forward: bool = wire["first_module"] == value["source_module"] and wire["first_port"] == value["source_port"] and wire["second_module"] == value["target_module"] and wire["second_port"] == value["target_port"]
		var reverse: bool = wire["second_module"] == value["source_module"] and wire["second_port"] == value["source_port"] and wire["first_module"] == value["target_module"] and wire["first_port"] == value["target_port"]
		var source: Dictionary = circuit._port(value["source_module"], value["source_port"])
		var target: Dictionary = circuit._port(value["target_module"], value["target_port"])
		if (not forward and not reverse) or source.get("signal_type") != "pulse" or not ControlContractValidation.can_connect(source, target).is_success:
			return ServiceResult.failure(&"invalid_saved_pulse_route", "Saved pulses require a matching directed wired pulse path.")
		var delivery: Dictionary = value.duplicate(true)
		delivery["sequence"] = sequence
		delivery["due_tick"] = due
		circuit._pending.append(delivery)
		previous_sequence = sequence
		previous_due = due
	circuit._tick = snapshot_tick
	circuit._sequence = int(record["sequence"])
	circuit._powered = record["powered"]
	circuit._metrics["peak_pending"] = circuit._pending.size()
	return ServiceResult.success(circuit)


func _port(instance_id: String, port_id: String) -> Dictionary:
	var part := _modules.get(instance_id) as MachineModuleInstance
	if part != null:
		for port: Dictionary in part.definition.ports:
			if port["port_id"] == port_id:
				return port.duplicate(true)
	return {}


func _operable(instance_id: String) -> bool:
	var part := _modules.get(instance_id) as MachineModuleInstance
	if part == null or part.integrity <= 0.0:
		return false
	if part.definition.required_host_capabilities.has("power.consumer") and not _powered:
		return false
	for capability in part.definition.required_host_capabilities:
		if not _capabilities.has(capability):
			return false
	return true


func _deliver(delivery: Dictionary) -> ServiceResult:
	if not _wires.has(delivery["wire_id"]) or not _operable(delivery["source_module"]) or not _operable(delivery["target_module"]):
		return ServiceResult.failure(&"pulse_path_unavailable", "The pulse path lost a wire, power, or an operable part.")
	var wire: Dictionary = _wires[delivery["wire_id"]]
	var forward: bool = wire["first_module"] == delivery["source_module"] and wire["first_port"] == delivery["source_port"] and wire["second_module"] == delivery["target_module"] and wire["second_port"] == delivery["target_port"]
	var reverse: bool = wire["second_module"] == delivery["source_module"] and wire["second_port"] == delivery["source_port"] and wire["first_module"] == delivery["target_module"] and wire["first_port"] == delivery["target_port"]
	if not forward and not reverse:
		return ServiceResult.failure(&"pulse_path_changed", "The queued wire no longer joins the original endpoints.")
	var part := _modules[delivery["target_module"]] as MachineModuleInstance
	var handler: Callable = _handlers.get(part.definition.handler_id, Callable())
	if not handler.is_valid():
		return ServiceResult.failure(&"unbound_control_handler", "No trusted handler is commissioned for this module.")
	var result: Variant = handler.call(part.instance_id, delivery["target_port"], int(delivery["sequence"]), _tick)
	if not result is ServiceResult:
		return ServiceResult.failure(&"invalid_control_handler_result", "Trusted handlers must return ServiceResult.")
	return result
