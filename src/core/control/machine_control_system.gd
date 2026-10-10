extends SimulationSystem
class_name MachineControlSystem

## Authoritative prototype host. Catalog I/O occurs only during startup.
const SYSTEM_ID: StringName = &"machine_control"
const HOST_ID: StringName = &"habitat_airlock"
const ACTUATOR_ID: StringName = &"habitat_airlock-inner-door"
const RECEIVER_ID: String = "habitat_airlock-radio-receiver"
const LATCH_ID: String = "habitat_airlock-latch-module"
const ALARM_ID: String = "habitat_airlock-alarm-module"
const HOST_CAPABILITIES: Array[String] = ["power.consumer", "control.wired", "door.latch"]

var _access: AccessControlSystem
var _board: MachineControlBoardDefinition
var _catalog: MachineModuleRegistry
var _circuit: MachineControlCircuit
var _latch_adapter: DoorLatchPulseAdapter
var _alarm_adapter: LocalAlarmPulseAdapter
var _debug_requests: int = 0
var _last_error: String = ""
var _last_deliveries: Array = []
## Shared host maintenance tray, not a player inventory or a fabrication source.
var _salvage: Dictionary = {}
var _boards: Dictionary = {}
var _installed_board_id: String = "habitat-board-expanded"
var _board_spares: Dictionary = {}
var _board_job: BoardReplacementJob


func validate_maintenance(intent: MachineMaintenanceIntent, context: AuthenticatedCommandContext) -> ServiceResult:
	if _circuit == null or intent == null or context == null:
		return ServiceResult.failure(&"maintenance_unavailable", "An initialized circuit and authenticated intent are required.")
	if not OS.is_debug_build() or context.origin != AuthenticatedCommandContext.Origin.DEVELOPMENT_LOCAL or not context.has_permission("control.configure") or not context.has_tool_capability("tool.electrical_probe"):
		return ServiceResult.failure(&"permission_denied", "Prototype maintenance requires local development configuration grants and tools.")
	var parsed: ServiceResult = MachineMaintenanceIntent.from_record(intent.to_record())
	if not parsed.is_success:
		return parsed
	if _board_job != null:
		if intent.operation not in ["resume_board_job", "cancel_board_job"]:
			return ServiceResult.failure(&"board_job_reserved", "Finish or cancel reserved board work before other maintenance.")
		if String(context.principal_id) != _board_job.actor_id:
			return ServiceResult.failure(&"board_job_owner_required", "Only the initiating actor can resume or cancel this prototype job.")
		if intent.operation == "cancel_board_job":
			return parsed
	elif intent.operation in ["resume_board_job", "cancel_board_job"]:
		return ServiceResult.failure(&"board_job_missing", "There is no board job to resume or cancel.")
	var device := _access.devices.get(HOST_ID) as AccessControlledDeviceState
	var controller: AccessControllerState = device.controller() if device != null else null
	if controller == null or controller.integrity <= 0.0:
		return ServiceResult.failure(&"controller_unavailable", "Maintenance requires an intact controller.")
	for actuator: ActuatorState in device.actuators.values():
		if actuator.position > 0.0:
			return ServiceResult.failure(&"maintenance_door_open", "Close the host's doors before maintenance.")
	for job: BypassJobState in device.bypass_jobs:
		if job.status == &"active":
			return ServiceResult.failure(&"maintenance_job_conflict", "Finish active bypass work before maintenance.")
	if intent.operation == "isolate":
		if controller.power_state != &"powered":
			return ServiceResult.failure(&"invalid_isolation_state", "Only a powered controller can enter maintenance isolation.")
	elif controller.power_state != &"isolated":
		return ServiceResult.failure(&"maintenance_requires_isolation", "Isolate the controller before changing hardware or restoring maintenance power.")
	return parsed


