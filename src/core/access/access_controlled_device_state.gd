extends RefCounted
class_name AccessControlledDeviceState

## Versioned security, actuator, work-job, and tamper state for one device.

const SCHEMA_VERSION: int = 1
const MAX_JOBS: int = 256
const MAX_TAMPER_EVENTS: int = 256

var device_id: StringName
var access_policy: Dictionary = {}
var security_controllers: Dictionary = {}
var actuators: Dictionary = {}
var bypass_jobs: Array[BypassJobState] = []
var tamper_events: Array[Dictionary] = []


func controller() -> AccessControllerState:
	for controller_id in _sorted_ids(security_controllers):
		return security_controllers[controller_id] as AccessControllerState
	return null


func actuator(actuator_id: StringName) -> ActuatorState:
	return actuators.get(actuator_id) as ActuatorState


func to_record() -> Dictionary:
	var controllers: Array[Dictionary] = []
	for controller_id in _sorted_ids(security_controllers):
		var controller_state := security_controllers[controller_id] as AccessControllerState
		controllers.append(controller_state.to_record())
	var actuator_records: Array[Dictionary] = []
	for actuator_id in _sorted_ids(actuators):
		var actuator_state := actuators[actuator_id] as ActuatorState
		actuator_records.append(actuator_state.to_record())
	var job_records: Array[Dictionary] = []
	for job in bypass_jobs:
		job_records.append(job.to_record())
	return {
		"schema_version": SCHEMA_VERSION,
		"device_id": String(device_id),
		"access_policy": access_policy.duplicate(true),
		"security_controllers": controllers,
		"actuators": actuator_records,
		"bypass_jobs": job_records,
		"tamper_events": tamper_events.duplicate(true),
	}


func actor_can_control(actuator_id: StringName, actor_id: StringName, tick_number: int) -> bool:
	var target_actuator := actuator(actuator_id)
	return target_actuator != null and target_actuator.authorizes_actor(actor_id, tick_number)


func add_tamper_event(actor_id: StringName, target_id: StringName, route: StringName, result_code: StringName, tick_number: int) -> void:
	tamper_events.append({
		"event_id": "%s-tamper-%d-%d" % [device_id, tick_number, tamper_events.size() + 1],
		"actor_id": String(actor_id),
		"target_id": String(target_id),
		"route": String(route),
		"result_code": String(result_code),
		"tick_number": tick_number,
	})
	while tamper_events.size() > MAX_TAMPER_EVENTS:
		tamper_events.pop_front()


func prune_jobs() -> void:
	while bypass_jobs.size() > MAX_JOBS:
		var removable_index: int = -1
		for index in range(bypass_jobs.size()):
			var candidate := bypass_jobs[index] as BypassJobState
			if candidate.status != &"active" and candidate.status != &"queued":
				removable_index = index
				break
		if removable_index < 0:
			break
		bypass_jobs.remove_at(removable_index)


