extends Camera3D
class_name HabitatInspectionCamera

## Local inspection controls, not an authoritative player body or vehicle.
enum Mode { OVERVIEW, FREE_LOOK }
const PIVOT := Vector3(-6.0, 1.0, 0.0)
var mode: Mode = Mode.OVERVIEW
var _looking: bool = false
var _yaw: float = 0.7
var _pitch: float = -0.38
var _radius: float = 26.0


func _ready() -> void:
	current = true
	fov = 70.0
	set_mode(Mode.OVERVIEW)


func set_mode(next_mode: int) -> void:
	if next_mode not in [Mode.OVERVIEW, Mode.FREE_LOOK]:
		return
	_release_mouse()
	mode = next_mode as Mode
	if mode == Mode.OVERVIEW:
		_yaw = 0.7
		_pitch = -0.38
		_radius = 26.0
		_update_overview()
	else:
		position = Vector3(-4.0, 1.7, 0.0)
		_yaw = -PI / 2.0
		_pitch = 0.0
		rotation = Vector3(_pitch, _yaw, 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if not current or not PlayerInputSettings.instance().accepts_gameplay_input():
		return
	if event.is_action_pressed("look"):
		_looking = true
		PlayerInputSettings.instance().request_capture(self)
		get_viewport().set_input_as_handled()
	elif mode == Mode.OVERVIEW:
		if event.is_action_pressed("zoom_in") or event.is_action_pressed("zoom_out"):
			_radius = clampf(_radius + (-2.0 if event.is_action_pressed("zoom_in") else 2.0), 5.0, 50.0)
			_update_overview()
			get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if not _looking:
		return
	if event.is_action_released("look"):
		_release_mouse()
	elif event.is_action_pressed("release_cursor"):
		_release_mouse()
	elif event is InputEventMouseMotion and PlayerInputSettings.instance().can_navigate(self):
		_yaw = fposmod(_yaw - event.relative.x * PlayerInputSettings.instance().sensitivity, TAU)
		_pitch = clampf(_pitch - event.relative.y * PlayerInputSettings.instance().sensitivity, -1.3, 1.3)
		if mode == Mode.OVERVIEW:
			_update_overview()
		else:
			rotation = Vector3(_pitch, _yaw, 0.0)


func _process(delta: float) -> void:
	if not PlayerInputSettings.instance().can_navigate(self) or mode != Mode.FREE_LOOK:
		return
	var movement := Vector3.ZERO
	if Input.is_action_pressed("move_forward"): movement -= transform.basis.z
	if Input.is_action_pressed("move_back"): movement += transform.basis.z
	if Input.is_action_pressed("move_left"): movement -= transform.basis.x
	if Input.is_action_pressed("move_right"): movement += transform.basis.x
	if Input.is_action_pressed("fly_down"): movement -= Vector3.UP
	if Input.is_action_pressed("fly_up"): movement += Vector3.UP
	var speed: float = 15.0 if Input.is_action_pressed("sprint") else 6.0
	position += movement.normalized() * speed * clampf(delta, 0.0, 0.1)


func _update_overview() -> void:
	position = PIVOT + Vector3(sin(_yaw) * cos(_pitch), -sin(_pitch), cos(_yaw) * cos(_pitch)) * _radius
	look_at(PIVOT)


func _release_mouse() -> void:
	PlayerInputSettings.instance().release_capture(self)
	_looking = false


func _exit_tree() -> void:
	_release_mouse()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_release_mouse()
