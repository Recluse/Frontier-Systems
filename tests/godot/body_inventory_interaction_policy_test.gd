extends SceneTree

var _failures: int = 0


func _initialize() -> void:
	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/inventory/body-interactions.default.v1.json"))
	var parsed: ServiceResult = BodyInventoryInteractionPolicy.from_record(record)
	_check(parsed.is_success, "default interaction policy must validate")
	if not parsed.is_success:
		quit(1)
		return
	var policy: BodyInventoryInteractionPolicy = parsed.value
	var observed := {"distance_millimetres": 1500, "actor_can_manipulate": true, "target_available": true,
		"target_resisting": false, "target_moved": false, "path_accessible": true}
	var original: Dictionary = observed.duplicate(true)
	for action in BodyInventoryInteractionPolicy.ACTIONS:
		var assessed: ServiceResult = policy.assess(action, observed)
		_check(assessed.is_success and assessed.value["duration_ticks"] == int(record["duration_ticks"][action]), "passive reachable target must allow each timed attempt")
	_check(observed == original, "assessment must not change target observations")
	for field in ["target_resisting", "target_moved"]:
		var changed: Dictionary = observed.duplicate(true)
		changed[field] = true
		_check(not policy.assess("take", changed).is_success, "target action must interrupt: " + field)
	for field in ["actor_can_manipulate", "target_available", "path_accessible"]:
		var changed: Dictionary = observed.duplicate(true)
		changed[field] = false
		_check(not policy.assess("search", changed).is_success, "inaction must not bypass physical precondition: " + field)
	var changed: Dictionary = observed.duplicate(true)
	changed["distance_millimetres"] = 1501
	_check(not policy.assess("insert", changed).is_success, "out-of-reach insertion must reject")
	changed["distance_millimetres"] = -1
	_check(not policy.assess("insert", changed).is_success, "negative distance must reject")
	changed["distance_millimetres"] = 1.5
	_check(not policy.assess("insert", changed).is_success, "fractional millimetres must reject")
	changed = observed.duplicate(true)
	changed["target_resisting"] = 0
	_check(not policy.assess("take", changed).is_success, "nonboolean target state must reject")
	_check(not policy.assess("execute-program", observed).is_success, "physical policy must not grant arbitrary item capabilities")
	var invalid: Dictionary = record.duplicate(true)
	invalid["duration_ticks"]["take"] = 0
	_check(not BodyInventoryInteractionPolicy.from_record(invalid).is_success, "instant actions must reject")
	invalid = record.duplicate(true)
	invalid["duration_ticks"]["extra"] = 1
	_check(not BodyInventoryInteractionPolicy.from_record(invalid).is_success, "unknown policy actions must reject")
	var detached: Dictionary = policy.to_record()
	detached["duration_ticks"]["take"] = 1
	_check(policy.assess("take", observed).value["duration_ticks"] == 180, "policy must preserve detached trusted durations")
	if _failures == 0:
		print("Other-body inventory interaction policy scenarios passed.")
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
