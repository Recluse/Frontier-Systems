extends RefCounted
class_name CheckpointOperator

## Local startup operator boundary. Never called from a simulation tick.
const MAX_DESCRIPTOR_BYTES: int = 4096
const MAX_ARGUMENT_BYTES: int = 4096
const EXIT_OK: int = 0
const EXIT_OPTIONS: int = 2
const EXIT_INSPECTION: int = 3
const EXIT_RECOVERY: int = 4


## Both empty means disabled. Explicit limits use canonical unsigned decimal text.
static func history_from_settings(entries: String, bytes: String) -> ServiceResult:
	if entries.is_empty() and bytes.is_empty():
		return ServiceResult.success(null)
	if not _decimal(entries, 1, CheckpointHistoryPolicy.MAX_ENTRIES) or not _decimal(bytes, 1, CheckpointHistoryPolicy.MAX_RETAINED_BYTES):
		return ServiceResult.failure(&"backup_configuration", "Set both history limits: 1-8 entries and 1-67108864 retained bytes, using decimal integers.")
	var policy := CheckpointHistoryPolicy.new(entries.to_int(), bytes.to_int())
	var validated: ServiceResult = policy.validate()
	return ServiceResult.success(policy) if validated.is_success else validated


static func _decimal(text: String, minimum: int, maximum: int) -> bool:
	if text.is_empty() or text.length() > 8 or (text.length() > 1 and text.begins_with("0")):
		return false
	for character in text:
		if character < "0" or character > "9":
			return false
	return text.to_int() >= minimum and text.to_int() <= maximum


static func parse_arguments(arguments: PackedStringArray) -> ServiceResult:
	if arguments.is_empty() or arguments.size() > 7 or arguments[0] not in ["list", "recover"]:
		return _options_failure()
	var options: Dictionary = {"action": arguments[0]}
	var allowed: Array[String] = ["--source"] if arguments[0] == "list" else ["--source", "--descriptor", "--destination"]
	var index: int = 1
	while index < arguments.size():
		var key: String = arguments[index]
		if key not in allowed or options.has(key) or index + 1 >= arguments.size():
			return _options_failure()
		var value: String = arguments[index + 1]
		if value.is_empty() or value.to_utf8_buffer().size() > MAX_ARGUMENT_BYTES or not value.is_absolute_path():
			return _options_failure()
		options[key] = value
		index += 2
	if options.size() != allowed.size() + 1:
		return _options_failure()
	return ServiceResult.success(options)


static func _options_failure() -> ServiceResult:
	return ServiceResult.failure(&"operator_options", "Use list --source ABSOLUTE_DIR or recover --source ABSOLUTE_DIR --descriptor ABSOLUTE_JSON_FILE --destination ABSOLUTE_FRESH_DIR.")


## Injected I/O and disposable initialized world/adapter support isolated verification.
## The CLI owns the fresh world. Existing recovery owner enforces all storage/domain guards.
static func run(arguments: PackedStringArray, world: WorldRuntime = null, adapter: WorldPersistenceAdapter = null, io: CheckpointFileIO = null) -> Dictionary:
	var parsed: ServiceResult = parse_arguments(arguments)
	if not parsed.is_success:
		return failure(EXIT_OPTIONS, parsed, parsed.message)
	var options: Dictionary = parsed.value
	var files: CheckpointFileIO = io if io != null else CheckpointFileIO.new()
	if options["action"] == "list":
		if not files.exists(options["--source"]):
			return failure(EXIT_INSPECTION, ServiceResult.failure(&"backup_source", ""), "History source does not exist. Check the stopped host's save directory.")
		var listed: ServiceResult = CheckpointBackupHistory.list_candidates(options["--source"], files)
		if not listed.is_success:
			return failure(EXIT_INSPECTION, listed, "History inspection failed; preserve the source.")
		var rejected: Array = listed.value["rejected"]
		return {"exit_status": EXIT_OK if rejected.is_empty() else EXIT_INSPECTION, "action": "list", "candidates": listed.value["candidates"], "rejected": rejected, "message": "Copy one complete candidate into a descriptor JSON file. Stop the source host before recovery; listing does not lock storage."}
	var read: ServiceResult = files.read_text(options["--descriptor"], MAX_DESCRIPTOR_BYTES)
	if not read.is_success:
		return failure(EXIT_INSPECTION, read, "Cannot read a descriptor within 4096 bytes. Supply one complete listed candidate.")
	var json := JSON.new()
	if json.parse(read.value) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return failure(EXIT_INSPECTION, ServiceResult.failure(&"backup_selection", ""), "Descriptor must be one listed candidate JSON object; parser input is not printed.")
	if not is_instance_valid(world) or not is_instance_valid(adapter):
		return failure(EXIT_RECOVERY, ServiceResult.failure(&"backup_recovery", ""), "Recovery requires a fresh initialized stopped world and adapter.")
	var recovered: ServiceResult = adapter.configure_from_backup(world, options["--source"], json.data, options["--destination"], files)
	if not recovered.is_success:
		return failure(EXIT_RECOVERY, recovered, "Recovery rejected. Preserve source and any partial destination; discard this startup world. Re-list changed selections; use an absent destination outside source and a fresh stopped world.")
	return {"exit_status": EXIT_OK, "action": "recover", "source_sequence": recovered.value["source_sequence"], "sequence": recovered.value["sequence"], "tick_number": recovered.value["tick_number"], "message": "Recovery seeded a new destination at sequence 1. Source preserved; simulation was not started. Start the host explicitly with the destination."}


## Fixed diagnostics never interpolate raw snapshots, paths, descriptor text or keys.
static func failure(status: int, result: ServiceResult, message: String) -> Dictionary:
	return {"exit_status": status, "error_code": String(result.error_code), "message": message}


static func checkpoint_diagnostic(tick: int, result: ServiceResult, backup: Dictionary) -> String:
	if not result.is_success:
		return "Checkpoint failed: %s; previous active acknowledgement retained." % result.error_code
	if not backup["enabled"]:
		return "Checkpoint committed at tick %d; backup history disabled." % tick
	if not String(backup["error_code"]).is_empty():
		return "Checkpoint committed at tick %d; backup history failed: %s. Preserve history and inspect with checkpoint_operator list." % [tick, backup["error_code"]]
	return "Checkpoint committed at tick %d; backup history acknowledged sequence %d." % [tick, backup["sequence"]]