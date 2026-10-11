extends SceneTree

class SeedFaultFiles extends CheckpointFileIO:
	func write_text(path: String, text: String) -> ServiceResult:
		if path.ends_with("world-b.json.tmp"):
			return ServiceResult.failure(&"save_write", "private injected text must not escape")
		return super.write_text(path, text)

var _failures: int = 0
var _base: String
var _files := CheckpointFileIO.new()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_options()
	_base = OS.get_user_data_dir().path_join("checkpoint-operator-test-%d" % Time.get_ticks_usec())
	_check(_files.ensure_directory(_base).is_success, "create disposable storage")
	var source: String = _base.path_join("source")
	var descriptor: String = _base.path_join("selected.json")
	var world := WorldRuntime.new()
	world.resource_carriers_enabled = true
	root.add_child(world)
	_check(world.start_simulation().is_success, "advance fixture world")
	await create_timer(0.06).timeout
	world.stop_simulation()
	var snapshot: String = world.capture_world_snapshot_json().value
	_check(LocalWorldSaveStore.write_checkpoint(source, 1, snapshot).is_success, "seed disposable active")
	_check(CheckpointBackupHistory.archive_committed(source, 1, snapshot, CheckpointHistoryPolicy.new()).is_success, "seed disposable backup")
	world.free()
	var listing: Dictionary = CheckpointOperator.run(_list(source))
	_check(listing["exit_status"] == 0 and listing["candidates"].size() == 1 and listing["rejected"].is_empty(), "metadata listing succeeds")
	var selected: Dictionary = listing["candidates"][0]
	_check(selected["tick_number"] > 0 and not selected.has("snapshot_json"), "only bounded metadata escapes")
	_check(not JSON.stringify(listing).contains("snapshot_json") and not JSON.stringify(listing).contains("systems"), "listing never includes snapshots")
	_check(_files.write_text(descriptor, JSON.stringify(selected)).is_success, "explicit exact selection file")
	var backup: String = source.path_join("checkpoint-history/backup-0.json")
	var active: String = source.path_join("world-b.json")
	var original_backup: String = _files.read_text(backup, LocalWorldSaveStore.MAX_BYTES).value
	var original_active: String = _files.read_text(active, LocalWorldSaveStore.MAX_BYTES).value
	_check(_files.write_text(source.path_join("checkpoint-history/backup-1.json"), "SECRET invalid snapshot").is_success, "corrupt disposable backup")
	listing = CheckpointOperator.run(_list(source))
	_check(listing["exit_status"] == 3 and listing["candidates"].size() == 1 and listing["rejected"].size() == 1 and not JSON.stringify(listing).contains("SECRET"), "rejection reason and nonzero exit without raw input")
	_check(_files.remove_file(source.path_join("checkpoint-history/backup-1.json")).is_success, "remove disposable rejected fixture")
	var changed: Dictionary = JSON.parse_string(original_backup)
	changed["sequence"] = 2
	_check(_files.write_text(backup, JSON.stringify(changed)).is_success, "replace selected metadata between list and recover")
	var result: Dictionary = _recover(source, descriptor, _base.path_join("changed"))
	_check(result["exit_status"] == 4 and result["error_code"] == "backup_selection" and not _files.exists(_base.path_join("changed")), "changed selection fails without fallback or write")
	_check(_files.write_text(backup, original_backup).is_success, "restore disposable selection")
	result = _recover(source, descriptor, source.path_join("nested"))
	_check(result["exit_status"] == 4 and result["error_code"] == "backup_destination" and not _files.exists(source.path_join("nested")), "existing owner source-tree guard")
	result = _recover(source, descriptor, source)
	_check(result["exit_status"] == 4 and result["error_code"] == "backup_destination", "existing destination preserved")
	for state in ["running", "stopped", "configured", "identity"]:
		world = WorldRuntime.new()
		world.resource_carriers_enabled = true
		if state == "identity":
			world.world_id = &"world.other"
		root.add_child(world)
		var adapter := WorldPersistenceAdapter.new()
		root.add_child(adapter)
		adapter.set_process(false)
		if state in ["running", "stopped"]:
			_check(world.start_simulation().is_success, "start rejection world")
			if state == "stopped":
				world.stop_simulation()
		if state == "configured":
			_check(adapter.configure(world, _base.path_join("configured")).is_success, "configure rejection adapter")
		result = CheckpointOperator.run(_args(source, descriptor, _base.path_join(state)), world, adapter)
		_check(result["exit_status"] == 4 and not _files.exists(_base.path_join(state)), "reject nonfresh world/adapter or identity: " + state)
		adapter.free()
		world.free()
	_check(_files.write_text(descriptor, "SECRET not json").is_success, "invalid descriptor")
	result = _recover(source, descriptor, _base.path_join("invalid"))
	_check(result["exit_status"] == 3 and result["error_code"] == "backup_selection" and not JSON.stringify(result).contains("SECRET"), "parser diagnostics conceal input")
	_check(_files.write_text(descriptor, "x".repeat(CheckpointOperator.MAX_DESCRIPTOR_BYTES + 1)).is_success, "oversize descriptor fixture")
	result = _recover(source, descriptor, _base.path_join("oversize"))
	_check(result["exit_status"] == 3 and result["error_code"] == "save_bounds", "descriptor reads bounded")
	_check(_files.write_text(descriptor, JSON.stringify(selected)).is_success, "restore descriptor")
	var tampered: Dictionary = selected.duplicate()
	tampered["bytes"] = float(selected["bytes"]) + 0.5
	_check(_files.write_text(descriptor, JSON.stringify(tampered)).is_success, "fractional descriptor")
	result = _recover(source, descriptor, _base.path_join("fractional"))
	_check(result["exit_status"] == 4 and result["error_code"] == "backup_selection", "fractional metadata cannot normalize into selection")
	tampered = selected.duplicate()
	tampered["extra"] = "SECRET"
	_check(_files.write_text(descriptor, JSON.stringify(tampered)).is_success, "unexpected descriptor field")
	result = _recover(source, descriptor, _base.path_join("extra-field"))
	_check(result["exit_status"] == 4 and result["error_code"] == "backup_selection" and not JSON.stringify(result).contains("SECRET"), "full exact descriptor shape enforced by owner")
	_check(_files.write_text(descriptor, JSON.stringify(selected)).is_success, "restore exact descriptor")
	result = _recover(source, descriptor, _base.path_join("failed-seed"), SeedFaultFiles.new())
	_check(result["exit_status"] == 4 and result["error_code"] == "save_write" and not JSON.stringify(result).contains("private injected"), "seed failure exit and safe fixed diagnostics: " + JSON.stringify(result))
	var destination: String = _base.path_join("recovered")
	result = _recover(source, descriptor, destination)
	_check(result["exit_status"] == 0 and result["source_sequence"] == 1 and result["sequence"] == 1 and result["tick_number"] == selected["tick_number"], "explicit recovery retains tick and resets destination sequence: " + JSON.stringify(result))
	var persisted: ServiceResult = LocalWorldSaveStore.read_latest(destination)
	_check(persisted.is_success and not persisted.value.is_empty() and persisted.value["snapshot_json"] == snapshot, "domain-valid selected snapshot seeded")
	_check(_files.read_text(active, LocalWorldSaveStore.MAX_BYTES).value == original_active and _files.read_text(backup, LocalWorldSaveStore.MAX_BYTES).value == original_backup, "all operator outcomes preserve source active and backup bytes")
	_cleanup(_base)
	_check(not _files.exists(_base), "disposable storage removed")
	if _failures == 0:
		print("CHECKPOINT OPERATOR: strict opt-out/options, metadata-only inspection, stale selections, stopped/fresh guards, source preservation, bounded descriptors and failure diagnostics passed.")
	quit(0 if _failures == 0 else 1)