static func from_record(record: Dictionary) -> ServiceResult:
	if typeof(record.get("schema_version")) != TYPE_INT or record["schema_version"] != SCHEMA_VERSION:
		return ServiceResult.failure(&"unsupported_access_device_version", "The access-controlled device record version is not supported.")
	var required_keys := ["schema_version", "device_id", "access_policy", "security_controllers", "actuators", "bypass_jobs", "tamper_events"]
	if record.size() != required_keys.size():
		return ServiceResult.failure(&"invalid_access_device_record", "The access-controlled device record has missing or unsupported fields.")
	for required_key in required_keys:
		if not record.has(required_key):
			return ServiceResult.failure(&"invalid_access_device_record", "The access-controlled device record is missing a required field.")
	var id_value: Variant = record.get("device_id")
	if typeof(id_value) != TYPE_STRING or String(id_value).strip_edges().is_empty():
		return ServiceResult.failure(&"invalid_access_device_id", "An access-controlled device requires a stable ID.")
	var policy_result: ServiceResult = _decode_access_policy(record.get("access_policy"))
	if not policy_result.is_success:
		return policy_result
	for collection_name in ["security_controllers", "actuators", "bypass_jobs", "tamper_events"]:
		if typeof(record.get(collection_name)) != TYPE_ARRAY:
			return ServiceResult.failure(&"invalid_access_device_record", "Access device collections must be arrays.")
	if (
		record["security_controllers"].size() > 128
		or record["actuators"].size() > 128
		or record["bypass_jobs"].size() > MAX_JOBS
		or record["tamper_events"].size() > MAX_TAMPER_EVENTS
	):
		return ServiceResult.failure(&"access_history_limit", "Access device state exceeds a configured record limit.")
	var device := AccessControlledDeviceState.new()
	device.device_id = StringName(id_value)
	device.access_policy = policy_result.value
	var seen_job_ids: Dictionary = {}
	var seen_request_ids: Dictionary = {}
	var seen_event_ids: Dictionary = {}
	for controller_record in record["security_controllers"]:
		if typeof(controller_record) != TYPE_DICTIONARY:
			return ServiceResult.failure(&"invalid_access_controller_record", "Each security controller must be an object.")
		var controller_result: ServiceResult = AccessControllerState.from_record(controller_record)
		if not controller_result.is_success:
			return controller_result
		var controller_state: AccessControllerState = controller_result.value
		if device.security_controllers.has(controller_state.controller_id):
			return ServiceResult.failure(&"duplicate_access_controller_id", "Security-controller IDs must be unique per device.")
		device.security_controllers[controller_state.controller_id] = controller_state
	for actuator_record in record["actuators"]:
		if typeof(actuator_record) != TYPE_DICTIONARY:
			return ServiceResult.failure(&"invalid_actuator_record", "Each actuator must be an object.")
		var actuator_result: ServiceResult = ActuatorState.from_record(actuator_record)
		if not actuator_result.is_success:
			return actuator_result
		var actuator_state: ActuatorState = actuator_result.value
		if device.actuators.has(actuator_state.actuator_id):
			return ServiceResult.failure(&"duplicate_actuator_id", "Actuator IDs must be unique per device.")
		device.actuators[actuator_state.actuator_id] = actuator_state
	for job_record in record["bypass_jobs"]:
		if typeof(job_record) != TYPE_DICTIONARY:
			return ServiceResult.failure(&"invalid_bypass_job", "Each bypass job must be an object.")
		var job_result: ServiceResult = BypassJobState.from_record(job_record)
		if not job_result.is_success:
			return job_result
		var job: BypassJobState = job_result.value
		if job.target_id not in device.actuators:
			return ServiceResult.failure(&"bypass_target_missing", "A bypass job must reference an actuator on its device.")
		if seen_job_ids.has(job.job_id) or seen_request_ids.has(job.request_id):
			return ServiceResult.failure(&"duplicate_bypass_job_id", "Bypass job and request IDs must be unique per device.")
		seen_job_ids[job.job_id] = true
		seen_request_ids[job.request_id] = true
		device.bypass_jobs.append(job)
	for event_record in record["tamper_events"]:
		if typeof(event_record) != TYPE_DICTIONARY or not _is_valid_tamper_event(event_record, device.device_id):
			return ServiceResult.failure(&"invalid_tamper_event", "A tamper event is invalid or references another device.")
		if seen_event_ids.has(event_record["event_id"]):
			return ServiceResult.failure(&"duplicate_tamper_event_id", "Tamper event IDs must be unique per device.")
		seen_event_ids[event_record["event_id"]] = true
		device.tamper_events.append(event_record.duplicate(true))
	if device.security_controllers.is_empty() and device.actuators.is_empty():
		return ServiceResult.failure(&"access_capability_missing", "A device must have a controller, an actuator, or both.")
	if device.bypass_jobs.size() > MAX_JOBS or device.tamper_events.size() > MAX_TAMPER_EVENTS:
		return ServiceResult.failure(&"access_history_limit", "Access job and tamper history exceed their configured limits.")
	return ServiceResult.success(device)


