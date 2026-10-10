extends SceneTree

## Real runner/command/snapshot paths, stepped synchronously for exact tick boundaries.
var _failures: int = 0
var _last_result: ServiceResult


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_pulse_recovery()
	_power_loss()
	_alarm_fanout()
	_board_recovery()
	_interruption()
	_profile_history()
	if _failures == 0:
		print("Control runtime and snapshot recovery scenarios passed.")
	quit(0 if _failures == 0 else 1)


func _world(start: bool = true) -> WorldRuntime:
	var world := WorldRuntime.new()
	root.add_child(world)
	world.command_completed.connect(func(_command: SimulationCommand, result: ServiceResult) -> void: _last_result = result)
	if start:
		_start(world)
	return world


func _start(world: WorldRuntime) -> void:
	_check(world.start_simulation().is_success, "world must start")
	_runner(world).set_physics_process(false)


func _runner(world: WorldRuntime) -> SimulationRunner:
	return world.get_node("SimulationRunner") as SimulationRunner


func _controls(world: WorldRuntime) -> MachineControlSystem:
	return world.get_simulation_system(MachineControlSystem.SYSTEM_ID) as MachineControlSystem


func _access(world: WorldRuntime) -> AccessControlSystem:
	return world.get_simulation_system(AccessControlSystem.SYSTEM_ID) as AccessControlSystem


func _latch(world: WorldRuntime) -> ActuatorState:
	return (_access(world).devices[MachineControlSystem.HOST_ID] as AccessControlledDeviceState).actuator(MachineControlSystem.ACTUATOR_ID)


func _step(world: WorldRuntime, count: int = 1) -> void:
	for _index in range(count):
		_runner(world)._physics_process(1.0 / 60.0)


func _pulse(world: WorldRuntime) -> void:
	var command := DebugControlPulseCommand.new()
	command.command_id = world.next_local_request_id()
	command.authenticated_context = AuthenticatedCommandContext.for_local_development(&"mechanic", world.world_id, world.region_id)
	_check(world.enqueue_command(command).is_success, "pulse command must queue")
	_step(world)
	_check(_last_result.is_success, "debug pulse request must be accepted")


func _maintain(world: WorldRuntime, operation: String, parameters: Dictionary = {}, actor: StringName = &"mechanic") -> ServiceResult:
	var parsed: ServiceResult = MachineMaintenanceIntent.from_record({"schema_version": 2, "operation": operation, "parameters": parameters})
	if not parsed.is_success:
		_check(false, "test maintenance intent must parse")
		return parsed
	var command := MachineMaintenanceCommand.new()
	command.command_id = world.next_local_request_id()
	command.authenticated_context = AuthenticatedCommandContext.for_local_development(actor, world.world_id, world.region_id)
	command.intent = parsed.value
	_check(world.enqueue_command(command).is_success, "maintenance command must queue")
	_step(world)
	return _last_result


func _state(world: WorldRuntime) -> Dictionary:
	var captured: ServiceResult = world.capture_world_snapshot()
	_check(captured.is_success, "world snapshot must validate")
	return captured.value.to_dictionary() if captured.is_success else {}


func _reject_restore(record: Dictionary, message: String) -> void:
	var fresh := _world(false)
	var before: Dictionary = _state(fresh)
	_check(not fresh.restore_world_snapshot_json(JSON.stringify(record)).is_success, message)
	_check(_state(fresh) == before, "failed restore must leave every system unchanged")
	fresh.free()


func _pulse_recovery() -> void:
	var source := _world()
	_pulse(source)
	_check(_latch(source).latch_state == &"engaged", "emission must not actuate on the same tick")
	var record: Dictionary = _state(source)
	var pending: Array = record["systems"]["machine_control"]["circuit"]["pending"]
	_check(pending.size() == 1, "pending pulse must be saved")
	var duplicate: Dictionary = record.duplicate(true)
	duplicate["systems"]["machine_control"]["circuit"]["pending"].append(pending[0].duplicate(true))
	_reject_restore(duplicate, "duplicate pending delivery must reject atomically")
	var future: Dictionary = record.duplicate(true)
	future["systems"]["machine_control"]["circuit"]["pending"][0]["due_tick"] = record["tick_number"] + 2
	_reject_restore(future, "delivery beyond the next frontier must reject")
	var restored := _world(false)
	_check(restored.restore_world_snapshot_json(JSON.stringify(record)).is_success, "pending pulse must survive JSON restoration")
	_start(restored)
	_step(restored)
	_check(_latch(restored).latch_state == &"released", "restored pulse must reach the commissioned latch")
	_check(_controls(restored).diagnostics()["delivered"] == 1, "restored receipt must deliver once")
	_step(restored, 3)
	_check(_controls(restored).diagnostics()["delivered"] == 1, "consumed pulse must not repeat")
	source.free()
	restored.free()


