extends SceneTree

class HistoryFaultFiles extends CheckpointFileIO:
	var fault: String = ""
	var history_writes: int = 0

	func ensure_directory(path: String) -> ServiceResult:
		if fault == "directory" and path.ends_with("checkpoint-history"):
			return ServiceResult.failure(&"save_directory", "Injected backup directory failure.")
		return super.ensure_directory(path)

	func write_text(path: String, text: String) -> ServiceResult:
		if path.ends_with("archive.tmp"):
			history_writes += 1
			if fault == "open":
				return ServiceResult.failure(&"save_open", "Injected backup open failure.")
			if fault == "flush":
				super.write_text(path, text.substr(0, 20))
				return ServiceResult.failure(&"save_write", "Injected interrupted archive/flush.")
			if fault == "short" or fault == "cleanup":
				return super.write_text(path, text.substr(0, 20))
		return super.write_text(path, text)

	func read_text(path: String, max_bytes: int) -> ServiceResult:
		if fault == "read" and path.ends_with("archive.tmp") or fault == "unreadable" and path.ends_with("backup-0.json"):
			return ServiceResult.failure(&"save_read", "Injected backup read failure.")
		return super.read_text(path, max_bytes)

	func promote(source: String, destination: String) -> ServiceResult:
		if fault == "promote" and source.ends_with("archive.tmp"):
			return ServiceResult.failure(&"save_promote", "Injected interrupted archive promotion.")
		return super.promote(source, destination)

	func remove_file(path: String) -> ServiceResult:
		if fault == "prune" and path.get_file().begins_with("backup-") or fault == "cleanup" and path.ends_with("archive.tmp"):
			return ServiceResult.failure(&"save_cleanup", "Injected interrupted backup removal.")
		return super.remove_file(path)


class SeedFaultFiles extends CheckpointFileIO:
	func write_text(path: String, text: String) -> ServiceResult:
		if path.ends_with("world-b.json.tmp"):
			return ServiceResult.failure(&"save_write", "Injected recovery seed interruption.")
		return super.write_text(path, text)


class GatedHistoryFiles extends HistoryFaultFiles:
	var entered := Semaphore.new()
	var release := Semaphore.new()
	var worker_id: int = -1

	func write_text(path: String, text: String) -> ServiceResult:
		if path.ends_with("archive.tmp"):
			worker_id = OS.get_thread_caller_id()
			entered.post()
			release.wait()
		return super.write_text(path, text)


var _failures: int = 0
var _base: String
var _directories: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_base = OS.get_user_data_dir().path_join("checkpoint-history-test-%d" % Time.get_ticks_usec())
	_test_retention()
	_test_failures()
	_test_selection()
	await _test_adapter()
	await _test_recovery()
	for directory in _directories:
		_cleanup(directory)
	DirAccess.remove_absolute(_base)
	_check(not DirAccess.dir_exists_absolute(_base), "disposable storage is cleaned")
	if _failures == 0:
		print("CHECKPOINT HISTORY: opt-in retention, verified archives, bounded interrupted pruning, distinct backup errors, worker isolation and explicit startup recovery passed.")
	quit(0 if _failures == 0 else 1)


func _fixture(name: String) -> String:
	var directory: String = _base.path_join(name)
	_directories.append(directory)
	_check(DirAccess.make_dir_recursive_absolute(directory) == OK, "create isolated fixture " + name)
	return directory


func _snapshot(tick: int, world: StringName = &"world.history") -> String:
	return WorldSnapshot.new(world, &"region.history", tick, {"fixture": {"marker": tick}}).to_json()


func _backup_path(directory: String, slot: int = 0) -> String:
	return directory.path_join("checkpoint-history/backup-%d.json" % slot)


func _listed(directory: String) -> Array[Dictionary]:
	var result: ServiceResult = CheckpointBackupHistory.list_candidates(directory)
	_check(result.is_success, "bounded metadata listing succeeds")
	return result.value["candidates"]