## Validate and transfer synchronously at the tick boundary; failure retains parts.
func apply_maintenance(intent: MachineMaintenanceIntent, context: AuthenticatedCommandContext, request_id: StringName = &"") -> ServiceResult:
	var validated: ServiceResult = validate_maintenance(intent, context)
	if not validated.is_success:
		return validated
	var checked: MachineMaintenanceIntent = validated.value
	var args: Dictionary = checked.parameters
	match checked.operation:
		"replace_board":
			if not ControlContractValidation.is_id(String(request_id)) or not ControlContractValidation.is_id(String(context.principal_id)) or not _board_spares.has(args["target_board_id"]):
				return ServiceResult.failure(&"board_spare_missing", "Board replacement needs a stable request ID and an existing spare.")
			var target := _boards[_board_spares[args["target_board_id"]]] as MachineControlBoardDefinition
			var plan: ServiceResult = _circuit.plan_board_replacement(target)
			if not plan.is_success:
				return plan
			_board_job = BoardReplacementJob.new()
			_board_job.job_id = String(request_id)
			_board_job.actor_id = String(context.principal_id)
			_board_job.target_board_id = args["target_board_id"]
			_board_job.created_tick = _access.current_tick
			_board_job.updated_tick = _access.current_tick
			return ServiceResult.success(_board_job.to_record())
		"resume_board_job":
			_board_job.status = "active"
			return ServiceResult.success(_board_job.to_record())
		"cancel_board_job":
			var canceled_id: String = _board_job.job_id
			_board_job = null
			return ServiceResult.success({"job_id": canceled_id, "status": "canceled"})
		"isolate", "restore_power":
			var changed: ServiceResult = _access.set_maintenance_isolation(HOST_ID, checked.operation == "isolate")
			_refresh_power()
			return changed
		"remove":
			if _salvage.size() >= 64 or _salvage.has(args["instance_id"]):
				return ServiceResult.failure(&"salvage_tray_full", "The bounded maintenance tray cannot accept another part.")
			var removed: ServiceResult = _circuit.remove(args["instance_id"])
			if removed.is_success:
				_salvage[args["instance_id"]] = removed.value.duplicate(true)
			return removed
		"install":
			if not _salvage.has(args["instance_id"]):
				return ServiceResult.failure(&"salvage_part_missing", "Installation requires an existing part in this host's tray.")
			var parsed: ServiceResult = MachineModuleInstance.from_record(_salvage[args["instance_id"]], _catalog)
			if not parsed.is_success:
				return parsed
			var part: MachineModuleInstance = parsed.value
			var installed: ServiceResult = _circuit.install(part.instance_id, args["slot_id"], part.definition, part.integrity)
			if installed.is_success:
				_salvage.erase(part.instance_id)
			return installed
		"attach_wire":
			return _circuit.attach_wire(args["wire_id"], args["first_module"], args["first_port"], args["second_module"], args["second_port"])
		"detach_wire":
			return _circuit.detach_wire(args["wire_id"])
	return ServiceResult.failure(&"unknown_maintenance_operation", "The operation is unsupported.")


func _init() -> void:
	system_id = SYSTEM_ID
	tick_priority = 100


