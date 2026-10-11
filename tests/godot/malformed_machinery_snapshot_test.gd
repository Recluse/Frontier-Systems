extends SceneTree
var failures: int = 0
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var world := WorldRuntime.new()
	root.add_child(world)
	var before: String = world.capture_world_snapshot_json().value
	for malformed in [null, 1, 1.5, true, "invalid", []]:
		var record: Dictionary = JSON.parse_string(before)
		record["systems"]["production"]["machinery"] = malformed
		var result: ServiceResult = world.restore_world_snapshot_json(JSON.stringify(record))
		check(result != null and not result.is_success, "malformed machinery returns a structured failure")
		check(world.capture_world_snapshot_json().value == before, "rejected restore preserves every live system")
	var legacy: Dictionary = JSON.parse_string(before)
	legacy["systems"]["production"]["schema_version"] = 5
	legacy["systems"]["production"].erase("machinery")
	legacy["systems"]["production"].erase("walls")
	check(world.restore_world_snapshot_json(JSON.stringify(legacy)).is_success, "pre-machinery snapshots retain their default migration")
	var migrated: Dictionary = JSON.parse_string(world.capture_world_snapshot_json().value)
	check(migrated["systems"]["production"]["machinery"] == JSON.parse_string(before)["systems"]["production"]["machinery"], "legacy snapshot restores the initial machinery record")
	check(world.restore_world_snapshot_json(before).is_success, "valid snapshot still restores after rejection")
	world.free()
	print("Malformed machinery snapshot: %d failures" % failures)
	quit(1 if failures else 0)
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