func _test_options() -> void:
	var disabled: ServiceResult = CheckpointOperator.history_from_settings("", "")
	_check(disabled.is_success and disabled.value == null, "default history disabled")
	for pair in [["1", "1"], ["8", "67108864"], ["3", "33554432"]]:
		var policy: ServiceResult = CheckpointOperator.history_from_settings(pair[0], pair[1])
		_check(policy.is_success and policy.value.validate().is_success, "valid strict configured bounds")
	for pair in [["", "1"], ["1", ""], ["0", "1"], ["9", "1"], ["1", "0"], ["1", "67108865"], ["1.0", "1"], ["01", "1"], [" 1", "1"], ["+1", "1"], ["true", "1"], ["1", "999999999999999999999999999999"]]:
		_check(CheckpointOperator.history_from_settings(pair[0], pair[1]).error_code == &"backup_configuration", "invalid configured bounds reject")
	for args in [[], ["unknown"], ["list"], ["list", "--source", "relative"], ["list", "--source", "/tmp", "--source", "/tmp"], ["recover", "--source", "/tmp"], ["list", "--secret", "SECRET"], ["list", "--source", "/" + "x".repeat(4096)]]:
		var report: Dictionary = CheckpointOperator.run(PackedStringArray(args))
		_check(report["exit_status"] == 2 and report["error_code"] == "operator_options" and not JSON.stringify(report).contains("SECRET"), "strict CLI usage rejects with safe diagnostic")
	var failed := ServiceResult.failure(&"save_write", "SECRET")
	_check(not CheckpointOperator.checkpoint_diagnostic(1, failed, {}).contains("SECRET"), "active diagnostic excludes untrusted text")
	var diagnostic: String = CheckpointOperator.checkpoint_diagnostic(12, ServiceResult.success(), {"enabled": true, "error_code": "backup_bounds", "sequence": 0})
	_check(diagnostic.contains("committed at tick 12") and diagnostic.contains("history failed: backup_bounds"), "active success and separate backup failure readable")
	_check(CheckpointOperator.checkpoint_diagnostic(12, ServiceResult.success(), {"enabled": false}).contains("disabled"), "opt-out diagnostic readable")
	_check(CheckpointOperator.checkpoint_diagnostic(12, ServiceResult.success(), {"enabled": true, "error_code": "", "sequence": 7}).contains("acknowledged sequence 7"), "backup success diagnostic readable")


func _list(source: String) -> PackedStringArray:
	return PackedStringArray(["list", "--source", source])


func _args(source: String, descriptor: String, destination: String) -> PackedStringArray:
	return PackedStringArray(["recover", "--source", source, "--descriptor", descriptor, "--destination", destination])


func _recover(source: String, descriptor: String, destination: String, files: CheckpointFileIO = null) -> Dictionary:
	var world := WorldRuntime.new()
	world.resource_carriers_enabled = true
	root.add_child(world)
	var adapter := WorldPersistenceAdapter.new()
	root.add_child(adapter)
	adapter.set_process(false)
	var result: Dictionary = CheckpointOperator.run(_args(source, descriptor, destination), world, adapter, files)
	_check(not world.profiling_snapshot()["simulation_running"], "operator never starts simulation")
	adapter.free()
	world.free()
	return result


func _cleanup(directory: String) -> void:
	var dir := DirAccess.open(directory)
	if dir == null:
		return
	for file in dir.get_files():
		_check(DirAccess.remove_absolute(directory.path_join(file)) == OK, "remove disposable file")
	for child in dir.get_directories():
		_cleanup(directory.path_join(child))
	_check(DirAccess.remove_absolute(directory) == OK, "remove disposable directory")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)