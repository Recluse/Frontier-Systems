extends RefCounted
class_name CheckpointBackupHistory

## Worker-side, bounded history. Fixed names exclude staging and arbitrary directory files.
## Never invoke storage operations inside a simulation tick. One writer owns the directory.
const SLOT_COUNT: int = CheckpointHistoryPolicy.MAX_ENTRIES + 1
const DIRECTORY: String = "checkpoint-history"


static func _path(directory: String, slot: int) -> String:
	return ProjectSettings.globalize_path(directory).path_join(DIRECTORY).path_join("backup-%d.json" % slot)


## Metadata only; no snapshot buffers escape the bounded scan. Invalid entries are reported.
static func list_candidates(directory: String, io: CheckpointFileIO = null) -> ServiceResult:
	if directory.is_empty():
		return ServiceResult.failure(&"backup_configuration", "A history source directory is required.")
	var files: CheckpointFileIO = io if io != null else CheckpointFileIO.new()
	var candidates: Array[Dictionary] = []
	var rejected: Array[Dictionary] = []
	for slot in range(SLOT_COUNT):
		var path: String = _path(directory, slot)
		if not files.exists(path):
			continue
		var read: ServiceResult = files.read_text(path, LocalWorldSaveStore.MAX_BYTES)
		if not read.is_success:
			rejected.append({"slot": slot, "code": String(read.error_code)})
			continue
		var decoded: ServiceResult = LocalWorldSaveStore.decode_checkpoint(read.value)
		if not decoded.is_success:
			rejected.append({"slot": slot, "code": String(decoded.error_code)})
			continue
		var snapshot: WorldSnapshot = WorldSnapshot.from_json(decoded.value["snapshot_json"]).value
		candidates.append({"slot": slot, "sequence": int(decoded.value["sequence"]), "tick_number": snapshot.tick_number, "sha256": decoded.value["sha256"], "world_id": String(snapshot.world_id), "region_id": String(snapshot.region_id), "bytes": read.value.to_utf8_buffer().size()})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["sequence"] > b["sequence"])
	return ServiceResult.success({"candidates": candidates, "rejected": rejected})


## Explicit descriptor from list_candidates; re-read and compare every field before selection.
## This returns detached data only. It never changes active slots or selects a fallback.
static func select_candidate(directory: String, selection: Dictionary, io: CheckpointFileIO = null) -> ServiceResult:
	if not ControlContractValidation.has_exact_fields(selection, PackedStringArray(["slot", "sequence", "tick_number", "sha256", "world_id", "region_id", "bytes"])) or not ControlContractValidation.is_integer(selection.get("slot"), 0, SLOT_COUNT - 1):
		return ServiceResult.failure(&"backup_selection", "Select an exact listed history descriptor.")
	var listed: ServiceResult = list_candidates(directory, io)
	if not listed.is_success:
		return listed
	if not listed.value["candidates"].has(selection):
		return ServiceResult.failure(&"backup_selection", "Selected backup is invalid, missing or changed; list history again.")
	var files: CheckpointFileIO = io if io != null else CheckpointFileIO.new()
	var read: ServiceResult = files.read_text(_path(directory, int(selection["slot"])), LocalWorldSaveStore.MAX_BYTES)
	if not read.is_success:
		return ServiceResult.failure(&"backup_selection", read.message)
	var decoded: ServiceResult = LocalWorldSaveStore.decode_checkpoint(read.value)
	if not decoded.is_success:
		return ServiceResult.failure(&"backup_selection", decoded.message)
	var snapshot: WorldSnapshot = WorldSnapshot.from_json(decoded.value["snapshot_json"]).value
	if int(decoded.value["sequence"]) != selection["sequence"] or decoded.value["sha256"] != selection["sha256"] or snapshot.tick_number != selection["tick_number"] or String(snapshot.world_id) != selection["world_id"] or String(snapshot.region_id) != selection["region_id"] or read.value.to_utf8_buffer().size() != selection["bytes"]:
		return ServiceResult.failure(&"backup_selection", "Selected backup changed during validation.")
	return decoded


