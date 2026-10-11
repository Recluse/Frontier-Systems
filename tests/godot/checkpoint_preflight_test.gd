extends SceneTree

class ReadOnlyFiles extends CheckpointFileIO:
	var mutations: int = 0
	func ensure_directory(_path: String) -> ServiceResult:
		return _mutation()
	func write_text(_path: String, _text: String) -> ServiceResult:
		return _mutation()
	func remove_file(_path: String) -> ServiceResult:
		return _mutation()
	func promote(_source: String, _destination: String) -> ServiceResult:
		return _mutation()
	func _mutation() -> ServiceResult:
		mutations += 1
		return ServiceResult.failure(&"unexpected_write", "PRIVATE mutation sentinel")

class ChangedReadFiles extends ReadOnlyFiles:
	var backup_reads: int = 0
	var replacement: String
	func read_text(path: String, max_bytes: int) -> ServiceResult:
		if path.ends_with("backup-0.json"):
			backup_reads += 1
			if backup_reads == 2:
				return ServiceResult.success(replacement)
		return super.read_text(path, max_bytes)

var _failures: int = 0
var _base: String
var _files := CheckpointFileIO.new()

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_base = OS.get_user_data_dir().path_join("checkpoint-preflight-%d" % Time.get_ticks_usec())
	_check(_files.ensure_directory(_base).is_success, "create disposable fixture")
	var world := _world()
	_check(world.start_simulation().is_success, "advance fixture")
	await create_timer(0.08).timeout
	world.stop_simulation()
	var snapshot: String = world.capture_world_snapshot_json().value
	world.free()
	var source: String = _base.path_join("source")
	var selection: Dictionary = _seed(source, snapshot)
	_check(selection["tick_number"] > 0, "nonzero fixture tick")
	var descriptor: String = _base.path_join("selected.json")
	_check(_files.write_text(descriptor, JSON.stringify(selection)).is_success, "explicit descriptor")
	# Capture every source file as raw bytes, including unknown files/staging evidence.
	_check(_files.write_text(source.path_join("operator-note"), "PRIVATE\r\nunchanged").is_success, "unknown evidence")
	_check(_files.write_text(source.path_join("checkpoint-history/archive.tmp"), "uncommitted").is_success, "staging evidence")
	var before: Dictionary = _tree_bytes(source)
	var readonly := ReadOnlyFiles.new()
	var result: Dictionary = _preflight(source, descriptor, readonly)
	_check(result["exit_status"] == 0 and result["action"] == "preflight" and result["source_sequence"] == 1 and result["tick_number"] == selection["tick_number"], "valid nonzero selection passes")
	_check(not result.has("sequence") and not JSON.stringify(result).contains("snapshot_json") and result["message"].contains("no cross-process lock"), "metadata only; no durability/lock claim")
	_check(_tree_bytes(source) == before, "successful preflight preserves exact source bytes and names")
	# Same selection after replacement must fail, with no substitution.
	var backup: String = source.path_join("checkpoint-history/backup-0.json")
	var original: String = _files.read_text(backup, LocalWorldSaveStore.MAX_BYTES).value
	var changed: Dictionary = JSON.parse_string(original)
	changed["sequence"] = 2
	_check(_files.write_text(backup, JSON.stringify(changed)).is_success, "replace listed selection")
	_assert_rejected_preserved(source, descriptor, readonly, "backup_selection")
	_check(_files.write_text(backup, "PRIVATE corrupt").is_success, "corrupt selected backup")
	_assert_rejected_preserved(source, descriptor, readonly, "backup_selection")
	_check(_files.remove_file(backup).is_success, "remove selected backup")
	_assert_rejected_preserved(source, descriptor, readonly, "backup_selection")
	_check(_files.write_text(backup, original).is_success, "restore fixture")
	var race := ChangedReadFiles.new()
	race.replacement = JSON.stringify(changed)
	_assert_rejected_preserved(source, descriptor, race, "backup_selection")
	_check(race.backup_reads == 2, "selection revalidated after scan")
	for kind in ["identity", "domain", "cross-system"]:
		var invalid: Dictionary = JSON.parse_string(snapshot)
		if kind == "identity":
			invalid["world_id"] = "world.other"
		elif kind == "domain":
			invalid["systems"]["health"]["timebase_hz"] = 0
		else:
			invalid["systems"]["health"]["entries"] = []
		var invalid_source: String = _base.path_join(kind)
		var selected: Dictionary = _seed(invalid_source, JSON.stringify(invalid))
		_check(_files.write_text(descriptor, JSON.stringify(selected)).is_success, "domain descriptor")
		_assert_rejected_preserved(invalid_source, descriptor, readonly, "world_snapshot_identity_mismatch" if kind == "identity" else ("invalid_health_links" if kind == "cross-system" else ""))
	_check(_files.write_text(descriptor, JSON.stringify(selection)).is_success, "restore descriptor")
	for state in ["running", "stopped", "configured"]:
		world = _world()
		var adapter := WorldPersistenceAdapter.new()
		root.add_child(adapter)
		adapter.set_process(false)
		if state == "configured":
			_check(adapter.configure(world, _base.path_join("unused")).is_success, "configure adapter without writes")
		else:
			_check(world.start_simulation().is_success, "nonfresh fixture")
			if state == "stopped":
				world.stop_simulation()
		result = CheckpointOperator.run(_args(source, descriptor), world, adapter, readonly)
		_check(result["exit_status"] == 4, "reject nonfresh " + state)
		adapter.free()
		world.free()
	for text in ["PRIVATE parser input", "x".repeat(4097)]:
		_check(_files.write_text(descriptor, text).is_success, "invalid descriptor fixture")
		result = _preflight(source, descriptor, readonly)
		_check(result["exit_status"] == 3 and not JSON.stringify(result).contains("PRIVATE"), "bounded safe descriptor failure")
	for args in [["preflight"], ["preflight", "--source", source], ["preflight", "--source", source, "--descriptor", descriptor, "--destination", _base.path_join("forbidden")], ["preflight", "--source", source, "--descriptor", "relative"], ["preflight", "--source", source, "--descriptor", descriptor, "--descriptor", descriptor]]:
		_check(CheckpointOperator.run(PackedStringArray(args))["exit_status"] == 2, "strict preflight options")
	_check(readonly.mutations == 0 and race.mutations == 0 and not _files.exists(_base.path_join("forbidden")) and not _files.exists(_base.path_join("unused")), "no mutating I/O or destination")
	_check(_tree_bytes(source) == before, "all preflight outcomes preserve original source bytes")
	_cleanup(_base)
	if _failures == 0:
		print("CHECKPOINT PREFLIGHT: explicit bounded descriptors, nonzero tick, identity/domain/cross-system rejection, changed/corrupt/missing/racing selections, read-only I/O and byte-for-byte preservation passed.")
	quit(0 if _failures == 0 else 1)

