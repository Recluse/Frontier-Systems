extends SimulationSystem
class_name AccessControlSystem

## Owns versioned access-controller, actuator, bypass-job, and tamper state.

const SYSTEM_ID: StringName = &"access_control"
const SNAPSHOT_SCHEMA_VERSION: int = 1
const MAX_DEVICES: int = 4096
const ELECTRICAL_TOOL: String = "tool.electrical_probe"
const MECHANICAL_TOOL: String = "tool.manual_release"
const PRY_TOOL: String = "tool.pry"
const PROTOTYPE_MANUAL_FORCE_NEWTONS: float = 1000.0
const BYPASS_DURATION_TICKS: int = 180
const OVERRIDE_DURATION_TICKS: int = 1800
const PROTOTYPE_AIRLOCK_ID: StringName = &"habitat_airlock"

var devices: Dictionary = {}
var current_tick: int = 0


func _init() -> void:
	system_id = SYSTEM_ID
	_create_prototype_state()


func simulate_tick(tick_number: int, _fixed_delta: float) -> void:
	current_tick = tick_number
	for device_id in _sorted_ids(devices):
		var device := devices[device_id] as AccessControlledDeviceState
		if device == null:
			continue
		for job_value in device.bypass_jobs:
			var job := job_value as BypassJobState
			if job == null or job.status != &"active":
				continue
			job.updated_tick = tick_number
			if not _job_preconditions_still_hold(device, job):
				job.status = &"failed"
				job.stage = &"restore"
				job.result_code = &"precondition_lost"
				device.add_tamper_event(job.actor_ids[0], job.target_id, job.route, job.result_code, tick_number)
				continue
			job.progress = minf(1.0, job.progress + 1.0 / float(job.total_work_ticks))
			job.stage = _stage_for_progress(job.progress)
			if job.progress >= 1.0:
				_complete_job(device, job, tick_number)
		device.prune_jobs()
		_expire_closed_overrides(device)
		_rebuild_controller_bypass_state(device)


## Trusted circuit adapter only; never expose directly as a player command.
## A latch request changes no credentials, bypass grants, door position, or gas.
func apply_circuit_latch_request(device_id: StringName, actuator_id: StringName, locked: bool, tick_number: int) -> ServiceResult:
	if tick_number != current_tick:
		return ServiceResult.failure(&"circuit_tick_mismatch", "Latch requests must run after access control in the same authoritative tick.")
	var device := devices.get(device_id) as AccessControlledDeviceState
	if device == null:
		return ServiceResult.failure(&"unknown_access_device", "The commissioned device does not exist.")
	var controller := device.controller()
	var actuator := device.actuator(actuator_id)
	if controller == null or controller.power_state != &"powered" or controller.integrity <= 0.0:
		return ServiceResult.failure(&"controller_unavailable", "The latch controller needs power and integrity.")
	if actuator == null or actuator.integrity <= 0.0 or actuator.mode != &"powered" or actuator.latch_state == &"damaged":
		return ServiceResult.failure(&"latch_unavailable", "The commissioned actuator has no usable powered latch.")
	if locked and actuator.position > 0.0:
		return ServiceResult.failure(&"door_not_closed", "Close the door before engaging its latch.")
	actuator.latch_state = &"engaged" if locked else &"released"
	return ServiceResult.success({"device_id": String(device_id), "actuator_id": String(actuator_id), "latch_state": String(actuator.latch_state)})


## Trusted pulse request; raising an alarm never clears or downgrades one.
func apply_circuit_alarm_request(device_id: StringName, tick_number: int) -> ServiceResult:
	if tick_number != current_tick:
		return ServiceResult.failure(&"circuit_tick_mismatch", "Alarm requests must run in the current authoritative access tick.")
	var device := devices.get(device_id) as AccessControlledDeviceState
	var controller: AccessControllerState = device.controller() if device != null else null
	if controller == null or controller.power_state != &"powered" or controller.integrity <= 0.0:
		return ServiceResult.failure(&"controller_unavailable", "An alarm needs a functional powered controller.")
	if controller.alarm_state in [&"disabled", &"faulted"]:
		return ServiceResult.failure(&"alarm_unavailable", "A disabled or faulted alarm cannot be activated by a pulse.")
	var changed: bool = controller.alarm_state == &"quiet"
	if changed:
		controller.alarm_state = &"local"
	return ServiceResult.success({"device_id": String(device_id), "alarm_state": String(controller.alarm_state), "changed": changed})