func _write_archive(directory: String, sequence: int, policy: CheckpointHistoryPolicy, io: CheckpointFileIO = null) -> ServiceResult:
	var snapshot: String = _snapshot(sequence)
	_check(LocalWorldSaveStore.write_checkpoint(directory, sequence, snapshot, io).is_success, "active checkpoint commits independently")
	return CheckpointBackupHistory.archive_committed(directory, sequence, snapshot, policy, io)


func _raw(path: String, text: String) -> void:
	_check(CheckpointFileIO.new().write_text(path, text).is_success, "write disposable phase-boundary fixture")


func _test_retention() -> void:
	_check(CheckpointHistoryPolicy.new(0).validate().error_code == &"backup_configuration", "history count zero rejects; null is opt-out")
	_check(not CheckpointHistoryPolicy.new(9).validate().is_success and not CheckpointHistoryPolicy.new(1, 0).validate().is_success and not CheckpointHistoryPolicy.new(1, CheckpointHistoryPolicy.MAX_RETAINED_BYTES + 1).validate().is_success, "retention count and bytes are bounded")
	var directory: String = _fixture("retention")
	var policy := CheckpointHistoryPolicy.new(2, 4096)
	for sequence in range(1, 13):
		_check(_write_archive(directory, sequence, policy).is_success, "archive verified committed envelope")
		var candidates: Array[Dictionary] = _listed(directory)
		_check(candidates.size() == mini(sequence, 2) and candidates[0]["sequence"] == sequence and candidates[0]["tick_number"] == sequence and candidates[0]["world_id"] == "world.history", "retain latest bounded sequence/tick/identity")
	var active: ServiceResult = LocalWorldSaveStore.read_latest(directory)
	var expected: String = FileAccess.get_file_as_string(directory.path_join("world-a.json"))
	var selected: Dictionary = _listed(directory)[0]
	_check(FileAccess.get_file_as_string(_backup_path(directory, selected["slot"])) == expected, "archive preserves exact v1 envelope bytes")
	_check(CheckpointBackupHistory.archive_committed(directory, 12, _snapshot(12), policy).is_success and _listed(directory).size() == 2, "identical archive retry is idempotent")
	_check(CheckpointBackupHistory.archive_committed(directory, 13, _snapshot(13), policy).error_code == &"backup_source", "uncommitted sequence cannot be archived")
	_check(CheckpointBackupHistory.archive_committed(directory, 12, _snapshot(99), policy).error_code == &"backup_source", "changed detached data cannot archive an acknowledged checkpoint")
	_check(LocalWorldSaveStore.read_latest(directory).value == active.value, "all history operations preserve active slots")
	var byte_dir: String = _fixture("byte-retention")
	_check(_write_archive(byte_dir, 1, policy).is_success, "seed byte retention")
	var bytes: int = _listed(byte_dir)[0]["bytes"]
	var byte_policy := CheckpointHistoryPolicy.new(8, bytes + 32)
	_check(_write_archive(byte_dir, 2, byte_policy).is_success and _listed(byte_dir).size() == 1, "aggregate bytes prune before count cap")
	var tiny := CheckpointHistoryPolicy.new(1, 1)
	_check(_write_archive(byte_dir, 3, tiny).error_code == &"backup_bounds" and _listed(byte_dir)[0]["sequence"] == 2, "oversized new backup preserves last recovery entry and acknowledges active sequence")
	_check(LocalWorldSaveStore.read_latest(byte_dir).value["sequence"] == 3, "backup bounds never invalidate active commit")
	var identity: String = _fixture("identity")
	_check(_write_archive(identity, 1, policy).is_success, "seed identity")
	_check(LocalWorldSaveStore.write_checkpoint(identity, 2, _snapshot(2, &"other.world")).is_success, "active codec permits detached valid other identity")
	_check(CheckpointBackupHistory.archive_committed(identity, 2, _snapshot(2, &"other.world"), policy).error_code == &"backup_identity" and _listed(identity).size() == 1, "history cannot mix world identities")


