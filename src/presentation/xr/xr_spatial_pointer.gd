extends Node3D
class_name XRSpatialPointer

## Bounded client ray query in physics frames. Never grants gameplay authority.
const MAX_DISTANCE_M: float = 5.0
const MAX_SAMPLE_AGE_S: float = 0.25
var _panel: XRSpatialAirlockPanel
var _sample: Dictionary = {}
var _sample_time_usec: int = 0
var _armed: bool = false
var _beam: MeshInstance3D
var _queries: int = 0
var _selections: int = 0


func configure(panel: XRSpatialAirlockPanel) -> ServiceResult:
	if _panel != null or not is_instance_valid(panel):
		return ServiceResult.failure(&"xr_pointer_configuration", "Configure one spatial panel per pointer.")
	_panel = panel
	_beam = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.004, 0.004, 1.0)
	_beam.mesh = box
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("#e8c76a")
	_beam.material_override = material
	add_child(_beam)
	_beam.visible = false
	return ServiceResult.success()


func stage_input(focused: bool, tracked: bool, trigger: float, ray_from: Vector3, direction: Vector3) -> ServiceResult:
	if not is_finite(trigger) or trigger < 0.0 or trigger > 1.0 or not ray_from.is_finite() or ray_from.length() > 1000000.0 or not direction.is_finite() or direction.length_squared() < 0.000001 or direction.length_squared() > 4.0:
		_sample = {}
		_armed = false
		return ServiceResult.failure(&"invalid_xr_pointer", "Pointer input must have finite bounded values and a direction.")
	_sample = {"focused": focused, "tracked": tracked, "trigger": trigger, "from": ray_from, "direction": direction.normalized()}
	_sample_time_usec = Time.get_ticks_usec()
	return ServiceResult.success()


func _physics_process(_delta: float) -> void:
	var stale: bool = Time.get_ticks_usec() - _sample_time_usec > int(MAX_SAMPLE_AGE_S * 1000000.0)
	if not is_instance_valid(_panel) or not _panel.is_available() or _sample.is_empty() or stale or not _sample["focused"] or not _sample["tracked"]:
		_armed = false
		if _beam != null:
			_beam.visible = false
		if is_instance_valid(_panel):
			_panel.highlight("")
		return
	var ray_from: Vector3 = _sample["from"]
	var direction: Vector3 = _sample["direction"]
	var end: Vector3 = ray_from + direction * MAX_DISTANCE_M
	var query := PhysicsRayQueryParameters3D.create(ray_from, end, 1 | XRSpatialAirlockPanel.BUTTON_LAYER)
	query.collide_with_areas = true
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	_queries = mini(_queries + 1, 1000000000)
	var id: String = _panel.button_id_for(hit.get("collider"))
	_panel.highlight(id)
	if not hit.is_empty():
		end = hit["position"]
	var distance: float = ray_from.distance_to(end)
	_beam.visible = distance > 0.00001
	if _beam.visible:
		var up: Vector3 = Vector3.RIGHT if absf(direction.dot(Vector3.UP)) > 0.999 else Vector3.UP
		_beam.look_at_from_position((ray_from + end) * 0.5, end, up)
		_beam.scale = Vector3(1.0, 1.0, distance)
	if float(_sample["trigger"]) <= 0.25:
		_armed = true
	elif _armed and float(_sample["trigger"]) >= 0.75:
		_armed = false
		if not id.is_empty() and _panel.submit(id).is_success:
			_selections = mini(_selections + 1, 1000000000)


func profiling_counters() -> Dictionary:
	return {"ray_queries": _queries, "queued_selections": _selections}


func reset_input() -> void:
	_sample = {}
	_armed = false
	if _beam != null:
		_beam.visible = false
	if is_instance_valid(_panel):
		_panel.highlight("")
