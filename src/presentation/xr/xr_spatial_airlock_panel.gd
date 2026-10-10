extends Node3D
class_name XRSpatialAirlockPanel

## Development spatial UI over the existing queued airlock command boundary.
const BUTTON_LAYER: int = 8
const BUTTONS: Dictionary = {
	"open_inner": ["Open inner", AirlockState.Action.OPEN_INNER], "close_inner": ["Close inner", AirlockState.Action.CLOSE_INNER],
	"open_outer": ["Open outer", AirlockState.Action.OPEN_OUTER], "close_outer": ["Close outer", AirlockState.Action.CLOSE_OUTER],
	"open_equalization": ["Equalize", AirlockState.Action.OPEN_EQUALIZATION], "close_equalization": ["Stop equalize", AirlockState.Action.CLOSE_EQUALIZATION],
	"open_vent": ["Vent", AirlockState.Action.OPEN_VENT], "close_vent": ["Stop vent", AirlockState.Action.CLOSE_VENT]
}
var _world: WorldRuntime
var _configured: bool = false
var _buttons: Dictionary = {}
var _pending: String = ""
var _hovered: String = ""
var _feedback: Label3D
var _readings: Label3D
var _elapsed: float = 0.0
var _nonce: String = str(Time.get_ticks_usec())


func configure(world: WorldRuntime) -> ServiceResult:
	if _configured or not OS.is_debug_build() or not is_instance_valid(world):
		return ServiceResult.failure(&"xr_panel_unavailable", "Spatial fixture controls require one local development world.")
	_configured = true
	_world = world
	_world.command_completed.connect(_on_command_completed)
	_world.tree_exiting.connect(_on_world_closed)
	_box(self, Vector3(1.5, 1.6, 0.025), Color("#172431"))
	var backing := StaticBody3D.new()
	backing.collision_layer = BUTTON_LAYER
	backing.collision_mask = 0
	add_child(backing)
	_shape(backing, Vector3(1.5, 1.6, 0.025))
	_readings = _label(self, "Airlock controls (development)", Vector3(0, 0.62, 0.03), 26)
	var index: int = 0
	for id in BUTTONS:
		var area := Area3D.new()
		area.name = id
		area.position = Vector3(-0.36 if index % 2 == 0 else 0.36, 0.3 - float(index / 2) * 0.24, 0.04)
		area.collision_layer = BUTTON_LAYER
		area.collision_mask = 0
		area.monitoring = false
		area.monitorable = false
		add_child(area)
		_shape(area, Vector3(0.65, 0.18, 0.04))
		var mesh: MeshInstance3D = _box(area, Vector3(0.65, 0.18, 0.04), Color("#315c71"))
		_label(area, BUTTONS[id][0], Vector3(0, 0, 0.025), 23)
		_buttons[id] = {"area": area, "material": mesh.material_override}
		index += 1
	_feedback = _label(self, "Point and release/press trigger to select", Vector3(0, -0.65, 0.03), 20)
	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_feedback.width = 1000
	refresh()
	return ServiceResult.success()


func is_available() -> bool:
	return is_instance_valid(_world) and OS.is_debug_build()


func button_id_for(collider: Object) -> String:
	if not is_instance_valid(collider):
		return ""
	for id in _buttons:
		if _buttons[id]["area"] == collider:
			return id
	return ""


func highlight(button_id: String) -> void:
	if _hovered == button_id:
		return
	_hovered = button_id if _buttons.has(button_id) else ""
	for id in _buttons:
		_buttons[id]["material"].albedo_color = Color("#b88b35") if id == _hovered else Color("#315c71")


func submit(button_id: String) -> ServiceResult:
	if not is_available() or not BUTTONS.has(button_id) or not _pending.is_empty():
		return ServiceResult.failure(&"xr_panel_unavailable", "A live registered control without a pending command is required.")
	var command := AirlockCommand.new()
	command.command_id = StringName("xr-panel-%s-%s" % [_nonce, _world.next_local_request_id()])
	command.source = &"xr-spatial-development"
	command.airlock_id = WorldRuntime.PROTOTYPE_AIRLOCK_ID
	command.action = BUTTONS[button_id][1]
	command.authenticated_context = AuthenticatedCommandContext.for_local_development(&"local-xr-airlock", _world.world_id, _world.region_id)
	var queued: ServiceResult = _world.enqueue_command(command)
	if queued.is_success:
		_pending = String(command.command_id)
		_feedback.text = "Queued: " + BUTTONS[button_id][0]
	else:
		_feedback.text = queued.message
	return queued


func _on_command_completed(command: SimulationCommand, result: ServiceResult) -> void:
	if not command is AirlockCommand or _pending.is_empty() or String(command.command_id) != _pending:
		return
	_pending = ""
	_feedback.text = "Applied" if result.is_success else "Rejected: " + result.message
	refresh()


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= 0.1:
		_elapsed = 0.0
		refresh()


func refresh() -> void:
	if not is_available():
		return
	var observed: ServiceResult = _world.pressure_snapshot()
	if observed.is_success:
		var state: Dictionary = observed.value
		_readings.text = "Airlock (development)\nHabitat %.1f | Chamber %.1f kPa\nInner %s | Outer %s" % [state["pressure_sensors"]["habitat"]["pressure_kpa_absolute"], state["pressure_sensors"]["chamber"]["pressure_kpa_absolute"], "open" if state["inner_door_open"] else "closed", "open" if state["outer_door_open"] else "closed"]


func _on_world_closed() -> void:
	_world = null
	_pending = ""
	highlight("")
	_feedback.text = "World closed"


static func _shape(parent: CollisionObject3D, size: Vector3) -> void:
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	parent.add_child(collider)


static func _box(parent: Node3D, size: Vector3, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	mesh.material_override = material
	parent.add_child(mesh)
	return mesh


static func _label(parent: Node3D, text: String, location: Vector3, font_size: int) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.position = location
	label.font_size = font_size
	label.pixel_size = 0.0011
	parent.add_child(label)
	return label
