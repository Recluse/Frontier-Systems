extends Node
class_name SimulationRunner

## Executes simulation systems on Godot's fixed physics cadence and records tick costs.
## Service responses must be converted into bounded commands and applied at tick start.

signal external_command_completed(command: SimulationCommand, result: ServiceResult)

@export_range(1, 1000000, 1) var tick_budget_usec: int = 16667
@export_range(1, 65536, 1) var max_external_commands_per_tick: int = 256
@export_range(1, 1048576, 1) var max_queued_external_commands: int = 8192

var tick_number: int = 0
var has_started: bool = false
var is_running: bool = false
var _systems: Array[SimulationSystem] = []
var _external_commands: Array[SimulationCommand] = []
var _external_command_head: int = 0
var _system_metrics: Dictionary = {}
var _dropped_external_commands: int = 0
var _rejected_external_commands: int = 0
var _last_tick_usec: int = 0
var _max_tick_usec: int = 0
var _over_budget_ticks: int = 0
var _is_simulating_tick: bool = false
var _profile_history := TickProfileHistory.new()
var _capture_profile_history: bool = false
var _last_command_usec: int = 0
var _last_commands_processed: int = 0
var _last_profile_usec: int = 0


func _ready() -> void:
	process_physics_priority = -100
	set_physics_process(false)
	for child in get_children():
		if child is SimulationSystem:
			register_system(child)


## Starts fixed ticks after optional startup restoration has completed.
func start_simulation() -> ServiceResult:
	if not is_inside_tree():
		return ServiceResult.failure(&"runner_not_ready", "The simulation runner must be in the scene tree before it can start.")
	has_started = true
	is_running = true
	set_physics_process(true)
	return ServiceResult.success({"tick_number": tick_number})


## Stops fixed ticks; a started runner cannot later accept a startup restore.
func stop_simulation() -> void:
	is_running = false
	set_physics_process(false)


func register_system(system: SimulationSystem) -> bool:
	if system == null or system.system_id == &"" or _systems.has(system):
		return false
	for registered in _systems:
		if registered.system_id == system.system_id:
			return false
	_systems.append(system)
	_systems.sort_custom(_system_order)
	_system_metrics[system.system_id] = {
		"ticks": 0,
		"last_usec": 0,
		"total_usec": 0,
		"max_usec": 0,
		"over_budget_ticks": 0,
	}
	return true


func unregister_system(system_id: StringName) -> bool:
	for index in range(_systems.size()):
		if _systems[index].system_id == system_id:
			_systems.remove_at(index)
			_system_metrics.erase(system_id)
			return true
	return false


func get_system(system_id: StringName) -> SimulationSystem:
	for system in _systems:
		if system.system_id == system_id:
			return system
	return null


## Captures a stable state only outside a tick and with no pending commands.
func capture_snapshot() -> ServiceResult:
	if _is_simulating_tick:
		return ServiceResult.failure(&"snapshot_during_tick", "Capture a world snapshot after the current simulation tick completes.")
	if _external_commands.size() - _external_command_head > 0:
		return ServiceResult.failure(&"commands_pending", "Wait until queued commands are applied before capturing a world snapshot.")
	if _systems.is_empty():
		return ServiceResult.failure(&"no_registered_systems", "A world snapshot requires at least one registered simulation system.")

	var system_records: Dictionary = {}
	for system in _systems:
		var result: ServiceResult = system.capture_snapshot()
		if not result.is_success:
			return ServiceResult.failure(
				&"system_snapshot_failed",
				"System %s could not be captured: %s" % [system.system_id, result.message]
			)
		if typeof(result.value) != TYPE_DICTIONARY:
			return ServiceResult.failure(&"invalid_system_snapshot", "System %s returned a non-record snapshot." % system.system_id)
		var validation: ServiceResult = system.validate_snapshot_record(result.value, tick_number)
		if not validation.is_success:
			return ServiceResult.failure(
				&"invalid_system_snapshot",
				"System %s produced an invalid snapshot: %s" % [system.system_id, validation.message]
			)
		system_records[String(system.system_id)] = result.value

	return ServiceResult.success({"tick_number": tick_number, "systems": system_records})