## Trusted isolation request. It does not repair controller faults.
func set_maintenance_isolation(device_id: StringName, isolated: bool) -> ServiceResult:
	var device := devices.get(device_id) as AccessControlledDeviceState
	var controller: AccessControllerState = device.controller() if device != null else null
	if controller == null or controller.integrity <= 0.0:
		return ServiceResult.failure(&"controller_unavailable", "Maintenance requires an intact controller.")
	var required_state: StringName = &"powered" if isolated else &"isolated"
	if controller.power_state != required_state:
		return ServiceResult.failure(&"invalid_isolation_state", "The controller is not in the expected maintenance power state.")
	for actuator: ActuatorState in device.actuators.values():
		if actuator.position > 0.0:
			return ServiceResult.failure(&"maintenance_door_open", "Close all host doors before changing maintenance isolation.")
	for job: BypassJobState in device.bypass_jobs:
		if job.status == &"active":
			return ServiceResult.failure(&"maintenance_job_conflict", "Finish bypass work before changing maintenance isolation.")
	controller.power_state = &"isolated" if isolated else &"powered"
	return ServiceResult.success({"power_state": String(controller.power_state)})


func profiling_counters() -> Dictionary:
	return {"devices": devices.size()}


func register_device(device: AccessControlledDeviceState) -> ServiceResult:
	if device == null or String(device.device_id).strip_edges().is_empty():
		return ServiceResult.failure(&"invalid_access_device", "A device with a stable ID is required.")
	if devices.has(device.device_id):
		return ServiceResult.failure(&"duplicate_access_device_id", "An access-controlled device with this ID is already registered.")
	if devices.size() >= MAX_DEVICES:
		return ServiceResult.failure(&"access_device_limit", "The access-control system has reached its device limit.")
	if device.security_controllers.is_empty() and device.actuators.is_empty():
		return ServiceResult.failure(&"access_capability_missing", "A device must provide a security controller, an actuator, or both.")
	var parsed: ServiceResult = AccessControlledDeviceState.from_record(device.to_record())
	if not parsed.is_success:
		return parsed
	devices[device.device_id] = parsed.value
	return ServiceResult.success({"device_id": device.device_id})


func validate_start_bypass(
	device_id: StringName,
	target_id: StringName,
	route: StringName,
	context: AuthenticatedCommandContext,
	request_id: StringName = &""
) -> ServiceResult:
	if context == null or String(context.principal_id).is_empty():
		return ServiceResult.failure(&"unauthenticated_bypass", "A server-authenticated actor is required for bypass work.")
	if String(request_id).strip_edges().is_empty():
		return ServiceResult.failure(&"missing_bypass_request_id", "A stable request ID is required for bypass work.")
	var device := devices.get(device_id) as AccessControlledDeviceState
	if device == null:
		return ServiceResult.failure(&"unknown_access_device", "The access-controlled device does not exist.")
	if request_id != &"":
		for existing_value in device.bypass_jobs:
			var existing := existing_value as BypassJobState
			if existing != null and existing.request_id == request_id:
				if existing.target_id == target_id and existing.route == route and existing.actor_ids.has(context.principal_id):
					return ServiceResult.success(existing.to_record())
				return ServiceResult.failure(&"idempotency_conflict", "The request ID was already used for a different bypass job.")
	if not AccessControlledDeviceState._is_valid_route(String(route)):
		return ServiceResult.failure(&"unknown_bypass_route", "The requested bypass route is not supported.")
	var actuator := device.actuator(target_id)
	if actuator == null:
		return ServiceResult.failure(&"unknown_bypass_target", "The requested door or actuator is not part of this device.")
	var controller := device.controller()
	if route in [&"electrical", &"combined"]:
		if not context.has_permission("airlock.bypass.electrical"):
			return ServiceResult.failure(&"permission_denied", "The actor is not authorized to perform electrical bypass work.")
		if not context.has_tool_capability(ELECTRICAL_TOOL):
			return ServiceResult.failure(&"required_tool_missing", "A compatible electrical diagnostic tool is required.")
		if controller == null or controller.power_state != &"powered" or controller.integrity <= 0.0:
			return ServiceResult.failure(&"controller_unavailable", "The security controller is unpowered, faulted, or too damaged to bypass electrically.")
	if route in [&"mechanical", &"combined"]:
		if not context.has_permission("airlock.bypass.mechanical"):
			return ServiceResult.failure(&"permission_denied", "The actor is not authorized to perform mechanical bypass work.")
		if not context.has_tool_capability(MECHANICAL_TOOL):
			return ServiceResult.failure(&"required_tool_missing", "A compatible manual-release tool is required.")
		if not actuator.manual_override_available or actuator.integrity <= 0.0:
			return ServiceResult.failure(&"manual_override_unavailable", "This actuator has no usable mechanical release path.")
	for existing_value in device.bypass_jobs:
		var existing := existing_value as BypassJobState
		if existing != null and existing.status == &"active" and existing.target_id == target_id:
			return ServiceResult.failure(&"bypass_job_in_progress", "A bypass job is already active on this actuator.")
	return ServiceResult.success({"device_id": device_id, "target_id": target_id, "route": route})


