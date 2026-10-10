extends RefCounted
class_name PushOffImpulsePlanner

## Normal-only centerline impulse foundation. The future physics owner commits both records.
const MAX_IMPULSE_MICRO_NS: int = 1000000000


static func plan(actor_record: Dictionary, target_record: Dictionary, contact: Dictionary, impulse_micro_ns: Array) -> ServiceResult:
	var actor: ServiceResult = LinearMotionState.from_record(actor_record)
	var target: ServiceResult = LinearMotionState.from_record(target_record)
	if not actor.is_success or not target.is_success:
		return _failure("Both participants require valid mass and momentum state.")
	if actor_record["body_id"] == target_record["body_id"] or actor_record["frame_id"] != target_record["frame_id"]:
		return _failure("Distinct participants must share a local reference frame.")
	if not ControlContractValidation.has_exact_fields(contact, PackedStringArray(["schema_version", "normal_permille", "duration_microseconds", "capability_observation"])) or not ControlContractValidation.is_integer(contact.get("schema_version"), 1, 1) or not LinearMotionState.vector_valid(contact.get("normal_permille"), 1000) or not ControlContractValidation.is_integer(contact.get("duration_microseconds"), 1, 1000000) or typeof(contact.get("capability_observation")) != TYPE_DICTIONARY or not LinearMotionState.vector_valid(impulse_micro_ns, MAX_IMPULSE_MICRO_NS):
		return _failure("A bounded contact normal, duration and requested impulse are required.")
	var normal: Array = contact["normal_permille"]
	var normal_squared: int = 0
	var impulse_squared: int = 0
	var dot: int = 0
	for index in range(3):
		normal_squared += int(normal[index]) * int(normal[index])
		impulse_squared += int(impulse_micro_ns[index]) * int(impulse_micro_ns[index])
		dot += int(normal[index]) * int(impulse_micro_ns[index])
	if normal_squared != 1000000 or dot <= 0:
		return _failure("A unit outward normal and positive push-off impulse are required.")
	for index in range(3):
		var next: int = (index + 1) % 3
		if int(impulse_micro_ns[index]) * int(normal[next]) != int(impulse_micro_ns[next]) * int(normal[index]):
			return _failure("This prototype supports normal impulses without tangential friction or torque.")
	# Integer ceil norm: correct any floating sqrt rounding with exact bounded squares.
	var magnitude: int = int(sqrt(float(impulse_squared)))
	while magnitude * magnitude < impulse_squared:
		magnitude += 1
	while (magnitude - 1) * (magnitude - 1) >= impulse_squared:
		magnitude -= 1
	var duration: int = int(contact["duration_microseconds"])
	var required_force: int = (magnitude * 1000 + duration - 1) / duration
	var observation: Dictionary = contact["capability_observation"].duplicate(true)
	var original: ServiceResult = PhysicalInteractionPolicy.assess(observation)
	if not original.is_success or observation["action"] != "push_off" or observation["target_id"] != target_record["body_id"] or observation["participants"][0]["body_id"] != actor_record["body_id"]:
		return _failure("Trusted push-off capability must identify the actual actor and contacted assembly.")
	observation["required_force_millinewtons"] = required_force
	var permitted: ServiceResult = PhysicalInteractionPolicy.assess(observation)
	if not permitted.is_success or not permitted.value["allowed"]:
		return _failure("Contact strength, available hand or body force cannot supply the requested impulse.")
	var actor_after: Dictionary = actor.value.to_record()
	var target_after: Dictionary = target.value.to_record()
	for record in [actor_after, target_after]:
		if record["state_revision"] >= LinearMotionState.MAX_EXACT_INTEGER:
			return _failure("Motion revisions are exhausted.")
		record["state_revision"] += 1
	for index in range(3):
		actor_after["linear_momentum_micro_ns"][index] += int(impulse_micro_ns[index])
		target_after["linear_momentum_micro_ns"][index] -= int(impulse_micro_ns[index])
	var checked_actor: ServiceResult = LinearMotionState.from_record(actor_after)
	var checked_target: ServiceResult = LinearMotionState.from_record(target_after)
	if not checked_actor.is_success or not checked_target.is_success:
		return _failure("Resulting momentum or speed exceeds prototype limits.")
	return ServiceResult.success({"schema_version": 1, "actor_before": actor.value.to_record(), "target_before": target.value.to_record(), "actor_after": actor_after, "target_after": target_after,
		"impulse_micro_ns": [int(impulse_micro_ns[0]), int(impulse_micro_ns[1]), int(impulse_micro_ns[2])], "required_force_millinewtons": required_force})


static func _failure(message: String) -> ServiceResult:
	return ServiceResult.failure(&"invalid_push_off_impulse", message)