## Validates all registered systems before restoring any system-owned state.
func restore_snapshot(snapshot_tick_number: int, system_records: Dictionary) -> ServiceResult:
	if has_started or tick_number != 0 or _external_commands.size() - _external_command_head > 0:
		return ServiceResult.failure(&"simulation_already_started", "A world snapshot can only be restored before simulation ticks or commands begin.")
	if snapshot_tick_number < 0:
		return ServiceResult.failure(&"invalid_snapshot_tick", "The snapshot tick number must be non-negative.")
	if _systems.is_empty():
		return ServiceResult.failure(&"no_registered_systems", "A world snapshot cannot be restored before simulation systems are registered.")
	if system_records.size() != _systems.size():
		return ServiceResult.failure(&"snapshot_system_set_mismatch", "The snapshot must contain exactly the registered simulation systems.")

	var registered_ids: Dictionary = {}
	for system in _systems:
		var system_id: String = String(system.system_id)
		if not system_records.has(system_id):
			return ServiceResult.failure(&"snapshot_system_missing", "The snapshot is missing system %s." % system_id)
		registered_ids[system_id] = true
	for system_id in system_records:
		if typeof(system_id) != TYPE_STRING or not registered_ids.has(system_id):
			return ServiceResult.failure(&"snapshot_system_unknown", "The snapshot contains an unregistered simulation system.")
		if typeof(system_records[system_id]) != TYPE_DICTIONARY:
			return ServiceResult.failure(&"invalid_system_snapshot", "System %s must be represented by a record object." % system_id)

	for system in _systems:
		var record: Dictionary = system_records[String(system.system_id)]
		var validation: ServiceResult = system.validate_snapshot_record(record, snapshot_tick_number)
		if not validation.is_success:
			return ServiceResult.failure(
				&"snapshot_validation_failed",
				"System %s rejected the snapshot: %s" % [system.system_id, validation.message]
			)

	for system in _systems:
		var record: Dictionary = system_records[String(system.system_id)]
		var restored: ServiceResult = system.restore_snapshot_record(record, snapshot_tick_number)
		if not restored.is_success:
			return ServiceResult.failure(
				&"snapshot_restore_failed",
				"System %s failed to restore a previously validated snapshot: %s" % [system.system_id, restored.message]
			)

	tick_number = snapshot_tick_number
	return ServiceResult.success({"tick_number": tick_number})


func enqueue_external_command(command: SimulationCommand) -> ServiceResult:
	if not is_running:
		return ServiceResult.failure(&"simulation_not_running", "The simulation is not accepting commands while stopped.")
	if command == null:
		return ServiceResult.failure(&"invalid_command", "A simulation command is required.")
	if command.command_id == &"":
		return ServiceResult.failure(&"missing_command_id", "A command ID is required.")
	var world_runtime := get_parent() as WorldRuntime
	if world_runtime == null or command.authenticated_context == null:
		return ServiceResult.failure(&"unauthenticated_command", "Commands must be bound to a server-authenticated context before queueing.")
	if not command.authenticated_context.is_valid_for(world_runtime.world_id, world_runtime.region_id):
		return ServiceResult.failure(&"command_scope_mismatch", "Command principal is not scoped to this world and region.")
	if _external_commands.size() - _external_command_head >= max_queued_external_commands:
		_dropped_external_commands += 1
		return ServiceResult.failure(&"command_queue_full", "The simulation command queue is full.")
	_external_commands.append(command)
	return ServiceResult.success({"command_id": command.command_id, "status": "queued"})


func profiling_snapshot() -> Dictionary:
	return {
		"schema_version": 1,
		"tick_number": tick_number,
		"simulation_running": is_running,
		"tick_budget_usec": tick_budget_usec,
		"last_tick_usec": _last_tick_usec,
		"max_tick_usec": _max_tick_usec,
		"over_budget_ticks": _over_budget_ticks,
		"dropped_external_commands": _dropped_external_commands,
		"rejected_external_commands": _rejected_external_commands,
		"queued_external_commands": _external_commands.size() - _external_command_head,
		"systems": _system_metrics.duplicate(true),
		"last_command_usec": _last_command_usec,
		"last_commands_processed": _last_commands_processed,
		"history_enabled": _capture_profile_history,
		"last_profile_usec": _last_profile_usec,
		"last_total_tick_usec": _last_tick_usec + _last_profile_usec,
	}


## Observer configuration only; does not change tick or command budgets.
func configure_profile_history(enabled: bool, capacity: int = 120) -> ServiceResult:
	if _is_simulating_tick:
		return ServiceResult.failure(&"profiling_during_tick", "Configure profiling between completed ticks.")
	if capacity < 1 or capacity > TickProfileHistory.MAX_CAPACITY:
		return ServiceResult.failure(&"invalid_profile_capacity", "History capacity must be between one and 2,048 samples.")
	if enabled:
		_profile_history = TickProfileHistory.new(capacity)
	_capture_profile_history = enabled
	return ServiceResult.success({"enabled": enabled, "capacity": _profile_history.snapshot(0)["capacity"]})


