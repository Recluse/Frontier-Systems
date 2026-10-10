extends RefCounted
class_name BodyInventoryInteractionJob

## Fixed-tick precondition/progress state. Readiness is not a transfer permission.
const MAX_EXACT_INTEGER: int = 9007199254740990
const CONTEXT_FIELDS: Array[String] = ["actor_control_epoch", "target_action_epoch", "actor_inventory_revision", "target_inventory_revision"]
const STATES: Array[String] = ["active", "ready", "paused", "cancelled"]
var _record: Dictionary = {}
var _policy: BodyInventoryInteractionPolicy


func to_record() -> Dictionary:
	return _record.duplicate(true)


func policy_record() -> Dictionary:
	return _policy.to_record()


static func start(record: Dictionary, policy: BodyInventoryInteractionPolicy, observation: Dictionary) -> ServiceResult:
	var parsed: ServiceResult = _parse(record, policy)
	if not parsed.is_success:
		return parsed
	var job: BodyInventoryInteractionJob = parsed.value
	if record["state"] != "active" or int(record["progress_ticks"]) != 0 or record["cancellation_code"] != "" or int(record["last_tick"]) >= MAX_EXACT_INTEGER:
		return _failure("New jobs must start active with no progress or cancellation.")
	var assessed: ServiceResult = policy.assess(record["action"], observation)
	return ServiceResult.success(job) if assessed.is_success else assessed


## Restore always pauses unfinished jobs. The owner must explicitly revalidate/resume.
static func from_record(record: Dictionary, policy: BodyInventoryInteractionPolicy) -> ServiceResult:
	var parsed: ServiceResult = _parse(record, policy)
	if parsed.is_success and parsed.value._record["state"] != "cancelled":
		parsed.value._record["state"] = "paused"
	return parsed


func resume(tick: int, context: Dictionary, observation: Dictionary) -> ServiceResult:
	if _record["state"] != "paused" or tick < int(_record["last_tick"]) or tick >= MAX_EXACT_INTEGER:
		return _failure("Only a paused job can resume at a valid current tick.")
	var checked: ServiceResult = _check_context(context, observation)
	if not checked.is_success:
		_cancel(String(checked.error_code))
		return checked
	_record["last_tick"] = tick
	_record["state"] = "active"
	# Completed pre-restart timing still needs one freshly validated tick after resume.
	_record["progress_ticks"] = mini(int(_record["progress_ticks"]), _duration() - 1)
	return ServiceResult.success()


func advance(tick: int, context: Dictionary, observation: Dictionary) -> ServiceResult:
	if _record["state"] != "active" or tick != int(_record["last_tick"]) + 1 or tick > MAX_EXACT_INTEGER:
		return _failure("Active jobs require exactly one consecutive fixed tick.")
	var checked: ServiceResult = _check_context(context, observation)
	_record["last_tick"] = tick
	if not checked.is_success:
		_cancel(String(checked.error_code))
		return checked
	_record["progress_ticks"] = int(_record["progress_ticks"]) + 1
	if int(_record["progress_ticks"]) == _duration():
		_record["state"] = "ready"
	return ServiceResult.success({"state": _record["state"], "progress_ticks": _record["progress_ticks"]})


## Owner must consume this candidate only in the same tick, with an atomic receipt.
func completion_candidate(tick: int, context: Dictionary, observation: Dictionary) -> ServiceResult:
	if _record["state"] != "ready" or tick != int(_record["last_tick"]):
		return _failure("A job must be freshly ready in this completion tick.")
	var checked: ServiceResult = _check_context(context, observation)
	if not checked.is_success:
		_cancel(String(checked.error_code))
		return checked
	return ServiceResult.success(to_record())


func cancel() -> void:
	if _record["state"] != "cancelled":
		_cancel("actor_cancelled")


func _cancel(code: String) -> void:
	_record["state"] = "cancelled"
	_record["cancellation_code"] = code


