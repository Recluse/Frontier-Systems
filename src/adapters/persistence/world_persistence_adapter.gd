extends Node
class_name WorldPersistenceAdapter

signal checkpoint_completed(tick_number: int, result: ServiceResult)

## Worker owns detached checkpoint values and its result, never the world or adapter.
class CheckpointTask extends RefCounted:
	var directory: String
	var sequence: int
	var tick: int
	var snapshot_json: String
	var files: CheckpointFileIO
	var result: ServiceResult
	var history: CheckpointHistoryPolicy
	var backup_result: ServiceResult

	func execute() -> void:
		result = LocalWorldSaveStore.write_checkpoint(directory, sequence, snapshot_json, files)
		if result.is_success and history != null:
			backup_result = CheckpointBackupHistory.archive_committed(directory, sequence, snapshot_json, history, files)


var _world: WorldRuntime
var _directory: String
var _sequence: int = 0
var _task_id: int = -1
var _task: CheckpointTask
var _files: CheckpointFileIO
var _saved_tick: int = -1
var _elapsed: float = 0.0
var _last_error: String = ""
var _closed: bool = false
var _history: CheckpointHistoryPolicy
var _backup_error: String = ""
var _backup_error_code: StringName = &""
var _backup_sequence: int = 0


## Configure before starting the world; startup reads occur before fixed ticks.
## Optional filesystem boundary is for isolated tests; production uses native file I/O.
func configure(world: WorldRuntime, directory: String, files: CheckpointFileIO = null, history: CheckpointHistoryPolicy = null) -> ServiceResult:
	if _closed or _world != null or not is_instance_valid(world) or directory.is_empty():
		return ServiceResult.failure(&"persistence_configuration", "Configure one world and save directory.")
	if history != null and not history.validate().is_success:
		return history.validate()
	var latest: ServiceResult = LocalWorldSaveStore.read_latest(directory, files)
	if not latest.is_success:
		_last_error = latest.message
		return latest
	if not latest.value.is_empty():
		var restored: ServiceResult = world.restore_world_snapshot_json(latest.value["snapshot_json"])
		if not restored.is_success:
			_last_error = restored.message
			return restored
		_sequence = int(latest.value["sequence"])
		_saved_tick = world.current_tick_number()
	_world = world
	_directory = directory
	_files = files
	_history = history.detached() if history != null else null
	_last_error = ""
	return ServiceResult.success()


## Explicit stopped-world startup recovery only. Never modifies the source save directory.
## Destination must be absent; the selected original sequence remains in source history.
## On seeding failure discard this startup world/adapter; no save was acknowledged.
func configure_from_backup(world: WorldRuntime, source: String, selection: Dictionary, destination: String, io: CheckpointFileIO = null, history: CheckpointHistoryPolicy = null) -> ServiceResult:
	var ready: ServiceResult = _backup_startup_ready(world, source, history)
	if not ready.is_success:
		return ready
	if destination.is_empty():
		return ServiceResult.failure(&"backup_recovery", "Recovery requires an explicit fresh destination.")
	var files: CheckpointFileIO = io if io != null else CheckpointFileIO.new()
	var absolute: String = ProjectSettings.globalize_path(destination).simplify_path()
	var source_absolute: String = ProjectSettings.globalize_path(source).simplify_path().replace("\\", "/").trim_suffix("/")
	var destination_absolute: String = absolute.replace("\\", "/").trim_suffix("/")
	if OS.get_name() == "Windows":
		source_absolute = source_absolute.to_lower()
		destination_absolute = destination_absolute.to_lower()
	if not absolute.is_absolute_path() or destination_absolute == source_absolute or destination_absolute.begins_with(source_absolute + "/"):
		return ServiceResult.failure(&"backup_destination", "Recovery destination must be absolute and outside the source directory.")
	if files.exists(absolute):
		return ServiceResult.failure(&"backup_destination", "Recovery destination must not exist; preserve the source and existing saves.")
	var selected: ServiceResult = _restore_backup_selection(world, source, selection, files)
	if not selected.is_success:
		return selected
	var seeded: ServiceResult = LocalWorldSaveStore.write_checkpoint(absolute, 1, selected.value["snapshot_json"], files)
	if not seeded.is_success:
		_closed = true
		_last_error = seeded.message
		return seeded
	# Adopt the verified seed without restoring twice (the restored world now has a tick).
	_world = world
	_directory = absolute
	_files = io
	_history = history.detached() if history != null else null
	_sequence = 1
	_saved_tick = world.current_tick_number()
	_last_error = ""
	return ServiceResult.success({"source_sequence": int(selected.value["sequence"]), "sequence": 1, "tick_number": world.current_tick_number()})


## Read-only selection/domain validation. Caller must discard the disposable world
## after success or failure; restore may populate it, but storage is never configured.
func preflight_from_backup(world: WorldRuntime, source: String, selection: Dictionary, io: CheckpointFileIO = null) -> ServiceResult:
	var ready: ServiceResult = _backup_startup_ready(world, source)
	if not ready.is_success:
		return ready
	var selected: ServiceResult = _restore_backup_selection(world, source, selection, io)
	if not selected.is_success:
		return selected
	return ServiceResult.success({"source_sequence": int(selected.value["sequence"]), "tick_number": world.current_tick_number()})