func profiling_history(limit: int = 120) -> Dictionary:
	return _profile_history.snapshot(limit)


## History copies, sorting and JSON capture belong between ticks, never in hooks.
func capture_profiling(limit: int = 120) -> ServiceResult:
	if _is_simulating_tick:
		return ServiceResult.failure(&"profile_capture_during_tick", "Build profiling reports between completed ticks.")
	var history: Dictionary = _profile_history.snapshot(limit)
	var report: ServiceResult = TickProfileReport.summarize(history)
	if not report.is_success:
		return report
	return ServiceResult.success({"capture_tick_number": tick_number, "history": history, "report": report.value})


func _physics_process(fixed_delta: float) -> void:
	if not is_running:
		return
	_is_simulating_tick = true
	tick_number += 1
	var tick_started_usec: int = Time.get_ticks_usec()
	var command_started_usec: int = Time.get_ticks_usec()
	_last_commands_processed = mini(max_external_commands_per_tick, _external_commands.size() - _external_command_head)
	_run_external_commands()
	_last_command_usec = Time.get_ticks_usec() - command_started_usec
	var system_samples: Array[Dictionary] = []
	var system_observers: Array[SimulationSystem] = []
	for system in _systems:
		if not is_instance_valid(system):
			continue
		var system_started_usec: int = Time.get_ticks_usec()
		system.simulate_tick(tick_number, fixed_delta)
		var elapsed_usec: int = Time.get_ticks_usec() - system_started_usec
		_record_system_time(system.system_id, elapsed_usec)
		if _capture_profile_history and system_samples.size() < TickProfileHistory.MAX_SYSTEMS:
			system_samples.append({"system_id": String(system.system_id), "elapsed_usec": elapsed_usec})
			system_observers.append(system)
	_last_tick_usec = Time.get_ticks_usec() - tick_started_usec
	_max_tick_usec = maxi(_max_tick_usec, _last_tick_usec)
	if _last_tick_usec > tick_budget_usec:
		_over_budget_ticks += 1
	_last_profile_usec = 0
	if _capture_profile_history:
		var profile_started_usec: int = Time.get_ticks_usec()
		for index in range(system_samples.size()):
			var sampled_system: SimulationSystem = system_observers[index]
			if is_instance_valid(sampled_system):
				system_samples[index]["counters"] = sampled_system.profiling_counters()
		_profile_history.record_tick(tick_number, _last_tick_usec, _last_command_usec, _last_commands_processed, _external_commands.size() - _external_command_head, tick_budget_usec, system_samples)
		_last_profile_usec = Time.get_ticks_usec() - profile_started_usec
	_is_simulating_tick = false


func _run_external_commands() -> void:
	var remaining: int = _external_commands.size() - _external_command_head
	var count: int = mini(max_external_commands_per_tick, remaining)
	for _index in range(count):
		var command: SimulationCommand = _external_commands[_external_command_head]
		_external_command_head += 1
		var result: ServiceResult = command.execute(get_parent())
		if not result.is_success:
			_rejected_external_commands += 1
		external_command_completed.emit(command, result)

	if _external_command_head == _external_commands.size():
		_external_commands.clear()
		_external_command_head = 0
	elif _external_command_head >= 256 and _external_command_head * 2 >= _external_commands.size():
		var pending_commands: Array[SimulationCommand] = []
		for index in range(_external_command_head, _external_commands.size()):
			pending_commands.append(_external_commands[index])
		_external_commands = pending_commands
		_external_command_head = 0


func _record_system_time(system_id: StringName, elapsed_usec: int) -> void:
	if not _system_metrics.has(system_id):
		return
	var metrics: Dictionary = _system_metrics[system_id]
	metrics["ticks"] += 1
	metrics["last_usec"] = elapsed_usec
	metrics["total_usec"] += elapsed_usec
	metrics["max_usec"] = maxi(metrics["max_usec"], elapsed_usec)
	if elapsed_usec > tick_budget_usec:
		metrics["over_budget_ticks"] += 1
	_system_metrics[system_id] = metrics


func _system_order(left: SimulationSystem, right: SimulationSystem) -> bool:
	if left.tick_priority == right.tick_priority:
		return String(left.system_id) < String(right.system_id)
	return left.tick_priority < right.tick_priority
