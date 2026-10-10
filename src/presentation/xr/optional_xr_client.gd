extends Node3D
class_name OptionalXRClient

## Optional tracked presentation only. No input grants world or inventory authority.
var origin: XROrigin3D
var camera: XRCamera3D
var controllers: Array[XRController3D] = []
var aim_controller: XRController3D
var spatial_panel: XRSpatialAirlockPanel
var spatial_pointer: XRSpatialPointer
var preview: ProceduralHabitatPreview
var _world: WorldRuntime
var _active: bool = false
var _status: Label3D
var _hand_materials: Array[StandardMaterial3D] = []
var _elapsed: float = 0.0
var _built: bool = false
var _xr_interface: OpenXRInterface
var _comfort: XRComfortPolicy = XRComfortPolicy.create_default()
var _comfort_feedback: String = ""


func try_start(world: WorldRuntime) -> ServiceResult:
	if _active or _built or not is_instance_valid(world) or DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server"):
		return ServiceResult.failure(&"xr_unavailable", "XR presentation requires a graphical client and one configured world.")
	var interface := XRServer.find_interface("OpenXR") as OpenXRInterface
	if interface == null or not interface.is_initialized():
		return ServiceResult.failure(&"xr_unavailable", "OpenXR did not initialize. Start SteamVR and launch with --xr-mode on before -- --vr.")
	_world = world
	_xr_interface = interface
	var preferences: ServiceResult = XRComfortPolicy.load_preferences()
	if preferences.is_success:
		_comfort = preferences.value
	else:
		_comfort_feedback = "Invalid local preferences; using defaults."
	build_preview()
	XRServer.world_scale = 1.0
	get_viewport().use_xr = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_active = true
	interface.pose_recentered.connect(_on_pose_recentered)
	_world.tree_exiting.connect(_on_world_closed)
	return ServiceResult.success()


## Also usable for headset-free structural checks; this does not activate XR output.
func build_preview() -> void:
	if _built:
		return
	_built = true
	preview = ProceduralHabitatPreview.new()
	add_child(preview)
	preview.camera.current = false
	preview.camera.set_process_unhandled_input(false)
	preview.character.set_navigation_enabled(false)
	preview.character.read_local_keyboard = false
	preview.character.visible = false
	origin = XROrigin3D.new()
	origin.name = "XROrigin"
	origin.position = Vector3(-6.0, 0.0, 2.0)
	var settings: Dictionary = _comfort.to_record()
	origin.position.y = float(settings["seated_height_offset_mm"]) / 1000.0 if settings["seated_mode"] else 0.0
	add_child(origin)
	camera = XRCamera3D.new()
	camera.name = "HeadsetCamera"
	origin.add_child(camera)
	camera.make_current()
	for side in ["left", "right"]:
		var controller := XRController3D.new()
		controller.name = "%sController" % side.capitalize()
		controller.tracker = StringName("/user/hand/" + side)
		controller.pose = &"hand_pose"
		origin.add_child(controller)
		controllers.append(controller)
		var mesh := MeshInstance3D.new()
		var shape := BoxMesh.new()
		shape.size = Vector3(0.06, 0.06, 0.12)
		mesh.mesh = shape
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("#52a3ba")
		mesh.material_override = material
		_hand_materials.append(material)
		controller.add_child(mesh)
		controller.visible = false
	aim_controller = XRController3D.new()
	aim_controller.name = "RightAim"
	aim_controller.tracker = &"/user/hand/right"
	aim_controller.pose = &"aim_pose"
	origin.add_child(aim_controller)
	if is_instance_valid(_world):
		configure_spatial_controls(_world)
	_status = Label3D.new()
	_status.name = "XRStatusBoard"
	_status.position = Vector3(-6.0, 1.4, -0.5)
	_status.font_size = 32
	_status.pixel_size = 0.0015
	_status.text = "Frontier Systems — optional VR preview\n" + _spatial_status() + "\nNo body locomotion or object handling yet"
	add_child(_status)


func _process(delta: float) -> void:
	if not _active or not is_instance_valid(_world):
		return
	var labels: PackedStringArray = []
	var focused: bool = _xr_interface != null and _xr_interface.get_session_state() == OpenXRInterface.SESSION_STATE_FOCUSED
	for index in range(controllers.size()):
		var controller: XRController3D = controllers[index]
		var tracked: bool = controller.get_has_tracking_data()
		controller.visible = tracked
		var grip: float = clampf(controller.get_float("grip"), 0.0, 1.0) if tracked and focused else 0.0
		var trigger: float = clampf(controller.get_float("trigger"), 0.0, 1.0) if tracked and focused else 0.0
		_hand_materials[index].albedo_color = Color("#52a3ba").lerp(Color("#e8c76a"), grip)
		labels.append("%s: %s | grip %.2f | trigger %.2f" % [controller.name, "tracked" if tracked else "not tracked", grip, trigger])
	consume_comfort_input({"schema_version": 1, "turn_axis": controllers[1].get_vector2("turn").x,
		"session_focused": focused, "left_tracked": controllers[0].get_has_tracking_data(), "right_tracked": controllers[1].get_has_tracking_data(),
		"seated_pressed": controllers[0].is_button_pressed("toggle_seated"), "height_up_pressed": controllers[1].is_button_pressed("height_up"), "height_down_pressed": controllers[1].is_button_pressed("height_down")})
	if is_instance_valid(spatial_pointer):
		spatial_pointer.stage_input(focused, aim_controller.get_has_tracking_data(), controllers[1].get_float("trigger"), aim_controller.global_position, -aim_controller.global_transform.basis.z)
	_elapsed += delta
	if _elapsed >= 0.1:
		_elapsed = 0.0
		var settings: Dictionary = _comfort.to_record()
		_status.text = "Frontier Systems — VR preview\n" + "\n".join(labels) + "\n" + _spatial_status() + "\nRight stick: snap turn | X: seated | A/B: height\n%s | seated offset %d mm | snap %d°\n%s\nNo body locomotion or object handling yet" % ["Seated" if settings["seated_mode"] else "Standing", settings["seated_height_offset_mm"], settings["snap_turn_degrees"], _comfort_feedback]
		var observed: ServiceResult = _world.pressure_snapshot()
		if observed.is_success:
			preview.observe_snapshot(observed.value)