func start_bypass_job(
	request_id: StringName,
	device_id: StringName,
	target_id: StringName,
	route: StringName,
	context: AuthenticatedCommandContext
) -> ServiceResult:
	if context == null or String(context.principal_id).is_empty():
		return ServiceResult.failure(&"unauthenticated_bypass", "A server-authenticated actor is required for bypass work.")
	var device := devices.get(device_id) as AccessControlledDeviceState
	if device == null:
		return ServiceResult.failure(&"unknown_access_device", "The access-controlled device does not exist.")
	for existing_value in device.bypass_jobs:
		var existing := existing_value as BypassJobState
		if existing != null and existing.request_id == request_id:
			if existing.target_id == target_id and existing.route == route and existing.actor_ids.has(context.principal_id):
				return ServiceResult.success(existing.to_record())
			return ServiceResult.failure(&"idempotency_conflict", "The request ID was already used for a different bypass job.")
	var validation: ServiceResult = validate_start_bypass(device_id, target_id, route, context, request_id)
	if not validation.is_success:
		return validation
	var job := BypassJobState.new()
	job.job_id = StringName("bypass-%s" % request_id)
	job.request_id = request_id
	job.target_id = target_id
	job.route = route
	job.actor_ids.append(context.principal_id)
	job.created_tick = current_tick
	job.updated_tick = current_tick
	job.total_work_ticks = BYPASS_DURATION_TICKS * (2 if route == &"combined" else 1)
	if route in [&"electrical", &"combined"]:
		for tool_id in context.tool_ids_for_capability(ELECTRICAL_TOOL):
			job.tool_ids.append(StringName(tool_id))
	if route in [&"mechanical", &"combined"]:
		for tool_id in context.tool_ids_for_capability(MECHANICAL_TOOL):
			job.tool_ids.append(StringName(tool_id))
	device.bypass_jobs.append(job)
	device.prune_jobs()
	return ServiceResult.success(job.to_record())


func actor_can_control(device_id: StringName, target_id: StringName, actor_id: StringName, closing: bool = false) -> bool:
	var device := devices.get(device_id) as AccessControlledDeviceState
	if device == null:
		return false
	var actuator := device.actuator(target_id)
	if actuator == null:
		return false
	if closing and actuator.override_actor_id == actor_id and actuator.override_expires_tick >= 0:
		return true
	return actuator.authorizes_actor(actor_id, current_tick)


