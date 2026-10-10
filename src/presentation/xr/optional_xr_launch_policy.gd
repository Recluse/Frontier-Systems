extends RefCounted
class_name OptionalXRLaunchPolicy


static func requested(engine_arguments: PackedStringArray, user_arguments: PackedStringArray, headless: bool) -> bool:
	if headless:
		return false
	if user_arguments.has("--vr"):
		return true
	for index in range(engine_arguments.size() - 1):
		if engine_arguments[index] == "--xr-mode" and engine_arguments[index + 1] == "on":
			return true
	return false
