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

	func execute() -> void:
		result = LocalWorldSaveStore.write_checkpoint(directory, sequence, snapshot_json, files)


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


## Configure before starting the world; startup reads occur before fixed ticks.
## Optional filesystem boundary is for isolated tests; production uses native file I/O.
func configure(world: WorldRuntime, directory: String, files: CheckpointFileIO = null) -> ServiceResult:
	if _closed or _world != null or not is_instance_valid(world) or directory.is_empty():
		return ServiceResult.failure(&"persistence_configuration", "Configure one world and save directory.")
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
	_last_error = ""
	return ServiceResult.success()


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


func _exit_tree() -> void:
	_closed = true
	# Shutdown only, outside simulation ticks. Join and consume without late callbacks.
	if _task_id >= 0:
		_finish_task(false)
