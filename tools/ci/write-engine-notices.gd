extends SceneTree

## Retain the pinned export engine's bundled software license/copyright notices.
func _initialize() -> void:
	var target: String = "res://var/ci/engine-notices.txt"
	DirAccess.make_dir_recursive_absolute("res://var/ci")
	var file: FileAccess = FileAccess.open(target, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write engine notices.")
		quit(1)
		return
	file.store_string("Godot Engine\n\n" + Engine.get_license_text() + "\n\n")
	for entry in Engine.get_copyright_info():
		file.store_string(String(entry["name"]) + "\n")
		for part in entry["parts"]:
			for notice in part["copyright"]: file.store_string(String(notice) + "\n")
			file.store_string("License: " + String(part["license"]) + "\n")
		file.store_string("\n")
	for name in Engine.get_license_info():
		file.store_string(String(name) + "\n" + String(Engine.get_license_info()[name]) + "\n\n")
	file.close()
	quit(0)