## Archive only exact committed bytes after active acknowledgement. Failure is a separate result.
static func archive_committed(directory: String, sequence: int, snapshot_json: String, policy: CheckpointHistoryPolicy, io: CheckpointFileIO = null) -> ServiceResult:
	if policy == null or not policy.validate().is_success:
		return ServiceResult.failure(&"backup_configuration", "A valid opt-in history policy is required.")
	var files: CheckpointFileIO = io if io != null else CheckpointFileIO.new()
	var active_path: String = ProjectSettings.globalize_path(directory).path_join("world-%s.json" % ("a" if sequence % 2 == 0 else "b"))
	var active: ServiceResult = files.read_text(active_path, LocalWorldSaveStore.MAX_BYTES)
	if not active.is_success:
		return ServiceResult.failure(&"backup_source", active.message)
	var decoded: ServiceResult = LocalWorldSaveStore.decode_checkpoint(active.value)
	if not decoded.is_success or int(decoded.value["sequence"]) != sequence or decoded.value["snapshot_json"] != snapshot_json:
		return ServiceResult.failure(&"backup_source", "History requires the exact verified committed checkpoint.")
	var size: int = active.value.to_utf8_buffer().size()
	if size > policy.retained_bytes:
		return ServiceResult.failure(&"backup_bounds", "Committed checkpoint exceeds configured history byte retention.")
	var created: ServiceResult = files.ensure_directory(_path(directory, 0).get_base_dir())
	if not created.is_success:
		return ServiceResult.failure(&"backup_directory", created.message)
	var listed: ServiceResult = list_candidates(directory, files)
	# Preserve unreadable/corrupt evidence rather than overwrite an uncertain recovery entry.
	if not listed.is_success or not listed.value["rejected"].is_empty():
		return ServiceResult.failure(&"backup_scan", "History has an invalid or unreadable entry; preserve it for operator inspection.")
	var candidates: Array[Dictionary] = listed.value["candidates"]
	var snapshot: WorldSnapshot = WorldSnapshot.from_json(snapshot_json).value
	var existing: bool = false
	for candidate in candidates:
		if candidate["world_id"] != String(snapshot.world_id) or candidate["region_id"] != String(snapshot.region_id):
			return ServiceResult.failure(&"backup_identity", "History belongs to another world or region.")
		if candidate["sequence"] == sequence:
			if candidate["sha256"] != decoded.value["sha256"]:
				return ServiceResult.failure(&"backup_sequence", "History sequence has conflicting content.")
			existing = true
		if candidate["sequence"] > sequence:
			return ServiceResult.failure(&"backup_sequence", "History is newer than the acknowledged active checkpoint.")
	if existing:
		var retried: ServiceResult = _prune(directory, candidates, policy, files)
		return ServiceResult.success({"sequence": sequence}) if retried.is_success else retried
	# Repair interrupted post-promotion pruning before adding another entry.
	var pruned: ServiceResult = _prune(directory, candidates, policy, files)
	if not pruned.is_success:
		return pruned
	var slot: int = -1
	for index in range(SLOT_COUNT):
		if not files.exists(_path(directory, index)):
			slot = index
			break
	if slot < 0:
		return ServiceResult.failure(&"backup_bounds", "No bounded history slot is available.")
	var path: String = _path(directory, slot)
	var staging: String = _path(directory, 0).get_base_dir().path_join("archive.tmp")
	var written: ServiceResult = files.write_text(staging, active.value)
	if not written.is_success:
		return _cleanup(files, staging, &"backup_write", written.message)
	var verified: ServiceResult = files.read_text(staging, LocalWorldSaveStore.MAX_BYTES)
	if not verified.is_success or verified.value != active.value:
		return _cleanup(files, staging, &"backup_verify", "History staging did not read back exactly.")
	var promoted: ServiceResult = files.promote(staging, path)
	if not promoted.is_success:
		return _cleanup(files, staging, &"backup_promote", promoted.message)
	# New valid backup exists before any old recovery candidate may be removed.
	candidates.push_front({"slot": slot, "sequence": sequence, "bytes": size})
	var retained: ServiceResult = _prune(directory, candidates, policy, files)
	return ServiceResult.success({"sequence": sequence}) if retained.is_success else retained


static func _prune(directory: String, candidates: Array[Dictionary], policy: CheckpointHistoryPolicy, files: CheckpointFileIO) -> ServiceResult:
	var total: int = 0
	for candidate in candidates:
		total += int(candidate["bytes"])
	while candidates.size() > 1 and (candidates.size() > policy.entries or total > policy.retained_bytes):
		var oldest: Dictionary = candidates.back()
		var removed: ServiceResult = files.remove_file(_path(directory, int(oldest["slot"])))
		if not removed.is_success:
			return ServiceResult.failure(&"backup_prune", "History pruning failed; active slots and the last valid backup are preserved.")
		total -= int(oldest["bytes"])
		candidates.pop_back()
	# A smaller policy cannot delete the last recoverable backup to meet a bound.
	if total > policy.retained_bytes:
		return ServiceResult.failure(&"backup_bounds", "Last backup exceeds changed retention; preserve it for explicit operator handling.")
	return ServiceResult.success()


static func _cleanup(files: CheckpointFileIO, staging: String, code: StringName, message: String) -> ServiceResult:
	var cleaned: ServiceResult = files.remove_file(staging)
	if not cleaned.is_success:
		return ServiceResult.failure(&"backup_cleanup", message + " History staging cleanup failed; staging is never selectable.")
	return ServiceResult.failure(code, message)
