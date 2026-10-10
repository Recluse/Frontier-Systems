extends Node
class_name LocalInventoryBodyAdapter

## Opt-in debug bridge from local capsule pose to queued logical inventory movement.
const SAMPLE_SECONDS: float = 0.1
var _world: WorldRuntime
var _character: LocalHabitatCharacter
var _origin: Vector3
var _enabled: bool = false
var _observe_inactive_character: bool = false
var _elapsed: float = 0.0
var _pending_id: String = ""
var _pending_position: Array = []
var _last_position: Array = []
var _nonce: String = str(Time.get_ticks_usec())


func configure(world: WorldRuntime, character: LocalHabitatCharacter, origin: Vector3, observe_inactive_character: bool = false) -> ServiceResult:
	if _world != null or not is_instance_valid(world) or not is_instance_valid(character) or not origin.is_finite():
		return ServiceResult.failure(&"inventory_body_adapter_configuration", "Configure one live world/capsule and finite display origin.")
	_world = world
	_character = character
	_origin = origin
	_observe_inactive_character = observe_inactive_character
	_world.command_completed.connect(_on_completed)
	return ServiceResult.success()


func set_enabled(enabled: bool) -> void:
	_enabled = enabled and OS.is_debug_build()
	_elapsed = 0.0
	if _enabled:
		_last_position = []


func _process(delta: float) -> void:
	if not _enabled or not is_instance_valid(_world) or not is_instance_valid(_character) or (not _observe_inactive_character and not _character.navigation_enabled()):
		return
	_elapsed += delta
	if _elapsed < SAMPLE_SECONDS:
		return
	_elapsed = 0.0
	sample()


func sample() -> ServiceResult:
	if not _enabled or not is_instance_valid(_world) or not is_instance_valid(_character) or (not _observe_inactive_character and not _character.navigation_enabled()) or not _pending_id.is_empty():
		return ServiceResult.failure(&"inventory_body_adapter_idle", "The bridge is disabled, inactive or awaiting acknowledgement.")
	var point: Vector3 = (_character.position - _origin) * 1000.0
	if not point.is_finite():
		return ServiceResult.failure(&"invalid_inventory_body_pose", "The local pose must be finite.")
	for coordinate in [point.x, point.y, point.z]:
		if absf(coordinate) > InventorySpatialMath.MAX_COORDINATE:
			return ServiceResult.failure(&"invalid_inventory_body_pose", "The local pose exceeds region bounds.")
	var position: Array = [roundi(point.x), roundi(point.y), roundi(point.z)]
	if position == _last_position:
		return ServiceResult.success()
	var command := InventoryDevelopmentCommand.new()
	command.command_id = StringName("inventory-pose-%s-%s" % [_nonce, _world.next_local_request_id()])
	command.authenticated_context = AuthenticatedCommandContext.for_local_development(&"local-inventory-actor", _world.world_id, _world.region_id)
	command.operation = "move_to"
	command.payload = {"position_millimetres": position}
	var queued: ServiceResult = _world.enqueue_command(command)
	if queued.is_success:
		_pending_id = String(command.command_id)
		_pending_position = position
	return queued


func _on_completed(command: SimulationCommand, result: ServiceResult) -> void:
	if String(command.command_id) != _pending_id:
		return
	if result.is_success:
		_last_position = _pending_position.duplicate()
	_pending_id = ""
	_pending_position = []
