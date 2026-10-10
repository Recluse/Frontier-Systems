extends SceneTree

## Exercises the real command path with missing power/controller and physical locks.

var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run_scenarios")


func _run_scenarios() -> void:
	var world := WorldRuntime.new()
	root.add_child(world)
	var pressure := world.get_simulation_system(PressureSystem.SYSTEM_ID) as PressureSystem
	var access := world.get_simulation_system(AccessControlSystem.SYSTEM_ID) as AccessControlSystem
	var device := access.devices[WorldRuntime.PROTOTYPE_AIRLOCK_ID] as AccessControlledDeviceState
	var actuator := device.actuator(&"habitat_airlock-outer-door")
	var controller := device.controller()
	var airlock := pressure.airlocks[WorldRuntime.PROTOTYPE_AIRLOCK_ID] as AirlockState
	for volume_value in pressure.volumes.values():
		var volume := volume_value as PressureVolumeState
		volume.gas_moles = 0.0
	controller.power_state = &"unpowered"
	actuator.latch_state = &"released"
	var manual_actor: AuthenticatedCommandContext = AuthenticatedCommandContext.from_authenticated_session(
		&"mechanic", &"session", world.world_id, world.region_id,
		PackedStringArray(["airlock.manual_operate"]),
		{"tool.pry": PackedStringArray(["crowbar-1"])}
	)
	var operator_actor: AuthenticatedCommandContext = AuthenticatedCommandContext.from_authenticated_session(
		&"operator", &"session", world.world_id, world.region_id, PackedStringArray(["airlock.operate"])
	)
	_check(_execute(world, AirlockState.Action.OPEN_OUTER, false, operator_actor).error_code == &"controller_unpowered", "powered operation must fail during a power outage")
	_check(_execute(world, AirlockState.Action.OPEN_OUTER, true, manual_actor).is_success, "an unlocked door must open with a crowbar without power or electronic access")
	_check(airlock.outer_door_open and actuator.position == 1.0, "manual movement must update pressure and actuator state together")
	_check(_execute(world, AirlockState.Action.CLOSE_OUTER, true, manual_actor).is_success, "manual closing must also work without power")
	actuator.latch_state = &"engaged"
	_check(_execute(world, AirlockState.Action.OPEN_OUTER, true, manual_actor).error_code == &"door_locked", "a crowbar must not silently defeat a physical lock")
	actuator.latch_state = &"released"
	manual_actor.tools_by_capability.clear()
	_check(_execute(world, AirlockState.Action.OPEN_OUTER, true, manual_actor).error_code == &"required_tool_missing", "manual movement requires the real server-context tool capability")
	manual_actor.tools_by_capability[&"tool.pry"] = PackedStringArray(["crowbar-1"])
	device.security_controllers.clear()
	_check(_execute(world, AirlockState.Action.OPEN_OUTER, false, operator_actor).error_code == &"controller_unavailable", "a missing controller disables powered commands")
	_check(_execute(world, AirlockState.Action.OPEN_OUTER, true, manual_actor).is_success, "removing a controller must preserve usable mechanical movement")
	_check(_execute(world, AirlockState.Action.CLOSE_OUTER, true, manual_actor).is_success, "controller-less doors must close manually")
	actuator.mode = &"manual"
	_check(_execute(world, AirlockState.Action.OPEN_OUTER, true, manual_actor).is_success, "a manual drive can work without a powered motor")
	_check(_execute(world, AirlockState.Action.CLOSE_OUTER, true, manual_actor).is_success, "manual drive closing must work")
	actuator.mode = &"jammed"
	_check(_execute(world, AirlockState.Action.OPEN_OUTER, true, manual_actor).error_code == &"actuator_unavailable", "a mechanical jam must still prevent movement")
	actuator.mode = &"manual"
	var chamber := pressure.volumes[PressureSystem.PROTOTYPE_CHAMBER_ID] as PressureVolumeState
	chamber.gas_moles = 100.0
	_check(_execute(world, AirlockState.Action.OPEN_OUTER, true, manual_actor).error_code == &"actuator_force_exceeded", "manual tool force must not overcome arbitrary pressure loads")
	chamber.gas_moles = 0.0
	airlock.inner_door_open = true
	_check(_execute(world, AirlockState.Action.OPEN_OUTER, true, manual_actor).error_code == &"inner_door_open", "manual work must retain the current airlock interlock")
	airlock.inner_door_open = false
	_check(_execute(world, AirlockState.Action.OPEN_VENT, true, manual_actor).error_code == &"manual_action_unsupported", "door tools must not authorize unrelated valve actions")
	world.free()
	if _failures == 0:
		print("Manual airlock operation scenarios passed.")
	quit(0 if _failures == 0 else 1)


func _execute(world: WorldRuntime, action: int, manual: bool, context: AuthenticatedCommandContext) -> ServiceResult:
	var command := AirlockCommand.new()
	command.command_id = world.next_local_request_id()
	command.airlock_id = WorldRuntime.PROTOTYPE_AIRLOCK_ID
	command.action = action
	command.manual_operation = manual
	command.authenticated_context = context
	return command.execute(world)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
