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
	if not current:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_looking = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and mode == Mode.OVERVIEW:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_radius = clampf(_radius + (-2.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 2.0), 5.0, 50.0)
			_update_overview()
			get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if not _looking:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed:
		_release_mouse()
	elif event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed:
		_release_mouse()
	elif event is InputEventMouseMotion:
		_yaw = fposmod(_yaw - event.relative.x * 0.003, TAU)
		_pitch = clampf(_pitch - event.relative.y * 0.003, -1.3, 1.3)
		if mode == Mode.OVERVIEW:
			_update_overview()
		else:
			rotation = Vector3(_pitch, _yaw, 0.0)


func _process(delta: float) -> void:
	if not _looking or mode != Mode.FREE_LOOK:
		return
	var movement := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W): movement -= transform.basis.z
	if Input.is_physical_key_pressed(KEY_S): movement += transform.basis.z
	if Input.is_physical_key_pressed(KEY_A): movement -= transform.basis.x
	if Input.is_physical_key_pressed(KEY_D): movement += transform.basis.x
	if Input.is_physical_key_pressed(KEY_Q): movement -= Vector3.UP
	if Input.is_physical_key_pressed(KEY_E): movement += Vector3.UP
	var speed: float = 15.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 6.0
	position += movement.normalized() * speed * clampf(delta, 0.0, 0.1)


func _update_overview() -> void:
	position = PIVOT + Vector3(sin(_yaw) * cos(_pitch), -sin(_pitch), cos(_yaw) * cos(_pitch)) * _radius
	look_at(PIVOT)


func _release_mouse() -> void:
	if _looking:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_looking = false


func _exit_tree() -> void:
	_release_mouse()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_release_mouse()