func _test_failures() -> void:
	var policy := CheckpointHistoryPolicy.new(1, 4096)
	for fault in ["directory", "open", "flush", "short", "read", "promote", "cleanup", "prune"]:
		var directory: String = _fixture(fault)
		_check(_write_archive(directory, 1, policy).is_success, "seed last backup for fault " + fault)
		var files := HistoryFaultFiles.new()
		files.fault = fault
		var active_bytes: String = FileAccess.get_file_as_string(directory.path_join("world-b.json"))
		for sequence in range(2, 5):
			var result: ServiceResult = _write_archive(directory, sequence, policy, files)
			var expected: StringName = {"directory": &"backup_directory", "open": &"backup_write", "flush": &"backup_write", "short": &"backup_verify", "read": &"backup_verify", "promote": &"backup_promote", "cleanup": &"backup_cleanup", "prune": &"backup_prune"}[fault]
			_check(result.error_code == expected, "archive failure is distinct: " + fault)
			_check(LocalWorldSaveStore.read_latest(directory).value["sequence"] == sequence, "active commit survives repeated archive failure")
			var candidates: Array[Dictionary] = _listed(directory)
			_check(candidates.size() == (2 if fault == "prune" else 1), "repeated interruption cannot grow bounded backup storage")
			_check(candidates.back()["sequence"] == 1 and FileAccess.get_file_as_string(_backup_path(directory)) == active_bytes, "last recoverable backup survives archive/prune failure")
		_check(files.history_writes == (1 if fault == "prune" else (0 if fault == "directory" else 3)), "failed pre-prune stops new archive growth")
		files.fault = ""
		_check(CheckpointBackupHistory.archive_committed(directory, 4, _snapshot(4), policy, files).is_success and _listed(directory).size() == 1 and _listed(directory)[0]["sequence"] == 4, "restart/retry repairs staging or pruning with bounded retention")
	var maximum: String = _fixture("maximum-prune")
	var maximum_policy := CheckpointHistoryPolicy.new(8, 8192)
	for sequence in range(1, 9):
		_check(_write_archive(maximum, sequence, maximum_policy).is_success, "seed maximum entry retention")
	var blocked := HistoryFaultFiles.new()
	blocked.fault = "prune"
	for sequence in range(9, 12):
		_check(_write_archive(maximum, sequence, maximum_policy, blocked).error_code == &"backup_prune" and _listed(maximum).size() == 9, "maximum retention keeps only one bounded spare through repeated interrupted prune")
	blocked.fault = ""
	_check(CheckpointBackupHistory.archive_committed(maximum, 11, _snapshot(11), maximum_policy, blocked).is_success and _listed(maximum).size() == 8, "restart repairs full history ring before admitting new archive")
	var shrink: String = _fixture("shrink-last")
	var large_json: String = WorldSnapshot.new(&"world.history", &"region.history", 1, {"fixture": {"padding": "x".repeat(1000)}}).to_json()
	_check(LocalWorldSaveStore.write_checkpoint(shrink, 1, large_json).is_success and CheckpointBackupHistory.archive_committed(shrink, 1, large_json, policy).is_success, "seed backup larger than changed retention")
	var smaller := CheckpointHistoryPolicy.new(1, 512)
	_check(_write_archive(shrink, 2, smaller).error_code == &"backup_bounds" and _listed(shrink).size() == 1 and _listed(shrink)[0]["sequence"] == 1, "changed byte policy cannot delete last recoverable backup even for smaller new checkpoint")
	var interrupted: String = _fixture("phase-boundaries")
	_check(_write_archive(interrupted, 1, policy).is_success, "seed archive phase fixture")
	var envelope: String = FileAccess.get_file_as_string(_backup_path(interrupted))
	_raw(interrupted.path_join("checkpoint-history/archive.tmp"), envelope)
	_check(_listed(interrupted).size() == 1, "valid but unpromoted archive staging is ignored on restart")
	_raw(interrupted.path_join("checkpoint-history/archive.tmp"), "partial")
	_check(_listed(interrupted).size() == 1, "partial staging never becomes a recovery candidate")
	_raw(_backup_path(interrupted, 1), envelope.substr(0, 20))
	_check(_listed(interrupted).size() == 1 and CheckpointBackupHistory.list_candidates(interrupted).value["rejected"].size() == 1, "partial committed-name archive is rejected and reported")
	_check(_write_archive(interrupted, 2, policy).error_code == &"backup_scan", "archive preserves invalid evidence and valid backup")
	var unreadable := HistoryFaultFiles.new()
	unreadable.fault = "unreadable"
	_check(CheckpointBackupHistory.list_candidates(interrupted, unreadable).value["candidates"].is_empty(), "unreadable backups never become selectable")
	_raw(_backup_path(interrupted, 1), "x".repeat(LocalWorldSaveStore.MAX_BYTES + 1))
	_check(CheckpointBackupHistory.list_candidates(interrupted).value["rejected"][0]["code"] == "save_bounds", "oversized committed-name backup is byte-bounded")