func configure(access: AccessControlSystem) -> ServiceResult:
	if _circuit != null or access == null:
		return ServiceResult.failure(&"invalid_control_setup", "Configure the control system once with access control.")
	_access = access
	_catalog = MachineModuleRegistry.new(PackedStringArray(["radio.receiver.v1", DoorLatchPulseAdapter.HANDLER_ID, LocalAlarmPulseAdapter.HANDLER_ID]))
	var board_record: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/control/boards/door_expanded.v2.json"))
	if typeof(board_record) != TYPE_DICTIONARY:
		return ServiceResult.failure(&"control_catalog_missing", "The prototype board fixture is missing or invalid.")
	var parsed: ServiceResult = MachineControlBoardDefinition.from_record(board_record)
	if not parsed.is_success:
		return parsed
	_board = parsed.value
	_boards[_board.revision] = _board
	var stock_record: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/control/boards/door_stock.v1.json"))
	if typeof(stock_record) != TYPE_DICTIONARY:
		return ServiceResult.failure(&"control_catalog_missing", "The stock board fixture is missing or invalid.")
	var stock: ServiceResult = MachineControlBoardDefinition.from_record(stock_record)
	if not stock.is_success:
		return stock
	var stock_board: MachineControlBoardDefinition = stock.value
	if stock_board.definition_id != _board.definition_id or stock_board.revision != 1 or _board.revision != 2:
		return ServiceResult.failure(&"invalid_board_catalog", "Prototype boards must use the pinned stock and expanded revisions.")
	_boards[stock_board.revision] = stock_board
	for path in ["res://data/control/modules/radio_receiver.v1.json", "res://data/control/modules/door_latch.v1.json", "res://data/control/modules/local_alarm.v1.json"]:
		var record: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(record) != TYPE_DICTIONARY:
			return ServiceResult.failure(&"control_catalog_missing", "A prototype module fixture is missing or invalid.")
		var registered: ServiceResult = _catalog.register_definition(record)
		if not registered.is_success:
			return registered
	var circuit := MachineControlCircuit.new()
	var commissioned: ServiceResult = circuit.commission(_board, PackedStringArray(HOST_CAPABILITIES))
	if not commissioned.is_success:
		return commissioned
	var receiver: ServiceResult = _catalog.get_definition("module.radio_receiver.industrial", 1)
	var latch: ServiceResult = _catalog.get_definition("module.door_latch.utility", 1)
	var alarm: ServiceResult = _catalog.get_definition("module.alarm.local.utility", 1)
	if not receiver.is_success or not latch.is_success or not alarm.is_success:
		return ServiceResult.failure(&"control_catalog_missing", "The prototype module definitions are unavailable.")
	var fitted: ServiceResult = circuit.install(RECEIVER_ID, "door.receiver.1", receiver.value)
	if not fitted.is_success:
		return fitted
	fitted = circuit.install(LATCH_ID, "door.utility.1", latch.value)
	if not fitted.is_success:
		return fitted
	var attached: ServiceResult = circuit.attach_wire("habitat_airlock-unlock-wire", RECEIVER_ID, "pulse_out", LATCH_ID, "unlock")
	if not attached.is_success:
		return attached
	var bound: ServiceResult = _bind(circuit)
	if not bound.is_success:
		return bound
	_circuit = circuit
	var spare_alarm := MachineModuleInstance.new()
	spare_alarm.instance_id = ALARM_ID
	spare_alarm.slot_id = "door.utility.2"
	spare_alarm.definition = alarm.value
	_salvage[ALARM_ID] = spare_alarm.to_record()
	_board_spares = {"habitat-board-stock": 1}
	_refresh_power()
	return ServiceResult.success()


## Development requests emit after the circuit advances, due on the next tick.
func request_debug_pulse() -> ServiceResult:
	if _circuit == null or _debug_requests >= 64:
		return ServiceResult.failure(&"control_request_full", "The prototype control request queue is unavailable or full.")
	_debug_requests += 1
	return ServiceResult.success({"status": "queued", "host_id": String(HOST_ID)})


func simulate_tick(tick_number: int, _fixed_delta: float) -> void:
	if _circuit == null:
		return
	_refresh_power()
	var result: ServiceResult = _circuit.advance_tick(tick_number)
	_last_deliveries = result.value if result.is_success else []
	if not result.is_success:
		_last_error = String(result.error_code)
	_advance_board_job(tick_number)
	var requests: int = _debug_requests
	_debug_requests = 0
	for _index in range(requests):
		var emitted: ServiceResult = _circuit.emit_pulse(RECEIVER_ID, "pulse_out")
		if not emitted.is_success:
			_last_error = String(emitted.error_code)


func diagnostics() -> Dictionary:
	var result: Dictionary = _circuit.diagnostics() if _circuit != null else {}
	result["last_error"] = _last_error
	result["last_deliveries"] = _last_deliveries.duplicate(true)
	result["salvage_parts"] = _salvage.size()
	result["board_revision"] = _board.revision if _board != null else 0
	result["board_job"] = _board_job.to_record() if _board_job != null else null
	return result


