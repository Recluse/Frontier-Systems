extends SceneTree

class FaultFiles extends CheckpointFileIO:
	var fault: String = ""

	func ensure_directory(path: String) -> ServiceResult:
		if fault == "directory":
			return ServiceResult.failure(&"save_directory", "Injected directory failure.")
		return super.ensure_directory(path)

	func write_text(path: String, text: String) -> ServiceResult:
		if fault == "open":
			return ServiceResult.failure(&"save_open", "Injected open failure.")
		if fault == "flush":
			super.write_text(path, text.substr(0, 20))
			return ServiceResult.failure(&"save_write", "Injected interrupted write/flush failure.")
		return super.write_text(path, text.substr(0, 20) if fault == "short" or fault == "cleanup" else text)

	func read_text(path: String, max_bytes: int) -> ServiceResult:
		if fault == "read" and path.ends_with(".tmp") or fault == "unreadable" and path.ends_with("world-a.json"):
			return ServiceResult.failure(&"save_read", "Injected read failure.")
		return super.read_text(path, max_bytes)

	func remove_file(path: String) -> ServiceResult:
		if fault == "cleanup" and path.ends_with(".tmp") or fault == "remove" and path.ends_with("world-a.json"):
			return ServiceResult.failure(&"save_cleanup", "Injected cleanup failure.")
		return super.remove_file(path)

	func promote(source: String, destination: String) -> ServiceResult:
		if fault == "promote":
			return ServiceResult.failure(&"save_promote", "Injected promotion interruption.")
		return super.promote(source, destination)


class GatedFiles extends CheckpointFileIO:
	var entered := Semaphore.new()
	var release := Semaphore.new()
	var worker_id: int = -1

	func write_text(path: String, text: String) -> ServiceResult:
		worker_id = OS.get_thread_caller_id()
		entered.post()
		release.wait()
		return super.write_text(path, text)


var _failures: int = 0
var _directories: Array[String] = []
var _base: String
var _completions: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_base = OS.get_user_data_dir().path_join("checkpoint-recovery-test-%d" % Time.get_ticks_usec())
	_test_store()
	await _test_adapter()
	await _test_stale_acknowledgements()
	await _test_shutdown()
	for directory in _directories:
		_cleanup(directory)
	DirAccess.remove_absolute(_base)
	_check(not DirAccess.dir_exists_absolute(_base), "temporary storage is cleaned after all scenarios")
	if _failures == 0:
		print("CHECKPOINT RECOVERY: staged interruptions, bounded corrupt-slot fallback, fault-injected failures, matching acknowledgements, retries and shutdown passed.")
	quit(0 if _failures == 0 else 1)


func _fixture(name: String) -> String:
	var directory: String = _base.path_join(name)
	_directories.append(directory)
	_check(DirAccess.make_dir_recursive_absolute(directory) == OK, "create disposable fixture " + name)
	return directory


func _snapshot(tick: int = 0) -> String:
	return WorldSnapshot.new(&"world.recovery", &"region.recovery", tick, {"fixture": {"marker": tick}}).to_json()


func _raw(path: String, text: String) -> void:
	_check(CheckpointFileIO.new().write_text(path, text).is_success, "write isolated fixture")


func _latest_is(directory: String, sequence: int, message: String) -> void:
	var latest: ServiceResult = LocalWorldSaveStore.read_latest(directory)
	_check(latest.is_success and not latest.value.is_empty() and int(latest.value["sequence"]) == sequence, message)