func _test_selection() -> void:
	var directory: String = _fixture("selection")
	var policy := CheckpointHistoryPolicy.new(2, 4096)
	_check(_write_archive(directory, 1, policy).is_success and _write_archive(directory, 2, policy).is_success, "seed explicit selection")
	var selected: Dictionary = _listed(directory)[1].duplicate(true)
	var result: ServiceResult = CheckpointBackupHistory.select_candidate(directory, selected)
	_check(result.is_success and result.value["sequence"] == 1, "older history requires exact explicit selection")
	var tampered: Dictionary = selected.duplicate(true)
	tampered["tick_number"] = 99
	_check(CheckpointBackupHistory.select_candidate(directory, tampered).error_code == &"backup_selection", "tampered selector metadata rejects")
	tampered = selected.duplicate(true)
	tampered["slot"] = "../world-a"
	_check(CheckpointBackupHistory.select_candidate(directory, tampered).error_code == &"backup_selection", "selection is fixed slot metadata, never a supplied path")
	var bad_checksum: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_backup_path(directory, selected["slot"])))
	bad_checksum["sha256"] = "invalid"
	_raw(_backup_path(directory, selected["slot"]), JSON.stringify(bad_checksum))
	_check(CheckpointBackupHistory.select_candidate(directory, selected).error_code == &"backup_selection", "matching envelope identity with corrupt checksum is unselectable")
	_raw(_backup_path(directory, selected["slot"]), "corrupt")
	_check(CheckpointBackupHistory.select_candidate(directory, selected).error_code == &"backup_selection", "candidate corrupted since listing fails rather than select another backup")
	var newer: Dictionary = _listed(directory)[0]
	var envelope: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_backup_path(directory, newer["slot"])))
	envelope["sequence"] = 3
	_raw(_backup_path(directory, selected["slot"]), JSON.stringify(envelope))
	_check(CheckpointBackupHistory.select_candidate(directory, selected).error_code == &"backup_selection", "replaced slot cannot reuse stale selector")


func _wait(predicate: Callable) -> void:
	var deadline: int = Time.get_ticks_msec() + 3000
	var completed: bool = predicate.call()
	while not completed and Time.get_ticks_msec() < deadline:
		await process_frame
		completed = predicate.call()
	_check(completed, "bounded asynchronous wait completes")


