extends SceneTree

## Generates first-party native OpenXR resources; no hardware or vendor plugin needed.
func _initialize() -> void:
	var map := OpenXRActionMap.new()
	var set := OpenXRActionSet.new()
	set.resource_name = "frontier_preview"
	set.localized_name = "Frontier VR preview"
	var actions: Dictionary = {}
	for action_name in ["hand_pose", "aim_pose", "grip", "trigger", "turn", "toggle_seated", "height_up", "height_down"]:
		var action := OpenXRAction.new()
		action.resource_name = action_name
		action.localized_name = action_name.capitalize()
		action.action_type = OpenXRAction.OPENXR_ACTION_POSE if action_name in ["hand_pose", "aim_pose"] else OpenXRAction.OPENXR_ACTION_FLOAT
		if action_name == "turn":
			action.action_type = OpenXRAction.OPENXR_ACTION_VECTOR2
		elif action_name in ["toggle_seated", "height_up", "height_down"]:
			action.action_type = OpenXRAction.OPENXR_ACTION_BOOL
		action.toplevel_paths = PackedStringArray(["/user/hand/left", "/user/hand/right"])
		if action_name == "toggle_seated":
			action.toplevel_paths = PackedStringArray(["/user/hand/left"])
		elif action_name in ["turn", "height_up", "height_down"]:
			action.toplevel_paths = PackedStringArray(["/user/hand/right"])
		set.add_action(action)
		actions[action_name] = action
	var sets: Array[OpenXRActionSet] = [set]
	map.action_sets = sets
	var profiles: Array[OpenXRInteractionProfile] = []
	for profile_name in ["/interaction_profiles/oculus/touch_controller", "/interaction_profiles/khr/simple_controller"]:
		var profile := OpenXRInteractionProfile.new()
		profile.interaction_profile_path = profile_name
		var bindings: Array[OpenXRIPBinding] = []
		for side in ["left", "right"]:
			for action_name in actions:
				if profile_name.ends_with("simple_controller") and action_name not in ["hand_pose", "aim_pose", "trigger"]:
					continue
				if not actions[action_name].toplevel_paths.has("/user/hand/" + side):
					continue
				var suffix: String = "grip/pose" if action_name == "hand_pose" else ("squeeze/value" if action_name == "grip" else "trigger/value")
				if action_name == "aim_pose":
					suffix = "aim/pose"
				if action_name == "turn":
					suffix = "thumbstick"
				elif action_name == "toggle_seated":
					suffix = "x/click"
				elif action_name == "height_up":
					suffix = "a/click"
				elif action_name == "height_down":
					suffix = "b/click"
				if profile_name.ends_with("simple_controller") and action_name == "trigger":
					suffix = "select/click"
				var binding := OpenXRIPBinding.new()
				binding.action = actions[action_name]
				binding.binding_path = "/user/hand/%s/input/%s" % [side, suffix]
				bindings.append(binding)
		profile.bindings = bindings
		profiles.append(profile)
	map.interaction_profiles = profiles
	var result: Error = ResourceSaver.save(map, "res://data/xr/frontier_action_map.tres")
	if result != OK:
		push_error("Failed to save the first-party XR action map: %s" % result)
	else:
		print("Saved first-party Quest-compatible OpenXR action map.")
	quit(0 if result == OK else 1)