func is_active() -> bool:
	return _active


func _spatial_status() -> String:
	return "Right trigger: development airlock panel" if is_instance_valid(spatial_panel) and spatial_panel.is_available() else "Development airlock panel unavailable"


func configure_spatial_controls(world: WorldRuntime) -> ServiceResult:
	if not _built or spatial_panel != null:
		return ServiceResult.failure(&"xr_panel_configuration", "Build one rig before configuring its spatial controls.")
	spatial_panel = XRSpatialAirlockPanel.new()
	spatial_panel.position = Vector3(-4.2, 1.35, -0.4)
	add_child(spatial_panel)
	var configured: ServiceResult = spatial_panel.configure(world)
	if not configured.is_success:
		spatial_panel.queue_free()
		spatial_panel = null
		return configured
	spatial_pointer = XRSpatialPointer.new()
	add_child(spatial_pointer)
	return spatial_pointer.configure(spatial_panel)


func _on_pose_recentered() -> void:
	if _active:
		XRServer.center_on_hmd(XRServer.RESET_BUT_KEEP_TILT, true)
		_comfort.reset_input()
		if is_instance_valid(spatial_pointer):
			spatial_pointer.reset_input()


## Presentation-only transform helper. Native input is gated by the comfort policy.
func apply_snap_turn(yaw_degrees: int) -> ServiceResult:
	if origin == null or camera == null or abs(yaw_degrees) != int(_comfort.to_record()["snap_turn_degrees"]) or yaw_degrees == 0:
		return ServiceResult.failure(&"xr_comfort_unavailable", "A configured snap angle and built XR origin are required.")
	var pivot: Vector3 = camera.global_position
	if not pivot.is_finite():
		_comfort.reset_input()
		return ServiceResult.failure(&"xr_comfort_unavailable", "The headset pivot must be finite.")
	origin.rotate_y(deg_to_rad(float(yaw_degrees)))
	var after: Vector3 = camera.global_position
	origin.global_position += Vector3(pivot.x - after.x, 0.0, pivot.z - after.z)
	return ServiceResult.success()


func apply_comfort_settings(record: Dictionary, persist: bool = true, path: String = XRComfortPolicy.DEFAULT_PATH) -> ServiceResult:
	var parsed: ServiceResult = XRComfortPolicy.from_record(record)
	if not parsed.is_success:
		return parsed
	_comfort = parsed.value
	if origin != null:
		origin.position.y = float(record["seated_height_offset_mm"]) / 1000.0 if record["seated_mode"] else 0.0
	var saved: ServiceResult = _comfort.save_preferences(path) if persist else ServiceResult.success()
	_comfort_feedback = "Comfort settings applied." if saved.is_success else "Applied; local preference save failed."
	return ServiceResult.success({"preferences_saved": persist and saved.is_success, "warning": "" if saved.is_success else saved.message})


## Pure input observations can also exercise the presentation adapter without a headset.
func consume_comfort_input(observation: Dictionary, persist: bool = true) -> ServiceResult:
	if origin == null or camera == null:
		_comfort.reset_input()
		return ServiceResult.failure(&"xr_comfort_unavailable", "Build the XR rig before applying comfort inputs.")
	var sampled: ServiceResult = _comfort.sample_input(observation)
	if not sampled.is_success:
		return sampled
	if sampled.value["yaw_degrees"] != 0:
		var turned: ServiceResult = apply_snap_turn(sampled.value["yaw_degrees"])
		if not turned.is_success:
			return turned
	var settings: Dictionary = _comfort.to_record()
	if sampled.value["toggle_seated"]:
		settings["seated_mode"] = not settings["seated_mode"]
	settings["seated_height_offset_mm"] = clampi(int(settings["seated_height_offset_mm"]) + int(sampled.value["height_delta_mm"]), 0, 1000)
	if settings != _comfort.to_record():
		return apply_comfort_settings(settings, persist)
	return sampled


func _on_world_closed() -> void:
	_active = false
	_world = null
	_comfort.reset_input()
	if is_instance_valid(spatial_pointer):
		spatial_pointer.reset_input()
	for controller in controllers:
		controller.visible = false
	if _status != null:
		_status.text = "World closed"