func validate_door_actuation(
	device_id: StringName,
	target_id: StringName,
	opening: bool,
	pressure_difference_kpa: float,
	manual_operation: bool = false,
	context: AuthenticatedCommandContext = null
) -> ServiceResult:
	var device := devices.get(device_id) as AccessControlledDeviceState
	if device == null:
		return ServiceResult.failure(&"unknown_access_device", "The access-controlled device does not exist.")
	var actuator := device.actuator(target_id)
	if actuator == null:
		return ServiceResult.failure(&"unknown_actuator", "The requested door actuator does not exist.")
	if actuator.mode in [&"disabled", &"jammed"] or actuator.integrity <= 0.0:
		return ServiceResult.failure(&"actuator_unavailable", "The door actuator is disabled, jammed, or inoperable.")
	if opening and actuator.latch_state == &"damaged":
		return ServiceResult.failure(&"latch_damaged", "The damaged latch must be repaired before the door can move.")
	var available_force: float = actuator.maximum_force_newtons
	if manual_operation:
		if context == null or not context.has_permission("airlock.manual_operate"):
			return ServiceResult.failure(&"permission_denied", "The actor cannot perform manual door work.")
		if not context.has_tool_capability(PRY_TOOL):
			return ServiceResult.failure(&"required_tool_missing", "A compatible prying tool is required to move this door manually.")
		if not actuator.manual_override_available:
			return ServiceResult.failure(&"manual_override_unavailable", "This door has no accessible manual movement path.")
		if actuator.latch_state != &"released":
			return ServiceResult.failure(&"door_locked", "Release the physical lock before moving the door manually.")
		available_force = PROTOTYPE_MANUAL_FORCE_NEWTONS
	else:
		var controller := device.controller()
		if controller == null or controller.integrity <= 0.0:
			return ServiceResult.failure(&"controller_unavailable", "Powered door operation requires a functional controller.")
		if controller.power_state != &"powered":
			return ServiceResult.failure(&"controller_unpowered", "Control power is unavailable; an unlocked door may still be moved manually.")
		if actuator.mode != &"powered":
			return ServiceResult.failure(&"powered_drive_unavailable", "This actuator cannot perform powered movement.")
	if not is_finite(pressure_difference_kpa) or pressure_difference_kpa < 0.0:
		return ServiceResult.failure(&"invalid_pressure_load", "The door pressure load is invalid.")
	var pressure_force_newtons: float = pressure_difference_kpa * 1000.0 * actuator.effective_pressure_area_m2
	if pressure_force_newtons > available_force:
		return ServiceResult.failure(&"actuator_force_exceeded", "The pressure load exceeds this actuator's force limit.")
	return ServiceResult.success({"pressure_force_newtons": pressure_force_newtons, "available_force_newtons": available_force, "manual_operation": manual_operation})


func update_actuator_position(device_id: StringName, target_id: StringName, is_open: bool) -> void:
	var device := devices.get(device_id) as AccessControlledDeviceState
	if device == null:
		return
	var actuator := device.actuator(target_id)
	if actuator != null:
		actuator.position = 1.0 if is_open else 0.0


func device_snapshot(device_id: StringName) -> ServiceResult:
	var device := devices.get(device_id) as AccessControlledDeviceState
	if device == null:
		return ServiceResult.failure(&"unknown_access_device", "The access-controlled device does not exist.")
	return ServiceResult.success(device.to_record())


func migrate_legacy_pressure_snapshot(pressure_record: Dictionary) -> ServiceResult:
	if typeof(pressure_record.get("airlocks")) != TYPE_ARRAY:
		return ServiceResult.failure(&"invalid_legacy_pressure_snapshot", "A legacy pressure snapshot must contain airlocks.")
	var device_records: Array[Dictionary] = []
	for airlock_record in pressure_record["airlocks"]:
		if typeof(airlock_record) != TYPE_DICTIONARY:
			return ServiceResult.failure(&"invalid_legacy_airlock", "A legacy airlock record must be an object.")
		var airlock_result: ServiceResult = AirlockState.from_record(airlock_record)
		if not airlock_result.is_success:
			return airlock_result
		var airlock: AirlockState = airlock_result.value
		var device: AccessControlledDeviceState = _new_airlock_access_device(
			airlock.airlock_id,
			airlock.inner_door_open,
			airlock.outer_door_open,
			airlock.airlock_id == PROTOTYPE_AIRLOCK_ID
		)
		device_records.append(device.to_record())
	if device_records.is_empty():
		return ServiceResult.failure(&"legacy_airlock_missing", "A legacy pressure snapshot contains no airlock security targets.")
	return ServiceResult.success({"schema_version": SNAPSHOT_SCHEMA_VERSION, "devices": device_records})


func capture_snapshot() -> ServiceResult:
	var device_records: Array[Dictionary] = []
	for device_id in _sorted_ids(devices):
		var device := devices[device_id] as AccessControlledDeviceState
		if device == null:
			return ServiceResult.failure(&"invalid_access_device", "The access system contains an invalid device.")
		device_records.append(device.to_record())
	return ServiceResult.success({"schema_version": SNAPSHOT_SCHEMA_VERSION, "devices": device_records})


func validate_snapshot_record(record: Dictionary, snapshot_tick_number: int) -> ServiceResult:
	var decoded: ServiceResult = _decode_snapshot_record(record, snapshot_tick_number)
	return ServiceResult.success() if decoded.is_success else decoded