static func _decode_access_policy(value: Variant) -> ServiceResult:
	if typeof(value) != TYPE_DICTIONARY:
		return ServiceResult.failure(&"invalid_access_policy", "An access policy record is required.")
	var policy: Dictionary = value
	var policy_keys := ["schema_version", "policy_id", "revision", "default_decision", "grants"]
	if policy.size() != policy_keys.size():
		return ServiceResult.failure(&"invalid_access_policy", "The access policy has missing or unsupported fields.")
	for policy_key in policy_keys:
		if not policy.has(policy_key):
			return ServiceResult.failure(&"invalid_access_policy", "The access policy is missing a required field.")
	if (
		typeof(policy.get("schema_version")) != TYPE_INT
		or policy.get("schema_version") != 1
		or typeof(policy.get("policy_id")) != TYPE_STRING
		or String(policy.get("policy_id", "")).strip_edges().is_empty()
		or typeof(policy.get("revision")) != TYPE_INT
		or int(policy.get("revision", 0)) < 1
		or not ["allow", "deny"].has(policy.get("default_decision"))
		or typeof(policy.get("grants")) != TYPE_ARRAY
	):
		return ServiceResult.failure(&"invalid_access_policy", "The device access policy is malformed.")
	if policy["grants"].size() > 256:
		return ServiceResult.failure(&"invalid_access_policy", "The access policy has too many grants.")
	for grant in policy["grants"]:
		if typeof(grant) != TYPE_DICTIONARY or grant.size() != 3:
			return ServiceResult.failure(&"invalid_access_policy", "Each access grant must contain only its declared fields.")
		var grant_has_all_fields: bool = true
		for grant_field in ["subject_kind", "subject_id", "action_ids"]:
			if not grant.has(grant_field):
				grant_has_all_fields = false
		if (
			not grant_has_all_fields
			or not ["principal", "role", "group"].has(grant.get("subject_kind"))
			or typeof(grant.get("subject_id")) != TYPE_STRING
			or String(grant.get("subject_id", "")).strip_edges().is_empty()
			or typeof(grant.get("action_ids")) != TYPE_ARRAY
			or grant["action_ids"].is_empty()
			or grant["action_ids"].size() > 64
		):
			return ServiceResult.failure(&"invalid_access_policy", "An access grant is malformed.")
		var seen_actions: Dictionary = {}
		for action_id in grant["action_ids"]:
			if typeof(action_id) != TYPE_STRING or String(action_id).strip_edges().is_empty() or seen_actions.has(action_id):
				return ServiceResult.failure(&"invalid_access_policy", "Access grant action IDs must be unique non-empty strings.")
			seen_actions[action_id] = true
	return ServiceResult.success(policy.duplicate(true))


static func _is_valid_route(route: String) -> bool:
	return ["electrical", "mechanical", "combined"].has(route)


static func _is_valid_tamper_event(record: Dictionary, expected_device_id: StringName) -> bool:
	if record.size() != 6:
		return false
	for field_name in ["event_id", "actor_id", "target_id", "route", "result_code"]:
		if typeof(record.get(field_name)) != TYPE_STRING or String(record[field_name]).strip_edges().is_empty():
			return false
	if typeof(record.get("tick_number")) != TYPE_INT or int(record["tick_number"]) < 0:
		return false
	if not ["electrical", "mechanical", "combined", "unknown"].has(record.get("route")):
		return false
	return String(record.get("event_id", "")).begins_with("%s-" % expected_device_id)


func _sorted_ids(values: Dictionary) -> Array:
	var ids: Array = values.keys()
	ids.sort_custom(func(left: Variant, right: Variant) -> bool: return String(left) < String(right))
	return ids
