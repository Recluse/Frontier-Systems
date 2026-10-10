extends RefCounted
class_name BodyInventoryInteractionPolicy

## Timed physical access policy. Observations must be computed by the server.
## Passing this gate neither reveals contents nor transfers/equips an item.
const ACTIONS: Array[String] = ["search", "take", "insert", "equip", "unequip"]
var _record: Dictionary = {}


func to_record() -> Dictionary:
	return _record.duplicate(true)


func assess(action: String, observation: Dictionary) -> ServiceResult:
	var fields := PackedStringArray(["distance_millimetres", "actor_can_manipulate", "target_available", "target_resisting", "target_moved", "path_accessible"])
	if not ACTIONS.has(action) or not ControlContractValidation.has_exact_fields(observation, fields):
		return ServiceResult.failure(&"invalid_body_interaction", "A registered action and complete server observation are required.")
	if not ControlContractValidation.is_integer(observation["distance_millimetres"], 0, 9007199254740990):
		return ServiceResult.failure(&"invalid_body_interaction_distance", "Interaction distance must be an exact non-negative quantity.")
	for field in ["actor_can_manipulate", "target_available", "target_resisting", "target_moved", "path_accessible"]:
		if typeof(observation[field]) != TYPE_BOOL:
			return ServiceResult.failure(&"invalid_body_interaction_observation", "Interaction conditions must be boolean server observations.")
	if not observation["target_available"] or not observation["actor_can_manipulate"]:
		return ServiceResult.failure(&"body_interaction_unavailable", "The target or actor's manipulation capability is unavailable.")
	if observation["target_resisting"] or observation["target_moved"]:
		return ServiceResult.failure(&"body_interaction_interrupted", "Target resistance or deliberate movement interrupts this interaction.")
	if observation["distance_millimetres"] > _record["max_distance_millimetres"] or not observation["path_accessible"]:
		return ServiceResult.failure(&"body_interaction_inaccessible", "The target or selected container cannot be physically accessed.")
	return ServiceResult.success({"duration_ticks": int(_record["duration_ticks"][action]), "action": action})


static func from_record(record: Dictionary) -> ServiceResult:
	var fields := PackedStringArray(["schema_version", "definition_id", "revision", "max_distance_millimetres", "duration_ticks"])
	if not ControlContractValidation.has_exact_fields(record, fields) or not ControlContractValidation.is_integer(record.get("schema_version"), 1, 1) or not ControlContractValidation.is_id(record.get("definition_id")):
		return ServiceResult.failure(&"invalid_body_interaction_policy", "A complete versioned interaction policy is required.")
	if not ControlContractValidation.is_integer(record["revision"], 1, 9007199254740990) or not ControlContractValidation.is_integer(record["max_distance_millimetres"], 1, 5000) or typeof(record["duration_ticks"]) != TYPE_DICTIONARY:
		return ServiceResult.failure(&"invalid_body_interaction_policy_limits", "Interaction policy limits are invalid.")
	var durations: Dictionary = record["duration_ticks"]
	if not ControlContractValidation.has_exact_fields(durations, PackedStringArray(ACTIONS)):
		return ServiceResult.failure(&"invalid_body_interaction_actions", "Each registered action must declare a duration.")
	for action in ACTIONS:
		if not ControlContractValidation.is_integer(durations[action], 1, 3600):
			return ServiceResult.failure(&"invalid_body_interaction_duration", "Action durations must be bounded positive fixed ticks.")
	var policy := BodyInventoryInteractionPolicy.new()
	policy._record = record.duplicate(true)
	return ServiceResult.success(policy)