func _backup_startup_ready(world: WorldRuntime, source: String, history: CheckpointHistoryPolicy = null) -> ServiceResult:
	if not is_instance_valid(world) or source.is_empty():
		return ServiceResult.failure(&"backup_recovery", "Backup validation requires a fresh adapter/world and explicit source and selection.")
	if _world != null or _closed or (history != null and not history.validate().is_success):
		return ServiceResult.failure(&"backup_recovery", "Recovery requires an unconfigured adapter and a valid policy.")
	# Operational preflight avoids storage calls from active tick callbacks. The owner
	# still makes the authoritative has-started/domain checks during restore below.
	var runtime_status: Dictionary = world.profiling_snapshot()
	if runtime_status.is_empty():
		return ServiceResult.failure(&"runtime_not_ready", "Initialize the startup world before selecting recovery.")
	if runtime_status["simulation_running"] or runtime_status["tick_number"] != 0 or runtime_status["queued_external_commands"] != 0:
		return ServiceResult.failure(&"simulation_already_started", "Recovery requires a fresh stopped startup world without commands.")
	return ServiceResult.success()


func _restore_backup_selection(world: WorldRuntime, source: String, selection: Dictionary, files: CheckpointFileIO) -> ServiceResult:
	var selected: ServiceResult = CheckpointBackupHistory.select_candidate(source, selection, files)
	if not selected.is_success:
		return selected
	# WorldRuntime validates identity, every system, cross-system links and pre-start state.
	var restored: ServiceResult = world.restore_world_snapshot_json(selected.value["snapshot_json"])
	if not restored.is_success:
		return restored
	return selected


func request_checkpoint() -> ServiceResult:
	if _closed or not is_instance_valid(_world) or _task_id >= 0:
		return ServiceResult.failure(&"checkpoint_busy", "The store is unavailable or a checkpoint is already running.")
	if _sequence >= LocalWorldSaveStore.MAX_SEQUENCE:
		_last_error = "Checkpoint sequence is exhausted; no worker was started."
		return ServiceResult.failure(&"checkpoint_sequence_exhausted", _last_error)
	var captured: ServiceResult = _world.capture_world_snapshot_json()
	if not captured.is_success:
		_last_error = captured.message
		return captured
	_task = CheckpointTask.new()
	_task.directory = _directory
	_task.sequence = _sequence + 1
	_task.tick = _world.current_tick_number()
	_task.snapshot_json = captured.value
	_task.files = _files
	_task.history = _history.detached() if _history != null else null
	_task_id = WorkerThreadPool.add_task(_task.execute, false, "World checkpoint")
	# Queue acceptance is not a storage acknowledgement; completion reports the captured tick.
	return ServiceResult.success({"tick_number": _task.tick})


func _finish_task(emit_completion: bool) -> void:
	WorkerThreadPool.wait_for_task_completion(_task_id)
	var completed: CheckpointTask = _task
	var result: ServiceResult = completed.result
	if result == null:
		result = ServiceResult.failure(&"checkpoint_acknowledgement", "Worker did not return a checkpoint result.")
	elif result.is_success and (typeof(result.value) != TYPE_DICTIONARY or not ControlContractValidation.has_exact_fields(result.value, PackedStringArray(["sequence"])) or not ControlContractValidation.is_integer(result.value.get("sequence"), completed.sequence, completed.sequence) or completed.sequence != _sequence + 1 or completed.tick < _saved_tick):
		result = ServiceResult.failure(&"checkpoint_acknowledgement", "Worker acknowledgement does not match the pending checkpoint.")
	# Release the old task before callbacks can queue another checkpoint.
	_task_id = -1
	_task = null
	if result.is_success:
		_sequence = completed.sequence
		_saved_tick = completed.tick
		_last_error = ""
		if completed.history != null:
			var backup: ServiceResult = completed.backup_result
			if backup == null or (backup.is_success and (typeof(backup.value) != TYPE_DICTIONARY or not ControlContractValidation.has_exact_fields(backup.value, PackedStringArray(["sequence"])) or not ControlContractValidation.is_integer(backup.value.get("sequence"), completed.sequence, completed.sequence))):
				backup = ServiceResult.failure(&"backup_acknowledgement", "Worker did not return a matching history acknowledgement.")
			_backup_error = "" if backup.is_success else backup.message
			_backup_error_code = &"" if backup.is_success else backup.error_code
			if backup.is_success:
				_backup_sequence = completed.sequence
	else:
		_last_error = result.message
	if emit_completion:
		checkpoint_completed.emit(completed.tick, result)


func _process(delta: float) -> void:
	if _closed:
		return
	if _task_id >= 0 and WorkerThreadPool.is_task_completed(_task_id):
		_finish_task(true)
	_elapsed += delta
	if _elapsed >= 5.0 and _task_id < 0 and is_instance_valid(_world):
		_elapsed = 0.0
		request_checkpoint()


func status() -> Dictionary:
	return {"saved_tick": _saved_tick, "busy": _task_id >= 0, "last_error": _last_error}


## Separate bounded operator diagnostics; existing checkpoint/network status stays unchanged.
## Sequence is the latest successful history acknowledgement in this adapter session.
func backup_status() -> Dictionary:
	return {"enabled": _history != null, "sequence": _backup_sequence, "last_error": _backup_error, "error_code": String(_backup_error_code)}


func _exit_tree() -> void:
	_closed = true
	# Shutdown only, outside simulation ticks. Join and consume without late callbacks.
	if _task_id >= 0:
		_finish_task(false)
