extends RefCounted
class_name PhysicalInteractionPolicy

## Pure gate over trusted physics/loadout observations. Does not reserve hands or apply forces.
const MAX_FORCE_MILLINEWTONS: int = 1000000000
const ACTIONS: Array[String] = ["push_off", "grab", "pull_along", "move_world_object"]


static func assess(observation: Dictionary) -> ServiceResult:
	var fields := PackedStringArray(["schema_version", "action", "target_id", "pushable", "grippable", "movable", "contact_force_limit_millinewtons", "required_force_millinewtons", "participants"])
	if not ControlContractValidation.has_exact_fields(observation, fields) or not ControlContractValidation.is_integer(observation.get("schema_version"), 1, 1) or not ACTIONS.has(observation.get("action")) or not ControlContractValidation.is_id(observation.get("target_id")):
		return _failure("A complete versioned physical interaction observation is required.")
	for field in ["pushable", "grippable", "movable"]:
		if typeof(observation[field]) != TYPE_BOOL:
			return _failure("Target capabilities must be boolean.")
	for field in ["contact_force_limit_millinewtons", "required_force_millinewtons"]:
		if not ControlContractValidation.is_integer(observation[field], 0, MAX_FORCE_MILLINEWTONS):
			return _failure("Force observations must be bounded integer millinewtons.")
	if typeof(observation["participants"]) != TYPE_ARRAY or observation["participants"].is_empty() or observation["participants"].size() > 16:
		return _failure("One to sixteen distinct participants are required.")
	var bodies: Dictionary = {}
	var reservations: Array = []
	var force_budget: int = 0
	var reasons: Array[String] = []
	for raw in observation["participants"]:
		if typeof(raw) != TYPE_DICTIONARY or not ControlContractValidation.has_exact_fields(raw, PackedStringArray(["body_id", "free_hand_ids", "capable", "reachable", "contact", "force_budget_millinewtons"])) or not ControlContractValidation.is_id(raw.get("body_id")) or bodies.has(raw["body_id"]) or not ControlContractValidation.is_integer(raw.get("force_budget_millinewtons"), 0, MAX_FORCE_MILLINEWTONS):
			return _failure("Participants require unique bodies and bounded force budgets.")
		bodies[raw["body_id"]] = true
		for field in ["capable", "reachable", "contact"]:
			if typeof(raw[field]) != TYPE_BOOL:
				return _failure("Participant availability must be boolean.")
		if typeof(raw["free_hand_ids"]) != TYPE_ARRAY or raw["free_hand_ids"].size() > 8:
			return _failure("Available hands must be a bounded array.")
		var hands: Dictionary = {}
		for id in raw["free_hand_ids"]:
			if not ControlContractValidation.is_id(id) or hands.has(id):
				return _failure("Available hands must have distinct stable IDs per body.")
			hands[id] = true
		if not raw["capable"] or not raw["reachable"] or not raw["contact"] or hands.is_empty():
			reasons.append("participant_unavailable")
		force_budget += int(raw["force_budget_millinewtons"])
		reservations.append({"body_id": raw["body_id"], "hand_ids": raw["free_hand_ids"].duplicate()})
	var action: String = observation["action"]
	if action != "move_world_object" and bodies.size() != 1:
		return _failure("Traversal actions belong to one body; cooperative effort is for world manipulation.")
	if action == "push_off" and not observation["pushable"]:
		reasons.append("target_not_pushable")
	if action != "push_off" and not observation["grippable"]:
		reasons.append("target_not_grippable")
	if action == "move_world_object" and not observation["movable"]:
		reasons.append("target_anchored")
	if force_budget < int(observation["required_force_millinewtons"]):
		reasons.append("insufficient_force")
	if int(observation["contact_force_limit_millinewtons"]) < int(observation["required_force_millinewtons"]):
		reasons.append("contact_limit_exceeded")
	return ServiceResult.success({"schema_version": 1, "allowed": reasons.is_empty(), "action": action, "target_id": observation["target_id"],
		"force_budget_millinewtons": force_budget, "required_force_millinewtons": int(observation["required_force_millinewtons"]), "proposed_hand_reservations": reservations, "reasons": reasons})


static func _failure(message: String) -> ServiceResult:
	return ServiceResult.failure(&"invalid_physical_interaction", message)