func _power_loss() -> void:
	var world := _world()
	_pulse(world)
	(_access(world).devices[MachineControlSystem.HOST_ID] as AccessControlledDeviceState).controller().power_state = &"unpowered"
	_step(world)
	_check(_latch(world).latch_state == &"engaged" and _controls(world).diagnostics()["dropped"] == 1, "power loss must drop due pulses without unlocking")
	world.free()


func _board_recovery() -> void:
	var world := _world()
	_check(not _maintain(world, "remove", {"instance_id": MachineControlSystem.LATCH_ID}).is_success, "live hardware removal must require isolation")
	_check(_maintain(world, "isolate").is_success, "controller must isolate")
	_check(not _maintain(world, "replace_board", {"target_board_id": "habitat-board-stock"}).is_success, "smaller board must not silently discard utility modules")
	_check(_controls(world)._circuit.set_integrity(MachineControlSystem.LATCH_ID, 0.4).is_success, "damage fixture must apply")
	_check(_maintain(world, "remove", {"instance_id": MachineControlSystem.LATCH_ID}).is_success, "removed part must enter salvage")
	var record: Dictionary = _state(world)
	_check(_tray_part(record, MachineControlSystem.LATCH_ID).get("integrity") == 0.4, "salvage must retain condition")
	var duplicate: Dictionary = record.duplicate(true)
	duplicate["systems"]["machine_control"]["salvage"].append(record["systems"]["machine_control"]["circuit"]["modules"][0].duplicate(true))
	_reject_restore(duplicate, "installed and salvaged identity overlap must reject")
	_check(_maintain(world, "replace_board", {"target_board_id": "habitat-board-stock"}).is_success, "existing stock spare must reserve")
	_step(world, 9)
	record = _state(world)
	_check(record["systems"]["machine_control"]["board_job"]["completed_work_ticks"] == 10, "board work must advance once per fixed tick")
	var missing: Dictionary = record.duplicate(true)
	missing["systems"]["machine_control"]["board_spares"] = []
	_reject_restore(missing, "job without its reserved spare must reject")
	var restored := _world(false)
	_check(restored.restore_world_snapshot_json(JSON.stringify(record)).is_success, "reserved board progress must restore")
	_start(restored)
	_step(restored, 5)
	_check(_controls(restored).diagnostics()["board_job"]["status"] == "paused", "restart must pause actor-owned work")
	_check(_controls(restored).diagnostics()["board_job"]["completed_work_ticks"] == 10, "paused work must retain progress")
	_check(not _maintain(restored, "resume_board_job", {}, &"other-mechanic").is_success, "another actor must not resume the reservation")
	_check(_maintain(restored, "resume_board_job").is_success, "owner must resume")
	_step(restored, BoardReplacementJob.WORK_TICKS - 12)
	_check(_controls(restored).diagnostics()["board_job"]["completed_work_ticks"] == 179, "board exchange must not happen early")
	_step(restored)
	_check(_controls(restored).diagnostics()["board_job"] == null and _controls(restored).diagnostics()["board_revision"] == 1, "stock board must install exactly at completion")
	_check(not _maintain(restored, "install", {"instance_id": MachineControlSystem.LATCH_ID, "slot_id": "door.utility.1"}).is_success, "incompatible reinstall must retain the salvaged part")
	_check(_maintain(restored, "replace_board", {"target_board_id": "habitat-board-expanded"}).is_success, "old board must be reusable as a spare")
	_step(restored, BoardReplacementJob.WORK_TICKS - 1)
	_check(_maintain(restored, "install", {"instance_id": MachineControlSystem.LATCH_ID, "slot_id": "door.utility.1"}).is_success, "same salvaged part must reinstall after expansion")
	record = _state(restored)
	_check(_tray_part(record, MachineControlSystem.LATCH_ID).is_empty(), "successful transfer must consume that part's tray entry")
	var part: ServiceResult = _controls(restored)._circuit.module_record(MachineControlSystem.LATCH_ID)
	_check(part.value["integrity"] == 0.4, "reinstall must not repair integrity")
	world.free()
	restored.free()


func _interruption() -> void:
	var world := _world()
	_maintain(world, "isolate")
	_maintain(world, "remove", {"instance_id": MachineControlSystem.LATCH_ID})
	_maintain(world, "replace_board", {"target_board_id": "habitat-board-stock"})
	(_access(world).devices[MachineControlSystem.HOST_ID] as AccessControlledDeviceState).controller().power_state = &"unpowered"
	_step(world)
	_check(_controls(world).diagnostics()["board_job"]["status"] == "paused", "loss of isolation must pause work")
	_check(_maintain(world, "cancel_board_job").is_success, "owner must be able to cancel when hardware prerequisites are lost")
	_check(_controls(world).diagnostics()["board_revision"] == 2 and _state(world)["systems"]["machine_control"]["board_spares"].size() == 1, "cancellation must preserve both boards")
	world.free()