func profiling_counters() -> Dictionary:
	var counters: Dictionary = _circuit.diagnostics() if _circuit != null else {}
	counters.erase("tick_number")
	counters["salvage_parts"] = _salvage.size()
	counters["spare_boards"] = _board_spares.size()
	counters["board_work_ticks"] = _board_job.completed_work_ticks if _board_job != null else 0
	counters["board_job_active"] = 1 if _board_job != null and _board_job.status == "active" else 0
	return counters


func capture_snapshot() -> ServiceResult:
	if _circuit == null or _debug_requests != 0:
		return ServiceResult.failure(&"control_snapshot_unavailable", "Capture initialized controls after queued requests have run.")
	var captured: ServiceResult = _circuit.capture_record()
	if not captured.is_success:
		return captured
	var tray: Array[Dictionary] = []
	var ids: Array = _salvage.keys()
	ids.sort()
	for id in ids:
		tray.append(_salvage[id].duplicate(true))
	var spares: Array[Dictionary] = []
	ids = _board_spares.keys()
	ids.sort()
	for id in ids:
		spares.append({"instance_id": id, "definition_id": _board.definition_id, "revision": _board_spares[id]})
	return ServiceResult.success({"schema_version": 3, "host_id": String(HOST_ID), "circuit": captured.value, "salvage": tray,
		"installed_board_id": _installed_board_id, "board_spares": spares, "board_job": _board_job.to_record() if _board_job != null else null})


func validate_snapshot_record(record: Dictionary, snapshot_tick_number: int) -> ServiceResult:
	return _decode(record, snapshot_tick_number)


func restore_snapshot_record(record: Dictionary, snapshot_tick_number: int) -> ServiceResult:
	var decoded: ServiceResult = _decode(record, snapshot_tick_number)
	if not decoded.is_success:
		return decoded
	var circuit: MachineControlCircuit = decoded.value["circuit"]
	var bound: ServiceResult = _bind(circuit)
	if not bound.is_success:
		return bound
	_circuit = circuit
	_salvage = decoded.value["salvage"]
	_board = decoded.value["board"]
	_installed_board_id = decoded.value["installed_board_id"]
	_board_spares = decoded.value["board_spares"]
	_board_job = decoded.value["board_job"]
	if _board_job != null:
		_board_job.status = "paused"
	_debug_requests = 0
	_last_error = ""
	_last_deliveries = []
	_refresh_power()
	return ServiceResult.success()


## Older saves gain an empty board, never installed modules or exposed triggers.
func migrate_legacy_snapshot(snapshot_tick_number: int) -> ServiceResult:
	if _board == null:
		return ServiceResult.failure(&"control_catalog_missing", "Control catalogs must be initialized before migration.")
	var empty := MachineControlCircuit.new()
	var commissioned: ServiceResult = empty.commission(_board, PackedStringArray(HOST_CAPABILITIES))
	if not commissioned.is_success:
		return commissioned
	var captured: ServiceResult = empty.capture_record()
	var circuit_record: Dictionary = captured.value
	circuit_record["tick_number"] = snapshot_tick_number
	return ServiceResult.success({"schema_version": 1, "host_id": String(HOST_ID), "circuit": circuit_record})


