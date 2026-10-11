extends RefCounted
class_name LocalTerrainRetryStore

## Local client uncertainty journal, never a save or an authoritative terrain record.
const MAX_BYTES: int = 8192


static func valid(value: Variant) -> bool:
	return typeof(value) == TYPE_DICTIONARY and ToolComponentCatalog.exact(value, ["schema_version", "world_id", "region_id", "slot", "request_number", "operation", "payload"]) and ControlContractValidation.is_integer(value["schema_version"], 1, 2) and (value["schema_version"] == 2 or value["operation"] != "materialize") and ControlContractValidation.is_id(value["world_id"]) and ControlContractValidation.is_id(value["region_id"]) and ControlContractValidation.is_integer(value["slot"], 0, 1) and TerrainObservationValidation.valid_intent(value["request_number"], value["operation"], value["payload"])


static func read_intent(path: String) -> ServiceResult:
	if not FileAccess.file_exists(path): return ServiceResult.failure(&"terrain_retry_missing", "No unresolved terrain journal.")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_BYTES: return _failure("Terrain journal is unreadable or oversized.")
	var value: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not valid(value): return _failure("Terrain journal must contain one bounded original intent.")
	return ServiceResult.success(normalized(value))


static func normalized(value: Dictionary) -> Dictionary:
	var record: Dictionary = value.duplicate(true)
	for field in ["schema_version", "slot", "request_number"]: record[field] = int(record[field])
	for field in ["expected_cell_revision", "expected_inventory_revision", "expected_tool_revision", "amount_milligrams"]:
		if record["payload"].has(field): record["payload"][field] = int(record["payload"][field])
	return record


static func write_intent(path: String, record: Dictionary) -> ServiceResult:
	if not valid(record): return _failure("Refuse invalid client intent.")
	var text: String = JSON.stringify(record)
	if text.to_utf8_buffer().size() > MAX_BYTES or DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK: return _failure("Cannot create bounded client journal directory.")
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null: return _failure("Cannot open client journal temporary file.")
	file.store_string(text)
	file.flush()
	var error: Error = file.get_error()
	file.close()
	if error != OK or DirAccess.rename_absolute(path + ".tmp", path) != OK: return _failure("Cannot commit the original client intent journal.")
	return ServiceResult.success()


static func clear_intent(path: String) -> ServiceResult:
	if FileAccess.file_exists(path) and DirAccess.remove_absolute(path) != OK: return _failure("Cannot clear reconciled client intent; retry it before fresh work.")
	return ServiceResult.success()


static func _failure(message: String) -> ServiceResult:
	return ServiceResult.failure(&"terrain_retry_storage", message)