func _test_store() -> void:
	var directory: String = _fixture("interruptions")
	_check(LocalWorldSaveStore.read_latest(directory).is_success and LocalWorldSaveStore.read_latest(directory).value.is_empty(), "missing slots mean a new world")
	_check(LocalWorldSaveStore.write_checkpoint(directory, 1, _snapshot(1)).is_success, "first checkpoint promotes")
	var original: String = FileAccess.get_file_as_string(directory.path_join("world-b.json"))
	_raw(directory.path_join("world-a.json.tmp"), "interrupted staging")
	_latest_is(directory, 1, "partial staging is ignored after restart")
	var staged: Dictionary = JSON.parse_string(original)
	staged["sequence"] = 2
	staged["snapshot_json"] = _snapshot(2)
	staged["sha256"] = _snapshot(2).sha256_text()
	_raw(directory.path_join("world-a.json.tmp"), JSON.stringify(staged))
	_latest_is(directory, 1, "even checksum-valid staging is not a committed recovery candidate")
	_check(LocalWorldSaveStore.write_checkpoint(directory, 2, _snapshot(2)).is_success, "retry replaces abandoned staging")
	_check(not FileAccess.file_exists(directory.path_join("world-a.json.tmp")), "successful promotion consumes staging")
	_latest_is(directory, 2, "highest valid committed sequence wins")
	_raw(directory.path_join("world-a.json"), "truncated envelope")
	_latest_is(directory, 1, "truncated newest slot falls back to prior checkpoint")
	var valid: Dictionary = JSON.parse_string(original)
	valid["sequence"] = 2
	valid["snapshot_json"] = _snapshot(2)
	_raw(directory.path_join("world-a.json"), JSON.stringify(valid))
	_latest_is(directory, 1, "checksum mismatch falls back")
	valid["snapshot_json"] = "{}"
	valid["sha256"] = "{}".sha256_text()
	_raw(directory.path_join("world-a.json"), JSON.stringify(valid))
	_latest_is(directory, 1, "invalid world envelope falls back despite a matching checksum")
	valid = JSON.parse_string(original)
	_raw(directory.path_join("world-a.json"), JSON.stringify(valid))
	_latest_is(directory, 1, "misplaced sequence parity is rejected")
	_raw(directory.path_join("world-a.json"), "x".repeat(LocalWorldSaveStore.MAX_BYTES + 1))
	_latest_is(directory, 1, "oversized slot is bounded and falls back")
	_check(LocalWorldSaveStore.write_checkpoint(directory, 2, _snapshot(2)).is_success, "valid retry repairs only the inactive corrupt slot")
	_check(FileAccess.get_file_as_string(directory.path_join("world-b.json")) == original, "repair preserves previous checkpoint bytes")
	var exhausted: String = _fixture("exhausted")
	var maximum: Dictionary = JSON.parse_string(original)
	maximum["sequence"] = LocalWorldSaveStore.MAX_SEQUENCE
	_raw(exhausted.path_join("world-a.json"), JSON.stringify(maximum))
	_latest_is(exhausted, LocalWorldSaveStore.MAX_SEQUENCE, "maximum exact sequence remains readable")
	_check(LocalWorldSaveStore.write_checkpoint(exhausted, LocalWorldSaveStore.MAX_SEQUENCE + 1, _snapshot()).error_code == &"save_bounds", "sequence overflow fails before write")
	_check(LocalWorldSaveStore.write_checkpoint(directory, 1, _snapshot()).error_code == &"save_sequence", "stale write cannot overwrite a newer checkpoint")
	_check(LocalWorldSaveStore.write_checkpoint(directory, 4, _snapshot()).error_code == &"save_sequence", "skipped parity cannot replace the latest valid slot")
	_check(LocalWorldSaveStore.write_checkpoint(directory, 2, _snapshot(2)).is_success, "identical lost acknowledgement can be retried")
	_check(LocalWorldSaveStore.write_checkpoint(directory, 3, "{}").error_code == &"save_snapshot", "writer rejects invalid snapshot without touching disk")
	_check(LocalWorldSaveStore.write_checkpoint(directory, 3, "x".repeat(LocalWorldSaveStore.MAX_BYTES / 2 + 1)).error_code == &"save_bounds", "snapshot byte bound fails before parse/write")
	var empty: String = WorldSnapshot.new(&"w", &"r", 0, {"f": {"s": ""}}).to_json()
	var quote_count: int = (LocalWorldSaveStore.MAX_BYTES / 2 - empty.to_utf8_buffer().size()) / 2
	var escaped: String = WorldSnapshot.new(&"w", &"r", 0, {"f": {"s": '"'.repeat(quote_count)}}).to_json()
	_check(escaped.to_utf8_buffer().size() <= LocalWorldSaveStore.MAX_BYTES / 2, "escaped snapshot fits its own UTF-8 byte bound")
	_check(LocalWorldSaveStore.write_checkpoint(directory, 3, escaped).error_code == &"save_bounds", "JSON escaping can exceed envelope bound even when snapshot fits")
	for fault in ["directory", "open", "flush", "short", "read", "remove", "promote", "cleanup"]:
		var failures: String = _fixture(fault)
		_check(LocalWorldSaveStore.write_checkpoint(failures, 1, _snapshot(1)).is_success, "seed fault fixture")
		var files := FaultFiles.new()
		files.fault = fault
		for attempt in range(2):
			var result: ServiceResult = LocalWorldSaveStore.write_checkpoint(failures, 2, _snapshot(2), files)
			var expected: StringName = {"directory": &"save_directory", "open": &"save_open", "flush": &"save_write", "short": &"save_verify", "read": &"save_verify", "remove": &"save_cleanup", "promote": &"save_promote", "cleanup": &"save_cleanup"}[fault]
			_check(not result.is_success and result.error_code == expected, "%s failure %d is accurately reported" % [fault, attempt])
			_latest_is(failures, 1, "repeated failure retains last committed checkpoint")
			_check(FileAccess.get_file_as_string(failures.path_join("world-b.json")) == original, "failure preserves latest bytes")
			_check(FileAccess.file_exists(failures.path_join("world-a.json.tmp")) == (fault == "cleanup"), "failed staging cleanup is either complete or explicitly reported")
		files.fault = ""
		_check(LocalWorldSaveStore.write_checkpoint(failures, 2, _snapshot(2), files).is_success, "retry after fault succeeds without a skipped sequence")
	var unreadable := FaultFiles.new()
	unreadable.fault = "unreadable"
	_check(LocalWorldSaveStore.read_latest(directory, unreadable).error_code == &"save_read", "unreadable slot is not silently treated as an absent or corrupt file")
	_check(LocalWorldSaveStore.write_checkpoint(directory, 3, _snapshot(3), unreadable).error_code == &"save_read", "writer preserves an unreadable potentially newer slot")
	_raw(directory.path_join("world-a.json"), "corrupt a")
	_raw(directory.path_join("world-b.json"), "corrupt b")
	_check(LocalWorldSaveStore.read_latest(directory).error_code == &"save_corrupt", "two corrupt slots fail closed")
	_check(LocalWorldSaveStore.write_checkpoint(directory, 1, _snapshot()).error_code == &"save_corrupt", "writer preserves both corrupt slots for recovery")
	_check(FileAccess.get_file_as_string(directory.path_join("world-a.json")) == "corrupt a", "failed recovery never deletes evidence")
	var invalid_path: String = _fixture("invalid-path")
	_raw(invalid_path.path_join("file"), "blocking parent file")
	_check(LocalWorldSaveStore.write_checkpoint(invalid_path.path_join("file/child"), 1, _snapshot()).error_code == &"save_directory", "real unusable directory returns a reason-coded error")