func _duration() -> int:
	return int(_policy.to_record()["duration_ticks"][_record["action"]])


func _check_context(context: Dictionary, observation: Dictionary) -> ServiceResult:
	if not ControlContractValidation.has_exact_fields(context, PackedStringArray(CONTEXT_FIELDS)):
		return _failure("Every trusted action/control epoch and inventory revision is required.")
	for field in CONTEXT_FIELDS:
		if not ControlContractValidation.is_integer(context[field], 0, MAX_EXACT_INTEGER):
			return _failure("Context counters must be bounded exact integers.")
		if int(context[field]) != int(_record[field]):
			return ServiceResult.failure(&"body_interaction_context_changed", "Control, resistance/movement or inventory state changed during the attempt.")
	return _policy.assess(_record["action"], observation)


static func _parse(record: Dictionary, policy: BodyInventoryInteractionPolicy) -> ServiceResult:
	var fields := PackedStringArray(["schema_version", "job_id", "actor_body_id", "target_body_id", "policy_id", "policy_revision", "action", "target_container_id", "item_id", "slot_id", "last_tick", "progress_ticks", "state", "cancellation_code"])
	fields.append_array(PackedStringArray(CONTEXT_FIELDS))
	if policy == null or not ControlContractValidation.has_exact_fields(record, fields) or not ControlContractValidation.is_integer(record.get("schema_version"), 1, 1):
		return _failure("A complete versioned job and trusted policy are required.")
	for field in ["job_id", "actor_body_id", "target_body_id", "policy_id", "target_container_id"]:
		if not ControlContractValidation.is_id(record[field]):
			return _failure("Job targets and identities must be stable IDs.")
	if record["actor_body_id"] == record["target_body_id"] or not BodyInventoryInteractionPolicy.ACTIONS.has(record["action"]) or not STATES.has(record["state"]):
		return _failure("This job requires distinct bodies and registered action/state values.")
	for field in ["item_id", "slot_id", "cancellation_code"]:
		if typeof(record[field]) != TYPE_STRING or (record[field] != "" and not ControlContractValidation.is_id(record[field])):
			return _failure("Optional identifiers must be bounded strings.")
	if (record["action"] == "search" and record["item_id"] != "") or (record["action"] != "search" and record["item_id"] == ""):
		return _failure("Search has no item target; other actions require one.")
	if (record["action"] in ["equip", "unequip"] and record["slot_id"] == "") or (record["action"] not in ["equip", "unequip"] and record["slot_id"] != ""):
		return _failure("Equipment actions alone require a slot target.")
	var rules: Dictionary = policy.to_record()
	if not ControlContractValidation.is_integer(record["policy_revision"], 1, MAX_EXACT_INTEGER) or record["policy_id"] != rules["definition_id"] or int(record["policy_revision"]) != int(rules["revision"]):
		return _failure("The policy must match the pinned trusted revision.")
	for field in CONTEXT_FIELDS + ["last_tick"]:
		if not ControlContractValidation.is_integer(record[field], 0, MAX_EXACT_INTEGER):
			return _failure("Job counters must be bounded exact integers.")
	var duration: int = int(rules["duration_ticks"][record["action"]])
	if not ControlContractValidation.is_integer(record["progress_ticks"], 0, duration) or int(record["progress_ticks"]) > int(record["last_tick"]):
		return _failure("Job progress must be within the policy duration.")
	if (record["state"] == "ready" and int(record["progress_ticks"]) != duration) or (record["state"] == "active" and int(record["progress_ticks"]) >= duration) or ((record["state"] == "cancelled") != (record["cancellation_code"] != "")):
		return _failure("Job state, progress and cancellation must agree.")
	var job := BodyInventoryInteractionJob.new()
	job._record = record.duplicate(true)
	job._policy = BodyInventoryInteractionPolicy.from_record(rules).value
	return ServiceResult.success(job)


static func _failure(message: String) -> ServiceResult:
	return ServiceResult.failure(&"invalid_body_interaction_job", message)