func _world() -> WorldRuntime:
	var world := WorldRuntime.new()
	world.resource_carriers_enabled = true
	root.add_child(world)
	world.set_process(false)
	return world

func _seed(source: String, snapshot: String) -> Dictionary:
	_check(LocalWorldSaveStore.write_checkpoint(source, 1, snapshot).is_success, "seed codec-valid active fixture")
	_check(CheckpointBackupHistory.archive_committed(source, 1, snapshot, CheckpointHistoryPolicy.new()).is_success, "archive fixture")
	return CheckpointBackupHistory.list_candidates(source).value["candidates"][0]

func _args(source: String, descriptor: String) -> PackedStringArray:
	return PackedStringArray(["preflight", "--source", source, "--descriptor", descriptor])

func _preflight(source: String, descriptor: String, files: CheckpointFileIO) -> Dictionary:
	var world := _world()
	var adapter := WorldPersistenceAdapter.new()
	root.add_child(adapter)
	adapter.set_process(false)
	var result: Dictionary = CheckpointOperator.run(_args(source, descriptor), world, adapter, files)
	_check(not world.profiling_snapshot()["simulation_running"] and adapter.status()["saved_tick"] == -1 and adapter.request_checkpoint().error_code == &"checkpoint_busy", "preflight never runs simulation/configures storage/acknowledges durability")
	adapter.free()
	world.free()
	return result

func _assert_rejected_preserved(source: String, descriptor: String, files: CheckpointFileIO, code: String) -> void:
	var before: Dictionary = _tree_bytes(source)
	var result: Dictionary = _preflight(source, descriptor, files)
	_check(result["exit_status"] == 4 and (code.is_empty() or result["error_code"] == code) and not JSON.stringify(result).contains("PRIVATE"), "selection/domain rejection: " + code + " " + JSON.stringify(result))
	_check(_tree_bytes(source) == before, "rejected selection preserves raw bytes")

func _tree_bytes(directory: String) -> Dictionary:
	var result: Dictionary = {}
	var dir := DirAccess.open(directory)
	for file in dir.get_files():
		result[file] = FileAccess.get_file_as_bytes(directory.path_join(file))
	for child in dir.get_directories():
		result[child] = _tree_bytes(directory.path_join(child))
	return result

func _cleanup(directory: String) -> void:
	var dir := DirAccess.open(directory)
	for file in dir.get_files():
		_check(DirAccess.remove_absolute(directory.path_join(file)) == OK, "remove fixture file")
	for child in dir.get_directories():
		_cleanup(directory.path_join(child))
	_check(DirAccess.remove_absolute(directory) == OK, "remove fixture directory")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