func _observe(store: WorldPersistenceAdapter) -> void:
	store.checkpoint_completed.connect(func(tick: int, result: ServiceResult) -> void: _completions.append({"tick": tick, "result": result}))


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
	var store := WorldPersistenceAdapter.new()
	root.add_child(store)
	var files := FaultFiles.new()
	_check(store.configure(world, directory, files).is_success, "adapter initializes outside ticks")
	_observe(store)
	var before: int = _completions.size()
	_check(store.request_checkpoint().is_success and store.status()["saved_tick"] == -1 and store.status()["busy"], "request accepts work without claiming a saved tick")
	_check(store.request_checkpoint().error_code == &"checkpoint_busy", "overlapping request is rejected")
	await _wait(func() -> bool: return not store.status()["busy"])
	_check(_completions.size() == before + 1 and _completions.back()["result"].is_success and store.status()["saved_tick"] == 0, "one success acknowledges the captured tick")
	_check(world.start_simulation().is_success, "fixture world begins ticks")
	await create_timer(0.08).timeout
	files.fault = "flush"
	for attempt in range(2):
		var saved_tick: int = store.status()["saved_tick"]
		before = _completions.size()
		_check(store.request_checkpoint().is_success, "failed writes are still queued asynchronously")
		await _wait(func() -> bool: return not store.status()["busy"])
		_check(_completions.size() == before + 1 and _completions.back()["result"].error_code == &"save_write" and store.status()["saved_tick"] == saved_tick and not store.status()["last_error"].is_empty(), "failed write emits one failure and retains saved tick")
		_latest_is(directory, 1, "adapter retry cannot truncate the only good checkpoint")
	files.fault = ""
	_check(store.request_checkpoint().is_success, "adapter retries after an I/O failure")
	await _wait(func() -> bool: return not store.status()["busy"])
	_latest_is(directory, 2, "retry commits the next sequence")
	_check(store.status()["last_error"].is_empty() and store.status()["saved_tick"] > 0, "success clears prior error")
	var latest: ServiceResult = LocalWorldSaveStore.read_latest(directory)
	store.free()
	world.free()
	var restored := WorldRuntime.new()
	root.add_child(restored)
	var recovered := WorldPersistenceAdapter.new()
	root.add_child(recovered)
	_check(recovered.configure(restored, directory).is_success and recovered.status()["saved_tick"] == WorldSnapshot.from_json(latest.value["snapshot_json"]).value.tick_number, "restart restores checkpoint tick before simulation")
	var maximum: Dictionary = latest.value.duplicate(true)
	maximum["sequence"] = LocalWorldSaveStore.MAX_SEQUENCE
	var exhausted: String = _fixture("adapter-exhausted")
	_raw(exhausted.path_join("world-a.json"), JSON.stringify(maximum))
	var max_world := WorldRuntime.new()
	root.add_child(max_world)
	var max_store := WorldPersistenceAdapter.new()
	root.add_child(max_store)
	_check(max_store.configure(max_world, exhausted).is_success, "maximum sequence configures")
	_check(max_store.request_checkpoint().error_code == &"checkpoint_sequence_exhausted" and not max_store.status()["busy"] and not max_store.status()["last_error"].is_empty(), "exhaustion is reported without spawning a worker")
	max_store.free()
	max_world.free()
	recovered.free()
	restored.free()