func _profile_history() -> void:
	var history := TickProfileHistory.new(3)
	for tick in range(1, 7):
		history.record_tick(tick, tick * 10, 2, 1, tick, 50, [])
	var snapshot: Dictionary = history.snapshot(2)
	_check(snapshot["samples"][0]["tick_number"] == 5 and snapshot["samples"][1]["tick_number"] == 6, "ring must retain latest samples chronologically")
	var report: ServiceResult = TickProfileReport.summarize(snapshot)
	_check(report.is_success and report.value["tick_timing_usec"]["p95"] == 60 and report.value["queue_peak"] == 6, "bounded report must calculate window statistics")
	snapshot["samples"][0]["tick_number"] = 999
	_check(history.snapshot(2)["samples"][0]["tick_number"] == 5, "history readout must be detached")


func _tray_part(record: Dictionary, instance_id: String) -> Dictionary:
	for part: Dictionary in record["systems"]["machine_control"]["salvage"]:
		if part["instance_id"] == instance_id:
			return part
	return {}


func _alarm_fanout() -> void:
	var world := _world()
	var adapter := LocalAlarmPulseAdapter.new(_access(world), MachineControlSystem.ALARM_ID, MachineControlSystem.HOST_ID)
	_check(adapter.receive_pulse("foreign-module", "raise_alarm", 1, _access(world).current_tick).error_code == &"invalid_alarm_binding", "alarm adapter must reject another module identity")
	_check(adapter.receive_pulse(MachineControlSystem.ALARM_ID, "clear_alarm", 1, _access(world).current_tick).error_code == &"invalid_alarm_binding", "alarm input must not accept an undeclared clear operation")
	_check(adapter.receive_pulse(MachineControlSystem.ALARM_ID, "raise_alarm", 1, _access(world).current_tick + 1).error_code == &"circuit_tick_mismatch", "alarm adapter must retain authoritative tick validation")
	_check(_maintain(world, "isolate").is_success, "alarm installation must isolate")
	_check(_maintain(world, "install", {"instance_id": MachineControlSystem.ALARM_ID, "slot_id": "door.utility.2"}).is_success, "existing spare alarm must fit general utility bay")
	var wire := {"wire_id": "alarm-wire", "first_module": MachineControlSystem.RECEIVER_ID, "first_port": "pulse_out", "second_module": MachineControlSystem.ALARM_ID, "second_port": "raise_alarm"}
	_check(_maintain(world, "attach_wire", wire).is_success, "one output must connect to an independent alarm input")
	_check(not _maintain(world, "attach_wire", wire).is_success, "duplicate wire identity must reject")
	_check(_maintain(world, "restore_power").is_success, "alarm circuit must recommission")
	_pulse(world)
	_check(_controls(world).diagnostics()["pending_deliveries"] == 2, "receiver output must fan out to latch and alarm")
	var record: Dictionary = _state(world)
	var restored := _world(false)
	_check(restored.restore_world_snapshot_json(JSON.stringify(record)).is_success, "alarm module and queued fanout must restore from trusted catalog")
	_start(restored)
	_step(restored)
	var controller := (_access(restored).devices[MachineControlSystem.HOST_ID] as AccessControlledDeviceState).controller()
	_check(controller.alarm_state == &"local" and _latch(restored).latch_state == &"released", "same pulse must trigger both commissioned actions")
	_check(_controls(restored).diagnostics()["delivered"] == 2, "both restored destinations must deliver once")
	controller.alarm_state = &"remote"
	_pulse(restored)
	_step(restored)
	_check(controller.alarm_state == &"remote", "local trigger must not downgrade a remote alarm")
	controller.alarm_state = &"disabled"
	_pulse(restored)
	_step(restored)
	_check(controller.alarm_state == &"disabled", "trigger must not reactivate disabled alarm hardware")
	controller.alarm_state = &"quiet"
	_check(_controls(restored)._circuit.set_integrity(MachineControlSystem.ALARM_ID, 0.0).is_success, "alarm damage fixture must apply")
	_pulse(restored)
	_step(restored)
	_check(controller.alarm_state == &"quiet", "broken alarm module must not trigger its controller")
	_check(_latch(restored).latch_state == &"released", "a broken optional alarm must preserve the other destination's function")
	_check(_maintain(restored, "isolate").is_success, "alarm removal must isolate")
	_check(_maintain(restored, "remove", {"instance_id": MachineControlSystem.ALARM_ID}).is_success, "zero-integrity alarm must remain salvageable")
	_check(_tray_part(_state(restored), MachineControlSystem.ALARM_ID).get("integrity") == 0.0, "alarm removal must preserve broken condition")
	world.free()
	restored.free()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