## Validate saved host/actuator references before any system restore mutates state.
func validate_access_links(access_record: Dictionary, control_record: Dictionary = {}) -> ServiceResult:
	var devices_value: Variant = access_record.get("devices")
	if typeof(devices_value) != TYPE_ARRAY:
		return ServiceResult.failure(&"invalid_control_host", "Controls require a saved access device list.")
	for device in devices_value:
		if typeof(device) != TYPE_DICTIONARY or device.get("device_id") != String(HOST_ID):
			continue
		var actuators: Variant = device.get("actuators")
		if typeof(actuators) != TYPE_ARRAY:
			break
		for actuator in actuators:
			if typeof(actuator) == TYPE_DICTIONARY and actuator.get("actuator_id") == String(ACTUATOR_ID):
				var job_value: Variant = control_record.get("board_job")
				if typeof(job_value) == TYPE_DICTIONARY and job_value.get("status") == "active":
					var parsed: ServiceResult = AccessControlledDeviceState.from_record(device)
					if not parsed.is_success:
						return parsed
					if not _board_work_ready(parsed.value):
						return ServiceResult.failure(&"invalid_active_board_job", "Active saved board work requires isolated, closed hardware without bypass work.")
				return ServiceResult.success()
	return ServiceResult.failure(&"control_target_missing", "The commissioned latch target must exist in the saved host.")


func _decode(record: Dictionary, snapshot_tick_number: int) -> ServiceResult:
	if not ControlContractValidation.is_integer(record.get("schema_version"), 1, 3):
		return ServiceResult.failure(&"unsupported_control_system_version", "The control system version is unsupported.")
	var fields := PackedStringArray(["schema_version", "host_id", "circuit"])
	if int(record["schema_version"]) >= 2:
		fields.append("salvage")
	if int(record["schema_version"]) == 3:
		fields.append_array(PackedStringArray(["installed_board_id", "board_spares", "board_job"]))
	if not ControlContractValidation.has_exact_fields(record, fields) or record.get("host_id") != String(HOST_ID) or typeof(record.get("circuit")) != TYPE_DICTIONARY:
		return ServiceResult.failure(&"invalid_control_system_snapshot", "The prototype control system record is invalid.")
	var revision_value: Variant = record["circuit"].get("board_revision")
	if not ControlContractValidation.is_integer(revision_value, 1, 2):
		return ServiceResult.failure(&"unknown_control_board", "The saved board revision is not in the trusted catalog.")
	var saved_board := _boards.get(int(revision_value)) as MachineControlBoardDefinition
	var decoded: ServiceResult = MachineControlCircuit.from_record(record["circuit"], saved_board, _catalog, PackedStringArray(HOST_CAPABILITIES), snapshot_tick_number)
	if not decoded.is_success:
		return decoded
	var circuit: MachineControlCircuit = decoded.value
	var tray: Dictionary = {}
	var values: Variant = record.get("salvage", [])
	if typeof(values) != TYPE_ARRAY or values.size() > 64:
		return ServiceResult.failure(&"invalid_salvage_tray", "Saved maintenance trays hold at most 64 parts.")
	for value in values:
		if typeof(value) != TYPE_DICTIONARY:
			return ServiceResult.failure(&"invalid_salvage_part", "Saved salvage must contain inspection records.")
		var parsed: ServiceResult = MachineModuleInstance.from_record(value, _catalog)
		if not parsed.is_success:
			return parsed
		var part: MachineModuleInstance = parsed.value
		if tray.has(part.instance_id) or circuit.module_record(part.instance_id).is_success:
			return ServiceResult.failure(&"duplicate_salvage_identity", "A part cannot occur in both the tray and installed hardware.")
		tray[part.instance_id] = part.to_record()
	var installed_id: Variant = record.get("installed_board_id", "legacy-habitat-board")
	var spare_values: Variant = record.get("board_spares", [])
	if not ControlContractValidation.is_id(installed_id) or tray.has(installed_id) or circuit.module_record(installed_id).is_success or typeof(spare_values) != TYPE_ARRAY or spare_values.size() > 64:
		return ServiceResult.failure(&"invalid_saved_boards", "Board identities and spare count must be valid.")
	var spares: Dictionary = {}
	for value in spare_values:
		if typeof(value) != TYPE_DICTIONARY or not ControlContractValidation.has_exact_fields(value, PackedStringArray(["instance_id", "definition_id", "revision"])):
			return ServiceResult.failure(&"invalid_board_spare", "A spare requires an exact board reference record.")
		if not ControlContractValidation.is_id(value["instance_id"]) or value["definition_id"] != saved_board.definition_id or not ControlContractValidation.is_integer(value["revision"], 1, 2):
			return ServiceResult.failure(&"invalid_board_spare_reference", "Spare boards must resolve to trusted definitions.")
		var id: String = value["instance_id"]
		if id == installed_id or spares.has(id) or tray.has(id) or circuit.module_record(id).is_success:
			return ServiceResult.failure(&"duplicate_board_identity", "Boards and modules must have distinct owned identities.")
		spares[id] = int(value["revision"])
	var job: BoardReplacementJob = null
	var job_value: Variant = record.get("board_job")
	if job_value != null:
		if typeof(job_value) != TYPE_DICTIONARY:
			return ServiceResult.failure(&"invalid_board_job", "A saved job must be null or a record.")
		var parsed_job: ServiceResult = BoardReplacementJob.from_record(job_value, snapshot_tick_number)
		if not parsed_job.is_success:
			return parsed_job
		job = parsed_job.value
		if not spares.has(job.target_board_id) or spares.size() > 64:
			return ServiceResult.failure(&"board_reservation_missing", "A saved board job must reserve an existing spare.")
		var plan: ServiceResult = circuit.plan_board_replacement(_boards[spares[job.target_board_id]])
		if not plan.is_success:
			return plan
	return ServiceResult.success({"circuit": circuit, "salvage": tray, "board": saved_board,
		"installed_board_id": String(installed_id), "board_spares": spares, "board_job": job})