func _test_adapter() -> void:
	var directory: String = _fixture("adapter")
	var world := WorldRuntime.new()
	root.add_child(world)
	var adapter := WorldPersistenceAdapter.new()
	root.add_child(adapter)
	var files := HistoryFaultFiles.new()
	files.fault = "flush"
	var policy := CheckpointHistoryPolicy.new(2)
	_check(adapter.configure(world, directory, files, policy).is_success, "enable detached worker history")
	policy.entries = 0
	var completions: Array[ServiceResult] = []
	adapter.checkpoint_completed.connect(func(_tick: int, result: ServiceResult) -> void: completions.append(result))
	_check(adapter.request_checkpoint().is_success, "queue checkpoint independently of backup")
	await _wait(func() -> bool: return not adapter.status()["busy"])
	_check(completions.size() == 1 and completions[0].is_success and adapter.status()["saved_tick"] == 0 and adapter.status()["last_error"].is_empty() and adapter.backup_status()["error_code"] == "backup_write", "backup failure distinctly reports without falsely failing active checkpoint")
	files.fault = ""
	_check(adapter.request_checkpoint().is_success, "later checkpoint retries opt-in history")
	await _wait(func() -> bool: return not adapter.status()["busy"])
	_check(adapter.backup_status()["sequence"] == 2 and adapter.backup_status()["last_error"].is_empty() and _listed(directory).size() == 1, "configured history is detached from caller mutation and clears backup error")
	adapter.free()
	world.free()
	var disabled: String = _fixture("disabled")
	world = WorldRuntime.new()
	root.add_child(world)
	adapter = WorldPersistenceAdapter.new()
	root.add_child(adapter)
	_check(adapter.configure(world, disabled).is_success and adapter.request_checkpoint().is_success, "default history remains disabled")
	await _wait(func() -> bool: return not adapter.status()["busy"])
	_check(not adapter.backup_status()["enabled"] and not DirAccess.dir_exists_absolute(disabled.path_join("checkpoint-history")), "default path creates no history storage")
	adapter.free()
	world.free()
	var gated: String = _fixture("gated")
	world = WorldRuntime.new()
	root.add_child(world)
	adapter = WorldPersistenceAdapter.new()
	root.add_child(adapter)
	var gate := GatedHistoryFiles.new()
	_check(adapter.configure(world, gated, gate, CheckpointHistoryPolicy.new()).is_success and world.start_simulation().is_success, "gated archive starts on worker")
	var request: ServiceResult = adapter.request_checkpoint()
	await _wait(func() -> bool: return gate.entered.try_wait())
	await create_timer(0.08).timeout
	_check(world.current_tick_number() > request.value["tick_number"] and adapter.status()["busy"] and LocalWorldSaveStore.read_latest(gated).value["sequence"] == 1, "blocked history preserves committed active checkpoint while ticks continue")
	gate.release.post()
	# Shutdown joins the worker outside ticks and consumes both separate outcomes.
	root.remove_child(adapter)
	_check(adapter.status()["saved_tick"] == request.value["tick_number"] and adapter.backup_status()["sequence"] == 1 and gate.worker_id != OS.get_thread_caller_id(), "shutdown joins detached history worker and records captured tick")
	adapter.free()
	world.free()


