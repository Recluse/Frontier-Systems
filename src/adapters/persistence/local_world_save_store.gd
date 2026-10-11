extends RefCounted
class_name LocalWorldSaveStore

## Platform-neutral two-slot checkpoints. Invoke writes on a worker, never a tick.
## One writer owns a directory. Unpromoted staging files are never recovery candidates.
const MAX_BYTES: int = 16777216
const MAX_SEQUENCE: int = 9007199254740000


static func read_latest(directory: String, io: CheckpointFileIO = null) -> ServiceResult:
	if directory.is_empty():
		return ServiceResult.failure(&"save_bounds", "A checkpoint directory is required.")
	var files: CheckpointFileIO = io if io != null else CheckpointFileIO.new()
	var absolute: String = ProjectSettings.globalize_path(directory)
	var best: Dictionary = {}
	var found: bool = false
	var unreadable: bool = false
	for slot in ["a", "b"]:
		var path: String = absolute.path_join("world-%s.json" % slot)
		if not files.exists(path):
			continue
		found = true
		var read: ServiceResult = files.read_text(path, MAX_BYTES)
		if not read.is_success:
			unreadable = unreadable or read.error_code == &"save_read"
			continue
		var validated: ServiceResult = _decode(read.value)
		if not validated.is_success:
			continue
		var value: Dictionary = validated.value
		if slot != ("a" if int(value["sequence"]) % 2 == 0 else "b"):
			continue
		if best.is_empty() or int(value["sequence"]) > int(best["sequence"]):
			best = value
	# A write must not overwrite an unreadable slot that could be the newest one.
	if unreadable:
		return ServiceResult.failure(&"save_read", "A checkpoint slot is unreadable; preserve it for recovery.")
	if best.is_empty() and found:
		return ServiceResult.failure(&"save_corrupt", "No structurally valid world checkpoint remains; preserve the files for recovery.")
	return ServiceResult.success(best)


static func _decode(text: String) -> ServiceResult:
	var parser := JSON.new()
	if parser.parse(text) != OK or typeof(parser.data) != TYPE_DICTIONARY:
		return ServiceResult.failure(&"save_corrupt", "Checkpoint envelope is invalid JSON.")
	var value: Dictionary = parser.data
	if not ControlContractValidation.has_exact_fields(value, PackedStringArray(["schema_version", "sequence", "snapshot_json", "sha256"])) or not ControlContractValidation.is_integer(value.get("schema_version"), 1, 1) or not ControlContractValidation.is_integer(value.get("sequence"), 1, MAX_SEQUENCE) or typeof(value.get("snapshot_json")) != TYPE_STRING or typeof(value.get("sha256")) != TYPE_STRING:
		return ServiceResult.failure(&"save_corrupt", "Checkpoint fields or sequence are invalid.")
	if value["snapshot_json"].to_utf8_buffer().size() > MAX_BYTES / 2 or value["snapshot_json"].sha256_text() != value["sha256"] or not WorldSnapshot.from_json(value["snapshot_json"]).is_success:
		return ServiceResult.failure(&"save_corrupt", "Checkpoint checksum or world envelope is invalid.")
	return ServiceResult.success(value)


static func write_checkpoint(directory: String, sequence: int, snapshot_json: String, io: CheckpointFileIO = null) -> ServiceResult:
	if directory.is_empty() or sequence < 1 or sequence > MAX_SEQUENCE or snapshot_json.to_utf8_buffer().size() > MAX_BYTES / 2:
		return ServiceResult.failure(&"save_bounds", "Checkpoint exceeds its identity, sequence or byte bounds.")
	if not WorldSnapshot.from_json(snapshot_json).is_success:
		return ServiceResult.failure(&"save_snapshot", "Checkpoint requires a structurally valid world snapshot.")
	var envelope: String = JSON.stringify({"schema_version": 1, "sequence": sequence, "snapshot_json": snapshot_json, "sha256": snapshot_json.sha256_text()})
	if envelope.to_utf8_buffer().size() > MAX_BYTES:
		return ServiceResult.failure(&"save_bounds", "Encoded checkpoint envelope exceeds its byte bound.")
	var files: CheckpointFileIO = io if io != null else CheckpointFileIO.new()
	var absolute: String = ProjectSettings.globalize_path(directory)
	var created: ServiceResult = files.ensure_directory(absolute)
	if not created.is_success:
		return created
	var latest: ServiceResult = read_latest(absolute, files)
	if not latest.is_success:
		return latest
	var previous: int = 0 if latest.value.is_empty() else int(latest.value["sequence"])
	# Lost acknowledgement may be retried with the identical detached snapshot.
	if sequence == previous and snapshot_json == latest.value["snapshot_json"]:
		return ServiceResult.success({"sequence": sequence})
	if sequence != previous + 1:
		return ServiceResult.failure(&"save_sequence", "Checkpoint must follow the latest committed sequence; reload after an uncertain or external write.")
	var path: String = absolute.path_join("world-%s.json" % ("a" if sequence % 2 == 0 else "b"))
	var staging: String = path + ".tmp"
	var written: ServiceResult = files.write_text(staging, envelope)
	if not written.is_success:
		return _cleanup(files, staging, written)
	var readback: ServiceResult = files.read_text(staging, MAX_BYTES)
	if not readback.is_success or readback.value != envelope:
		return _cleanup(files, staging, ServiceResult.failure(&"save_verify", "Staged checkpoint did not read back exactly; no write is acknowledged."))
	# Removing only the inactive slot works on Windows without replace-rename assumptions.
	var removed: ServiceResult = files.remove_file(path)
	if not removed.is_success:
		return _cleanup(files, staging, removed)
	var promoted: ServiceResult = files.promote(staging, path)
	if not promoted.is_success:
		return _cleanup(files, staging, promoted)
	return ServiceResult.success({"sequence": sequence})


static func _cleanup(files: CheckpointFileIO, staging: String, failure: ServiceResult) -> ServiceResult:
	var removed: ServiceResult = files.remove_file(staging)
	if not removed.is_success:
		return ServiceResult.failure(&"save_cleanup", "%s Staging cleanup also failed; startup ignores the staging file." % failure.message)
	return failure