func _advance_board_job(tick_number: int) -> void:
	if _board_job == null or _board_job.status != "active":
		return
	_board_job.updated_tick = tick_number
	var device := _access.devices.get(HOST_ID) as AccessControlledDeviceState
	if not _board_work_ready(device):
		_board_job.status = "paused"
		_last_error = "board_work_precondition_lost"
		return
	_board_job.completed_work_ticks += 1
	if _board_job.completed_work_ticks < BoardReplacementJob.WORK_TICKS:
		return
	var target_id: String = _board_job.target_board_id
	var target := _boards[_board_spares[target_id]] as MachineControlBoardDefinition
	var applied: ServiceResult = _circuit.replace_board(target)
	if not applied.is_success:
		_board_job.completed_work_ticks = BoardReplacementJob.WORK_TICKS - 1
		_board_job.status = "paused"
		_last_error = String(applied.error_code)
		return
	_board_spares.erase(target_id)
	_board_spares[_installed_board_id] = _board.revision
	_installed_board_id = target_id
	_board = target
	_board_job = null


func _board_work_ready(device: AccessControlledDeviceState) -> bool:
	if device == null:
		return false
	var controller := device.controller()
	if controller == null or controller.integrity <= 0.0 or controller.power_state != &"isolated":
		return false
	for actuator: ActuatorState in device.actuators.values():
		if actuator.position > 0.0:
			return false
	for job: BypassJobState in device.bypass_jobs:
		if job.status == &"active":
			return false
	return true


func _bind(circuit: MachineControlCircuit) -> ServiceResult:
	var adapter := DoorLatchPulseAdapter.new(_access, LATCH_ID, HOST_ID, ACTUATOR_ID)
	var bound: ServiceResult = circuit.bind_handler(DoorLatchPulseAdapter.HANDLER_ID, adapter.receive_pulse)
	if not bound.is_success:
		return bound
	var alarm := LocalAlarmPulseAdapter.new(_access, ALARM_ID, HOST_ID)
	bound = circuit.bind_handler(LocalAlarmPulseAdapter.HANDLER_ID, alarm.receive_pulse)
	if bound.is_success:
		_latch_adapter = adapter
		_alarm_adapter = alarm
	return bound


func _refresh_power() -> void:
	var device := _access.devices.get(HOST_ID) as AccessControlledDeviceState
	var controller: AccessControllerState = device.controller() if device != null else null
	_circuit.set_powered(controller != null and controller.power_state == &"powered" and controller.integrity > 0.0)