func validate_pressure_links(pressure_record: Dictionary, access_record: Dictionary, snapshot_tick_number: int) -> ServiceResult:
	var decoded_access: ServiceResult = _decode_snapshot_record(access_record, snapshot_tick_number)
	if not decoded_access.is_success:
		return decoded_access
	if typeof(pressure_record.get("airlocks")) != TYPE_ARRAY:
		return ServiceResult.failure(&"invalid_pressure_links", "The pressure snapshot has no airlock list to validate.")
	var decoded_devices: Dictionary = decoded_access.value
	for airlock_record in pressure_record["airlocks"]:
		if typeof(airlock_record) != TYPE_DICTIONARY:
			return ServiceResult.failure(&"invalid_pressure_links", "An airlock reference is not a record object.")
		var airlock_result: ServiceResult = AirlockState.from_record(airlock_record)
		if not airlock_result.is_success:
			return airlock_result
		var airlock: AirlockState = airlock_result.value
		var device := decoded_devices.get(airlock.airlock_id) as AccessControlledDeviceState
		if device == null:
			return ServiceResult.failure(&"airlock_access_record_missing", "Every pressure airlock requires a matching access-control record.")
		var inner := device.actuator(StringName("%s-inner-door" % airlock.airlock_id))
		var outer := device.actuator(StringName("%s-outer-door" % airlock.airlock_id))
		if inner == null or outer == null:
			return ServiceResult.failure(&"airlock_actuator_missing", "A secured airlock requires both door actuator records.")
		if absf(inner.position - (1.0 if airlock.inner_door_open else 0.0)) > 0.000001:
			return ServiceResult.failure(&"airlock_actuator_mismatch", "The inner door state and access actuator position do not match.")
		if absf(outer.position - (1.0 if airlock.outer_door_open else 0.0)) > 0.000001:
			return ServiceResult.failure(&"airlock_actuator_mismatch", "The outer door state and access actuator position do not match.")
	return ServiceResult.success()


func restore_snapshot_record(record: Dictionary, snapshot_tick_number: int) -> ServiceResult:
	var decoded: ServiceResult = _decode_snapshot_record(record, snapshot_tick_number)
	if not decoded.is_success:
		return decoded
	devices = decoded.value
	current_tick = snapshot_tick_number
	return ServiceResult.success()


func _decode_snapshot_record(record: Dictionary, snapshot_tick_number: int) -> ServiceResult:
	if (
		record.size() != 2
		or typeof(record.get("schema_version")) != TYPE_INT
		or record.get("schema_version") != SNAPSHOT_SCHEMA_VERSION
		or typeof(record.get("devices")) != TYPE_ARRAY
		or record["devices"].is_empty()
		or record["devices"].size() > MAX_DEVICES
	):
		return ServiceResult.failure(&"invalid_access_snapshot", "The access-control system snapshot version or device list is invalid.")
	var decoded_devices: Dictionary = {}
	for device_record in record["devices"]:
		if typeof(device_record) != TYPE_DICTIONARY:
			return ServiceResult.failure(&"invalid_access_device", "Each access-controlled device must be an object.")
		var device_result: ServiceResult = AccessControlledDeviceState.from_record(device_record)
		if not device_result.is_success:
			return device_result
		var device: AccessControlledDeviceState = device_result.value
		if decoded_devices.has(device.device_id):
			return ServiceResult.failure(&"duplicate_access_device_id", "Access-controlled device IDs must be unique.")
		if device.security_controllers.is_empty() and device.actuators.is_empty():
			return ServiceResult.failure(&"access_capability_missing", "Each access device must have a security controller or actuator.")
		for job in device.bypass_jobs:
			if job.updated_tick > snapshot_tick_number:
				return ServiceResult.failure(&"future_bypass_job", "A bypass job cannot be updated after the snapshot world tick.")
		for event in device.tamper_events:
			if event["tick_number"] > snapshot_tick_number:
				return ServiceResult.failure(&"future_tamper_event", "A tamper event cannot be newer than the snapshot world tick.")
		decoded_devices[device.device_id] = device
	if decoded_devices.is_empty() or decoded_devices.size() > MAX_DEVICES:
		return ServiceResult.failure(&"access_device_limit", "The access snapshot must contain a supported number of devices.")
	return ServiceResult.success(decoded_devices)


