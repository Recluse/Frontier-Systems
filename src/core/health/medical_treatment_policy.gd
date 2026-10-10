extends RefCounted
class_name MedicalTreatmentPolicy

## Pure paired plan over trusted body/contact/loadout observations. No I/O or commits.
static func plan(injuries: BodyInjuryState, supply: MedicalSupplyState, definition: MedicalTreatmentDefinition, request: Dictionary, observation: Dictionary) -> ServiceResult:
	if injuries == null or supply == null or definition == null:
		return _failure("Registered injury, supply and treatment components are required.")
	var request_fields := PackedStringArray(["schema_version", "request_id", "target_body_id", "supply_id", "part_id", "expected_injury_revision", "expected_supply_revision"])
	if not ControlContractValidation.has_exact_fields(request, request_fields) or not ControlContractValidation.is_integer(request.get("schema_version"), 1, 1):
		return _failure("An exact versioned treatment intent is required.")
	for field in ["request_id", "target_body_id", "supply_id", "part_id"]:
		if not ControlContractValidation.is_id(request[field]):
			return _failure("Treatment intent identities must be bounded stable IDs.")
	for field in ["expected_injury_revision", "expected_supply_revision"]:
		if not ControlContractValidation.is_integer(request[field], 0, ConsciousnessState.MAX_INTEGER):
			return _failure("Treatment requires bounded expected revisions.")
	var observation_fields := PackedStringArray(["schema_version", "actor_body_id", "target_body_id", "supply_id", "tick_number", "actor_can_act", "manipulator_available", "reachable", "target_accessible", "target_resisting", "supply_accessible"])
	if not ControlContractValidation.has_exact_fields(observation, observation_fields) or not ControlContractValidation.is_integer(observation.get("schema_version"), 1, 1) or not ControlContractValidation.is_integer(observation.get("tick_number"), 1, ConsciousnessState.MAX_INTEGER):
		return _failure("A fresh trusted treatment observation is required.")
	for field in ["actor_body_id", "target_body_id", "supply_id"]:
		if not ControlContractValidation.is_id(observation[field]):
			return _failure("Trusted observation identities must be stable IDs.")
	for field in ["actor_can_act", "manipulator_available", "reachable", "target_accessible", "target_resisting", "supply_accessible"]:
		if typeof(observation[field]) != TYPE_BOOL:
			return _failure("Trusted capabilities must be boolean.")
	if not observation["actor_can_act"] or not observation["manipulator_available"] or not observation["reachable"] or not observation["target_accessible"] or observation["target_resisting"] or not observation["supply_accessible"]:
		return _failure("Treatment requires a capable actor, an available manipulator and accessible non-resisting target and supply.")
	var injury_record: Dictionary = injuries.to_record()
	var supply_record: Dictionary = supply.to_record()
	var treatment: Dictionary = definition.to_record()
	if injury_record.is_empty() or supply_record.is_empty() or treatment.is_empty():
		return _failure("Uninitialized treatment components cannot be planned.")
	if request["target_body_id"] != injury_record["body_id"] or request["target_body_id"] != observation["target_body_id"] or request["supply_id"] != supply_record["supply_id"] or request["supply_id"] != observation["supply_id"] or supply_record["definition_id"] != treatment["definition_id"] or not BodyInjuryState.PARTS.has(request["part_id"]):
		return _failure("The intent must match registered body, supply, definition and anatomy.")
	if int(request["expected_injury_revision"]) != int(injury_record["state_revision"]):
		return _failure("The injury revision is stale.")
	var tick: int = int(observation["tick_number"])
	var healing: ServiceResult = injuries.plan_change("heal", request["part_id"], treatment["injury_kind"], int(treatment["healing_permille"]), tick)
	if not healing.is_success:
		return healing
	if int(healing.value["applied_amount_permille"]) == 0:
		return _failure("No matching injury remains; do not consume a supply.")
	var consumption: ServiceResult = supply.plan_consumption(int(request["expected_supply_revision"]), int(treatment["charge_cost"]), tick)
	if not consumption.is_success:
		return consumption
	return ServiceResult.success({"schema_version": 1, "request_id": request["request_id"], "actor_body_id": observation["actor_body_id"],
		"tick_number": tick, "definition_revision": treatment["revision"], "injury_change": healing.value, "supply_change": consumption.value})


static func _failure(message: String) -> ServiceResult:
	return ServiceResult.failure(&"medical_treatment_denied", message)
