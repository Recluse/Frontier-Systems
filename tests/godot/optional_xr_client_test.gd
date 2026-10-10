extends SceneTree

var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(not OptionalXRLaunchPolicy.requested([], [], false), "desktop must remain the default")
	_check(OptionalXRLaunchPolicy.requested([], ["--vr"], false), "explicit user VR intent must select optional startup")
	_check(OptionalXRLaunchPolicy.requested(["--xr-mode", "on"], [], false), "engine XR launch flag must select optional startup")
	_check(not OptionalXRLaunchPolicy.requested(["--xr-mode", "off"], [], false), "disabled XR must not select VR")
	_check(not OptionalXRLaunchPolicy.requested(["--xr-mode", "on"], ["--vr"], true), "headless host must never create VR presentation")
	_check(not ProjectSettings.get_setting("xr/openxr/enabled"), "project defaults must not require an OpenXR runtime")
	_check(Engine.physics_ticks_per_second == 60, "headset presentation must not change simulation tick rate")
	var map: OpenXRActionMap = load("res://data/xr/frontier_action_map.tres")
	_check(map != null and map.action_sets.size() == 1 and map.interaction_profiles.size() == 2, "pinned first-party action map must load")
	var actions: Dictionary = {}
	for action in map.action_sets[0].actions:
		actions[action.resource_name] = action
	_check(actions.has("hand_pose") and actions["hand_pose"].action_type == OpenXRAction.OPENXR_ACTION_POSE, "controller tracking must bind a pose action")
	_check(actions.has("grip") and actions.has("trigger") and actions["grip"].action_type == OpenXRAction.OPENXR_ACTION_FLOAT, "analogue input checks must have explicit actions")
	var touch_profile: OpenXRInteractionProfile = map.interaction_profiles[0]
	_check(touch_profile.interaction_profile_path == "/interaction_profiles/oculus/touch_controller" and touch_profile.bindings.size() == 12, "Quest-compatible Touch bindings must cover tracking/aim, both hands and comfort inputs")
	var paths: Dictionary = {}
	for binding in touch_profile.bindings:
		_check(not paths.has(binding.binding_path), "a profile input must not have duplicate bindings")
		paths[binding.binding_path] = true
	_check(paths.has("/user/hand/left/input/grip/pose") and paths.has("/user/hand/right/input/trigger/value"), "profile must bind pose and analogue inputs")
	_check(actions.has("aim_pose") and paths.has("/user/hand/right/input/aim/pose"), "pointing must have a dedicated runtime aim pose")
	_check(actions.has("turn") and actions["turn"].action_type == OpenXRAction.OPENXR_ACTION_VECTOR2 and paths.has("/user/hand/right/input/thumbstick"), "snap turn must have a right-stick vector action")
	_check(paths.has("/user/hand/left/input/x/click") and paths.has("/user/hand/right/input/a/click") and paths.has("/user/hand/right/input/b/click"), "seated/height buttons must have explicit bindings")
	var world := WorldRuntime.new()
	root.add_child(world)
	_check(world.start_simulation().is_success, "world must start without XR")
	world.get_node("SimulationRunner").set_physics_process(false)
	var before: String = world.capture_world_snapshot_json().value
	var rig := OptionalXRClient.new()
	root.add_child(rig)
	_check(not rig.try_start(world).is_success and not rig.is_active(), "headless fallback must reject XR output without changing the world")
	_check(not root.use_xr, "fallback must not enable XR viewport output")
	rig.build_preview()
	_check(rig.origin != null and rig.camera != null and rig.controllers.size() == 2, "rig must build native origin/camera/controller nodes")
	_check(rig.camera.get_parent() == rig.origin and rig.controllers[0].get_parent() == rig.origin, "tracked nodes must share one origin")
	_check(rig.controllers[0].pose == &"hand_pose" and rig.controllers[0].tracker == &"/user/hand/left", "rig pose names must match the action map")
	_check(not rig.controllers[0].visible and not rig.preview.character.navigation_enabled(), "untracked controllers and the desktop walker must be inactive")
	_check(rig.aim_controller.get_parent() == rig.origin and rig.aim_controller.pose == &"aim_pose", "right pointer must use the separate aim pose under the shared origin")
	_check(rig.configure_spatial_controls(world).is_success and rig.spatial_panel != null and rig.spatial_pointer != null, "development rig must construct its spatial command adapter")
	_check(not rig.configure_spatial_controls(world).is_success, "spatial controls must not be duplicated")
	var child_count: int = rig.get_child_count()
	rig.build_preview()
	_check(rig.get_child_count() == child_count, "building twice must not duplicate the XR scene")
	_check(world.capture_world_snapshot_json().value == before, "rig construction and fallback must leave canonical world state untouched")
	rig.free()
	world.free()
	if _failures == 0:
		print("Optional XR launch, native rig, action-map and world-isolation scenarios passed.")
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
