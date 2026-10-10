extends Node
class_name WorldPersistenceAdapter

signal checkpoint_completed(tick_number: int, result: ServiceResult)
var _world: WorldRuntime
var _directory: String
var _sequence: int = 0
var _task_id: int = -1
var _result: ServiceResult
var _saved_tick: int = -1
var _pending_tick: int = -1
var _elapsed: float = 0.0
var _last_error: String = ""


## Configure before starting the world; startup reads occur before fixed ticks.
func configure(world: WorldRuntime, directory: String) -> ServiceResult:
	if _world != null or not is_instance_valid(world) or directory.is_empty():
		return ServiceResult.failure(&"persistence_configuration", "Configure one world and save directory.")
	var latest: ServiceResult = LocalWorldSaveStore.read_latest(directory)
	if not latest.is_success:
		return latest
	if not latest.value.is_empty():
		var restored: ServiceResult = world.restore_world_snapshot_json(latest.value["snapshot_json"])
		if not restored.is_success:
			return restored
		_sequence = int(latest.value["sequence"])
		_saved_tick = world.current_tick_number()
	_world = world
	_directory = directory
	return ServiceResult.success()


func request_checkpoint() -> ServiceResult:
	if not is_instance_valid(_world) or _task_id >= 0:
		return ServiceResult.failure(&"checkpoint_busy", "The store is unavailable or a checkpoint is already running.")
	var captured: ServiceResult = _world.capture_world_snapshot_json()
	if not captured.is_success:
		return captured
	_pending_tick = _world.current_tick_number()
	_sequence += 1
	_result = null
	_task_id = WorkerThreadPool.add_task(_write.bind(_sequence, captured.value), false, "World checkpoint")
	return ServiceResult.success({"tick_number": _pending_tick})


func _write(sequence: int, json: String) -> void:
	_result = LocalWorldSaveStore.write_checkpoint(_directory, sequence, json)


func _process(delta: float) -> void:
	if _task_id >= 0 and WorkerThreadPool.is_task_completed(_task_id):
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1
		if _result.is_success:
			_saved_tick = _pending_tick
			_last_error = ""
		else:
			_last_error = _result.message
		checkpoint_completed.emit(_pending_tick, _result)
	_elapsed += delta
	if _elapsed >= 5.0 and _task_id < 0 and is_instance_valid(_world):
		_elapsed = 0.0
		request_checkpoint()


func status() -> Dictionary:
	return {"saved_tick": _saved_tick, "busy": _task_id >= 0, "last_error": _last_error}


func _exit_tree() -> void:
	# Shutdown only, outside simulation ticks. Join before releasing worker-owned data.
	if _task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(_task_id)