func _test_stale_acknowledgements() -> void:
	for wrong in [ServiceResult.success({"sequence": 99}), ServiceResult.success({"sequence": 1, "extra": true}), ServiceResult.success(null), null]:
		var directory: String = _fixture("stale-%d" % _directories.size())
		var world := WorldRuntime.new()
		root.add_child(world)
		var store := WorldPersistenceAdapter.new()
		root.add_child(store)
		store.set_process(false)
		_check(store.configure(world, directory).is_success and store.request_checkpoint().is_success, "queue acknowledgement fixture")
		await _wait(func() -> bool: return WorkerThreadPool.is_task_completed(store._task_id))
		# Replace only after the real worker completes: no test/main/worker data race.
		store._task.result = wrong
		_observe(store)
		var before: int = _completions.size()
		store._process(0.0)
		_check(_completions.size() == before + 1 and _completions.back()["result"].error_code == &"checkpoint_acknowledgement" and store.status()["saved_tick"] == -1 and not store.status()["busy"], "stale/malformed/missing result cannot claim persistence")
		store._process(0.0)
		_check(_completions.size() == before + 1, "completion is consumed only once")
		_check(store.request_checkpoint().is_success, "lost acknowledgement is retryable with identical snapshot")
		await _wait(func() -> bool: return WorkerThreadPool.is_task_completed(store._task_id))
		store._process(0.0)
		_check(store.status()["saved_tick"] == 0 and store.status()["last_error"].is_empty(), "matching retry consumes already committed checkpoint")
		store.free()
		world.free()


func _test_shutdown() -> void:
	var directory: String = _fixture("shutdown")
	var world := WorldRuntime.new()
	root.add_child(world)
	var store := WorldPersistenceAdapter.new()
	root.add_child(store)
	var files := GatedFiles.new()
	_check(store.configure(world, directory, files).is_success and world.start_simulation().is_success, "gated worker fixture starts")
	_observe(store)
	var before: int = _completions.size()
	var accepted: ServiceResult = store.request_checkpoint()
	_check(accepted.is_success and store.status()["saved_tick"] == -1, "gated request returns before write completes")
	await _wait(func() -> bool: return files.entered.try_wait())
	var captured_tick: int = accepted.value["tick_number"]
	await create_timer(0.08).timeout
	_check(world.current_tick_number() > captured_tick and store.status()["busy"] and _completions.size() == before, "blocked storage does not stall simulation ticks or emit premature success")
	files.release.post()
	# Removing the adapter joins outside ticks and consumes completion without a late callback.
	root.remove_child(store)
	_check(not store.status()["busy"] and store.status()["saved_tick"] == captured_tick and _completions.size() == before, "shutdown joins and records only the captured tick without late callbacks")
	_check(files.worker_id != OS.get_thread_caller_id(), "storage write ran off the main simulation thread")
	_check(store.request_checkpoint().error_code == &"checkpoint_busy", "closed adapter cannot start new work")
	store.free()
	world.free()
	_latest_is(directory, 1, "shutdown checkpoint is recoverable")


func _cleanup(directory: String) -> void:
	var dir := DirAccess.open(directory)
	if dir == null:
		return
	for file in dir.get_files():
		_check(DirAccess.remove_absolute(directory.path_join(file)) == OK, "remove temporary fixture file")
	for child in dir.get_directories():
		_cleanup(directory.path_join(child))
	_check(DirAccess.remove_absolute(directory) == OK, "remove temporary fixture directory")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)


