extends SimulationCommand
class_name AirlockCommand

## Server-side intent to operate one airlock door or valve.

var airlock_id: StringName = &""
var action: int = AirlockState.Action.OPEN_INNER
## Manual movement uses physical latch/tool checks instead of credential access.
var manual_operation: bool = false


func validate(simulation_context: Node) -> ServiceResult:
	var pressure_system := _pressure_system(simulation_context)
	if pressure_system == null:
		return ServiceResult.failure(&"pressure_system_unavailable", "The pressure system is unavailable.")
	if authenticated_context == null:
		return ServiceResult.failure(&"permission_denied", "An authenticated principal is required to operate this airlock.")
	if manual_operation and _target_actuator_id() == &"":
		return ServiceResult.failure(&"manual_action_unsupported", "Manual operation is supported only for airlock doors.")
	if not manual_operation and not authenticated_context.has_permission("airlock.operate"):
		var target_id: StringName = _target_actuator_id()
		var is_closing: bool = action == AirlockState.Action.CLOSE_INNER or action == AirlockState.Action.CLOSE_OUTER
		var permission_access_system := _access_system(simulation_context)
		if (
			target_id == &""
			or permission_access_system == null
			or not permission_access_system.actor_can_control(airlock_id, target_id, authenticated_context.principal_id, is_closing)
		):
			return ServiceResult.failure(&"permission_denied", "The authenticated principal lacks normal airlock access and has no active actuator-specific bypass.")
	var physical_target_id: StringName = _target_actuator_id()
	if physical_target_id != &"":
		var actuator_access_system := _access_system(simulation_context)
		if actuator_access_system == null:
			return ServiceResult.failure(&"access_system_unavailable", "The access-control system is unavailable.")
		var pressure_snapshot: ServiceResult = pressure_system.airlock_snapshot(airlock_id)
		if not pressure_snapshot.is_success:
			return pressure_snapshot
		var pressure_key: String = "inner_pressure_difference_kpa" if physical_target_id == _target_actuator_id(AirlockState.Action.OPEN_INNER) else "outer_pressure_difference_kpa"
		var pressure_difference: float = float(pressure_snapshot.value.get(pressure_key, -1.0))
		var physical_check: ServiceResult = actuator_access_system.validate_door_actuation(
			airlock_id,
			physical_target_id,
			action == AirlockState.Action.OPEN_INNER or action == AirlockState.Action.OPEN_OUTER,
			pressure_difference,
			manual_operation,
			authenticated_context
		)
		if not physical_check.is_success:
			return physical_check
	return pressure_system.validate_airlock_action(airlock_id, action)


func apply(simulation_context: Node) -> ServiceResult:
	var pressure_system := _pressure_system(simulation_context)
	if pressure_system == null:
		return ServiceResult.failure(&"pressure_system_unavailable", "The pressure system is unavailable.")
	var result: ServiceResult = pressure_system.apply_airlock_action(airlock_id, action)
	if not result.is_success:
		return result
	var access_system := _access_system(simulation_context)
	if access_system != null:
		if action == AirlockState.Action.OPEN_INNER or action == AirlockState.Action.CLOSE_INNER:
			access_system.update_actuator_position(airlock_id, _target_actuator_id(AirlockState.Action.OPEN_INNER), action == AirlockState.Action.OPEN_INNER)
		elif action == AirlockState.Action.OPEN_OUTER or action == AirlockState.Action.CLOSE_OUTER:
			access_system.update_actuator_position(airlock_id, _target_actuator_id(AirlockState.Action.OPEN_OUTER), action == AirlockState.Action.OPEN_OUTER)
	return result


func _pressure_system(simulation_context: Node) -> PressureSystem:
	var world_runtime := simulation_context as WorldRuntime
	if world_runtime == null:
		return null
	return world_runtime.get_simulation_system(PressureSystem.SYSTEM_ID) as PressureSystem


func _access_system(simulation_context: Node) -> AccessControlSystem:
	var world_runtime := simulation_context as WorldRuntime
	if world_runtime == null:
		return null
	return world_runtime.get_simulation_system(AccessControlSystem.SYSTEM_ID) as AccessControlSystem


func _target_actuator_id(action_override: int = -1) -> StringName:
	var target_action: int = action if action_override < 0 else action_override
	if target_action == AirlockState.Action.OPEN_INNER or target_action == AirlockState.Action.CLOSE_INNER:
		return StringName("%s-inner-door" % airlock_id)
	if target_action == AirlockState.Action.OPEN_OUTER or target_action == AirlockState.Action.CLOSE_OUTER:
		return StringName("%s-outer-door" % airlock_id)
	return &""
