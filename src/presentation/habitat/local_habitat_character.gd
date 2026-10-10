extends CharacterBody3D
class_name LocalHabitatCharacter

## Local-only prototype body. No identity, inventory, survival or network authority.
enum CameraMode { FIRST_PERSON, THIRD_PERSON }
const WALK_SPEED: float = 4.0
const RUN_SPEED: float = 7.0
const GRAVITY: float = 3.71
const JUMP_SPEED: float = 2.5
var read_local_keyboard: bool = true
var camera_mode: CameraMode = CameraMode.FIRST_PERSON
var _active: bool = false
var _looking: bool = false
var _axes := Vector2.ZERO
var _jump: bool = false
var _sprint: bool = false
var _pitch: float = 0.0
var _rig: Node3D
var _arm: SpringArm3D
var _camera: Camera3D
var _mesh: MeshInstance3D


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.2
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.8
	var collider := CollisionShape3D.new()
	collider.shape = capsule
	add_child(collider)
	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.3
	body_mesh.height = 1.8
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#6cb8c5")
	_mesh = MeshInstance3D.new()
	_mesh.mesh = body_mesh
	_mesh.material_override = material
	add_child(_mesh)
	_rig = Node3D.new()
	_rig.position.y = 0.7
	add_child(_rig)
	_arm = SpringArm3D.new()
	_arm.collision_mask = 1
	_arm.margin = 0.1
	_rig.add_child(_arm)
	_arm.add_excluded_object(get_rid())
	_camera = Camera3D.new()
	_camera.fov = 75.0
	_arm.add_child(_camera)
	set_camera_mode(CameraMode.FIRST_PERSON)
	set_navigation_enabled(false)


func set_navigation_enabled(enabled: bool) -> void:
	release_controls()
	_active = enabled
	_axes = Vector2.ZERO
	velocity = Vector3.ZERO
	set_physics_process(enabled)
	if _camera != null:
		_camera.current = enabled


func navigation_enabled() -> bool:
	return _active


func set_camera_mode(next_mode: int) -> void:
	if next_mode not in [CameraMode.FIRST_PERSON, CameraMode.THIRD_PERSON]:
		return
	release_controls()
	camera_mode = next_mode as CameraMode
	if _mesh != null:
		_mesh.visible = camera_mode == CameraMode.THIRD_PERSON
	if _arm != null:
		_arm.spring_length = 3.0 if camera_mode == CameraMode.THIRD_PERSON else 0.0


## Local intent hook for keyboard or deterministic fixtures, not remote RPC ingress.
func set_motion_intent(axes: Vector2, jump: bool, sprint: bool = false) -> ServiceResult:
	if not is_finite(axes.x) or not is_finite(axes.y) or absf(axes.x) > 1.0 or absf(axes.y) > 1.0:
		return ServiceResult.failure(&"invalid_local_movement", "Movement axes must be finite and within minus/plus one.")
	_axes = axes.limit_length(1.0)
	_jump = jump
	_sprint = sprint
	return ServiceResult.success()


func _physics_process(delta: float) -> void:
	if not _active:
		return
	if read_local_keyboard:
		var axes := Vector2.ZERO
		if PlayerInputSettings.instance().can_navigate(self):
			axes = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		set_motion_intent(axes, _jump and PlayerInputSettings.instance().can_navigate(self), PlayerInputSettings.instance().can_navigate(self) and Input.is_action_pressed("sprint"))
	var direction: Vector3 = transform.basis * Vector3(_axes.x, 0.0, _axes.y)
	var speed: float = RUN_SPEED if _sprint else WALK_SPEED
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	if not is_on_floor():
		velocity.y -= GRAVITY * clampf(delta, 0.0, 0.1)
	elif _jump:
		velocity.y = JUMP_SPEED
	else:
		velocity.y = 0.0
	_jump = false
	move_and_slide()


func _unhandled_input(event: InputEvent) -> void:
	if _active and PlayerInputSettings.instance().accepts_gameplay_input() and event.is_action_pressed("look"):
		_looking = true
		PlayerInputSettings.instance().request_capture(self)
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if not _looking:
		return
	if event.is_action_released("look"):
		release_controls()
	elif event.is_action_pressed("release_cursor"):
		release_controls()
	elif not PlayerInputSettings.instance().can_navigate(self):
		return
	elif event.is_action_pressed("jump") and not event.is_echo():
		_jump = true
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		rotation.y = fposmod(rotation.y - event.relative.x * PlayerInputSettings.instance().sensitivity, TAU)
		_pitch = clampf(_pitch - event.relative.y * PlayerInputSettings.instance().sensitivity, -1.3, 1.3)
		_rig.rotation.x = _pitch


func release_controls() -> void:
	PlayerInputSettings.instance().release_capture(self)
	_looking = false
	_jump = false
	_axes = Vector2.ZERO
	_sprint = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		release_controls()


func _exit_tree() -> void:
	release_controls()