func _test_recovery() -> void:
	var source: String = _fixture("startup-source")
	var world := WorldRuntime.new()
	root.add_child(world)
	var snapshot: String = world.capture_world_snapshot_json().value
	_check(LocalWorldSaveStore.write_checkpoint(source, 1, snapshot).is_success and CheckpointBackupHistory.archive_committed(source, 1, snapshot, CheckpointHistoryPolicy.new()).is_success, "seed domain-valid startup history")
	_check(world.start_simulation().is_success, "advance domain checkpoint tick")
	await create_timer(0.06).timeout
	snapshot = world.capture_world_snapshot_json().value
	world.stop_simulation()
	_check(LocalWorldSaveStore.write_checkpoint(source, 2, snapshot).is_success and CheckpointBackupHistory.archive_committed(source, 2, snapshot, CheckpointHistoryPolicy.new()).is_success, "seed later domain-valid history")
	world.free()
	world = WorldRuntime.new()
	root.add_child(world)
	var selected: Dictionary = _listed(source)[0]
	_check(selected["tick_number"] > 0, "startup selection carries nonzero captured tick")
	_raw(source.path_join("world-a.json"), "corrupt active a")
	_raw(source.path_join("world-b.json"), "corrupt active")
	var automatic := WorldPersistenceAdapter.new()
	root.add_child(automatic)
	_check(automatic.configure(world, source).error_code == &"save_corrupt", "automatic startup never silently chooses backup history")
	automatic.free()
	var adapter := WorldPersistenceAdapter.new()
	root.add_child(adapter)
	var destination: String = _base.path_join("explicit-recovery")
	_directories.append(destination)
	var result: ServiceResult = adapter.configure_from_backup(world, source, selected, destination, null, CheckpointHistoryPolicy.new())
	_check(result.is_success and result.value["source_sequence"] == 2 and adapter.status()["saved_tick"] == selected["tick_number"] and LocalWorldSaveStore.read_latest(destination).value["snapshot_json"] == snapshot, "explicit startup recovery seeds fresh directory and restores through domain validators")
	_check(FileAccess.get_file_as_string(source.path_join("world-b.json")) == "corrupt active", "operator recovery preserves source active slots and history evidence")
	_check(adapter.request_checkpoint().is_success, "recovered world can checkpoint in fresh destination")
	await _wait(func() -> bool: return not adapter.status()["busy"])
	_check(LocalWorldSaveStore.read_latest(destination).value["sequence"] == 2, "recovered destination starts fresh active sequence without rollback conflicts")
	adapter.free()
	world.free()
	var running := WorldRuntime.new()
	root.add_child(running)
	adapter = WorldPersistenceAdapter.new()
	root.add_child(adapter)
	_check(running.start_simulation().is_success, "start rollback rejection world")
	var forbidden: String = _base.path_join("forbidden-running")
	_check(adapter.configure_from_backup(running, source, selected, forbidden).error_code == &"simulation_already_started" and not DirAccess.dir_exists_absolute(forbidden), "running world rejects selection before destination writes")
	running.stop_simulation()
	_check(adapter.configure_from_backup(running, source, selected, forbidden).error_code == &"simulation_already_started", "stopping an already-started world does not authorize rollback")
	adapter.free()
	running.free()
	var other := WorldRuntime.new()
	other.world_id = &"other.world"
	root.add_child(other)
	adapter = WorldPersistenceAdapter.new()
	root.add_child(adapter)
	_check(adapter.configure_from_backup(other, source, selected, forbidden).error_code == &"world_snapshot_identity_mismatch" and not DirAccess.dir_exists_absolute(forbidden), "wrong identity fails domain restore before destination writes")
	adapter.free()
	other.free()
	world = WorldRuntime.new()
	root.add_child(world)
	adapter = WorldPersistenceAdapter.new()
	root.add_child(adapter)
	_check(adapter.configure_from_backup(world, source, selected, destination).error_code == &"backup_destination", "existing destination is preserved")
	var invalid_source: String = _fixture("domain-invalid")
	var invalid: Dictionary = JSON.parse_string(snapshot)
	invalid["systems"].erase("inventory")
	var invalid_json: String = JSON.stringify(invalid)
	_check(LocalWorldSaveStore.write_checkpoint(invalid_source, 1, invalid_json).is_success and CheckpointBackupHistory.archive_committed(invalid_source, 1, invalid_json, CheckpointHistoryPolicy.new()).is_success, "codec-valid history may still require domain validation")
	_check(not adapter.configure_from_backup(world, invalid_source, _listed(invalid_source)[0], forbidden).is_success and not DirAccess.dir_exists_absolute(forbidden) and world.current_tick_number() == 0, "incompatible domain backup is rejected without startup mutation or destination")
	adapter.free()
	world.free()
	world = WorldRuntime.new()
	root.add_child(world)
	adapter = WorldPersistenceAdapter.new()
	root.add_child(adapter)
	var seed_failure := SeedFaultFiles.new()
	var failed_destination: String = _base.path_join("failed-seed")
	_directories.append(failed_destination)
	_check(adapter.configure_from_backup(world, source, selected, failed_destination, seed_failure).error_code == &"save_write" and adapter.status()["saved_tick"] == -1 and adapter.request_checkpoint().error_code == &"checkpoint_busy", "failed seed returns active write error, claims no saved tick and closes failed startup adapter")
	_check(_listed(source).size() == 2 and FileAccess.get_file_as_string(source.path_join("world-b.json")) == "corrupt active", "failed recovery seed preserves source history and active evidence")
	adapter.free()
	world.free()


func _cleanup(directory: String) -> void:
	var dir := DirAccess.open(directory)
	if dir == null:
		return
	for file in dir.get_files():
		_check(DirAccess.remove_absolute(directory.path_join(file)) == OK, "remove disposable fixture file")
	for child in dir.get_directories():
		_cleanup(directory.path_join(child))
	_check(DirAccess.remove_absolute(directory) == OK, "remove disposable fixture directory")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