func _complete_job(device: AccessControlledDeviceState, job: BypassJobState, tick_number: int) -> void:
	var actuator := device.actuator(job.target_id)
	var controller := device.controller()
	if actuator == null:
		job.status = &"failed"
		job.result_code = &"target_removed"
		job.stage = &"restore"
		device.add_tamper_event(job.actor_ids[0], job.target_id, job.route, job.result_code, tick_number)
		return
	actuator.override_actor_id = job.actor_ids[0]
	actuator.override_route = job.route
	actuator.override_expires_tick = tick_number + OVERRIDE_DURATION_TICKS
	if job.route in [&"mechanical", &"combined"]:
		actuator.latch_state = &"released"
	if controller != null and job.route in [&"electrical", &"combined"]:
		controller.alarm_state = &"local"
		if not controller.bypassed_channels.has(&"credential_reader"):
			controller.bypassed_channels.append(&"credential_reader")
	job.status = &"completed"
	job.stage = &"restore"
	job.progress = 1.0
	job.result_code = &"bypass_ready"
	job.updated_tick = tick_number
	device.add_tamper_event(job.actor_ids[0], job.target_id, job.route, job.result_code, tick_number)


func _job_preconditions_still_hold(device: AccessControlledDeviceState, job: BypassJobState) -> bool:
	var actuator := device.actuator(job.target_id)
	if actuator == null or actuator.integrity <= 0.0:
		return false
	var controller := device.controller()
	if job.route in [&"electrical", &"combined"]:
		if controller == null or controller.power_state != &"powered" or controller.integrity <= 0.0:
			return false
	if job.route in [&"mechanical", &"combined"] and not actuator.manual_override_available:
		return false
	return true


func _expire_closed_overrides(device: AccessControlledDeviceState) -> void:
	for actuator_value in device.actuators.values():
		var actuator := actuator_value as ActuatorState
		if actuator == null or actuator.override_expires_tick < 0 or actuator.override_expires_tick >= current_tick:
			continue
		if actuator.position <= 0.0:
			actuator.override_actor_id = &""
			actuator.override_route = &""
			actuator.override_expires_tick = -1
			if actuator.latch_state == &"released":
				actuator.latch_state = &"engaged"


func _rebuild_controller_bypass_state(device: AccessControlledDeviceState) -> void:
	var controller := device.controller()
	if controller == null:
		return
	var any_electrical_grant: bool = false
	for actuator_value in device.actuators.values():
		var actuator := actuator_value as ActuatorState
		if actuator != null and actuator.override_route in [&"electrical", &"combined"] and actuator.override_expires_tick >= current_tick:
			any_electrical_grant = true
	if not any_electrical_grant:
		controller.bypassed_channels.erase(&"credential_reader")


func _stage_for_progress(progress: float) -> StringName:
	if progress < 0.15:
		return &"inspect"
	if progress < 0.30:
		return &"access"
	if progress < 0.45:
		return &"isolate"
	if progress < 0.85:
		return &"perform"
	if progress < 1.0:
		return &"verify"
	return &"restore"


func _create_prototype_state() -> void:
	var device: AccessControlledDeviceState = _new_airlock_access_device(PROTOTYPE_AIRLOCK_ID, false, false, true)
	var registration: ServiceResult = register_device(device)
	if not registration.is_success:
		push_error("Prototype access device could not be registered: %s" % registration.message)


func _new_airlock_access_device(
	device_id: StringName,
	inner_door_open: bool,
	outer_door_open: bool,
	manual_override_available: bool
) -> AccessControlledDeviceState:
	var device := AccessControlledDeviceState.new()
	device.device_id = device_id
	device.access_policy = {
		"schema_version": 1,
		"policy_id": "access-%s" % device.device_id,
		"revision": 1,
		"default_decision": "deny",
		"grants": [],
	}
	var controller := AccessControllerState.new()
	controller.controller_id = StringName("%s-controller" % device.device_id)
	device.security_controllers[controller.controller_id] = controller
	var inner := ActuatorState.new()
	inner.actuator_id = StringName("%s-inner-door" % device.device_id)
	inner.position = 1.0 if inner_door_open else 0.0
	inner.maximum_force_newtons = 5000.0
	inner.effective_pressure_area_m2 = 1.0
	inner.manual_override_available = manual_override_available
	var outer := ActuatorState.new()
	outer.actuator_id = StringName("%s-outer-door" % device.device_id)
	outer.position = 1.0 if outer_door_open else 0.0
	outer.maximum_force_newtons = 5000.0
	outer.effective_pressure_area_m2 = 1.0
	outer.manual_override_available = manual_override_available
	device.actuators[inner.actuator_id] = inner
	device.actuators[outer.actuator_id] = outer
	return device


func _sorted_ids(values: Dictionary) -> Array:
	var ids: Array = values.keys()
	ids.sort_custom(func(left: Variant, right: Variant) -> bool: return String(left) < String(right))
	return ids
