extends RefCounted
class_name LocalWorldSaveStore

## Platform-neutral two-slot checkpoints. Invoke writes on a worker, never a tick.
const MAX_BYTES: int = 16777216


static func read_latest(directory: String) -> ServiceResult:
	var best: Dictionary = {}
	var found: bool = false
	for slot in ["a", "b"]:
		var path: String = directory.path_join("world-%s.json" % slot)
		if not FileAccess.file_exists(path):
			continue
		found = true
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null or file.get_length() > MAX_BYTES:
			continue
		var parser := JSON.new()
		if parser.parse(file.get_as_text()) != OK:
			continue
		var value: Variant = parser.data
		if typeof(value) != TYPE_DICTIONARY or not ControlContractValidation.has_exact_fields(value, PackedStringArray(["schema_version", "sequence", "snapshot_json", "sha256"])) or not ControlContractValidation.is_integer(value.get("schema_version"), 1, 1) or not ControlContractValidation.is_integer(value.get("sequence"), 1, 9007199254740000) or typeof(value.get("snapshot_json")) != TYPE_STRING or typeof(value.get("sha256")) != TYPE_STRING:
			continue
		if value["snapshot_json"].to_utf8_buffer().size() > MAX_BYTES / 2 or value["snapshot_json"].sha256_text() != value["sha256"] or not WorldSnapshot.from_json(value["snapshot_json"]).is_success:
			continue
		if best.is_empty() or int(value["sequence"]) > int(best["sequence"]):
			best = value
	if best.is_empty() and found:
		return ServiceResult.failure(&"save_corrupt", "No structurally valid world checkpoint remains; preserve the files for recovery.")
	return ServiceResult.success(best)


static func write_checkpoint(directory: String, sequence: int, snapshot_json: String) -> ServiceResult:
	if directory.is_empty() or sequence < 1 or sequence > 9007199254740000 or snapshot_json.to_utf8_buffer().size() > MAX_BYTES / 2:
		return ServiceResult.failure(&"save_bounds", "Checkpoint exceeds its identity, sequence or byte bounds.")
	var absolute: String = ProjectSettings.globalize_path(directory)
	if DirAccess.make_dir_recursive_absolute(absolute) != OK:
		return ServiceResult.failure(&"save_directory", "Cannot create the configured save directory.")
	var path: String = absolute.path_join("world-%s.json" % ("a" if sequence % 2 == 0 else "b"))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return ServiceResult.failure(&"save_open", "Cannot open the checkpoint slot.")
	file.store_string(JSON.stringify({"schema_version": 1, "sequence": sequence, "snapshot_json": snapshot_json, "sha256": snapshot_json.sha256_text()}))
	file.flush()
	var error: Error = file.get_error()
	file.close()
	return ServiceResult.success({"sequence": sequence}) if error == OK else ServiceResult.failure(&"save_write", "Checkpoint write failed; the other slot remains available.")
