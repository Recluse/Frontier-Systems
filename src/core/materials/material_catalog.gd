extends RefCounted
class_name MaterialCatalog

## Detached pinned material revisions; no executable recipe or handler content.
const MAX_REVISIONS: int = 4096
var _records: Dictionary = {}


func register_definition(record: Dictionary) -> ServiceResult:
	var parsed: ServiceResult = MaterialDefinition.from_record(record)
	if not parsed.is_success:
		return parsed
	var definition: MaterialDefinition = parsed.value
	var key: String = JSON.stringify([definition.definition_id, definition.revision])
	if _records.has(key) or _records.size() >= MAX_REVISIONS:
		return ServiceResult.failure(&"material_catalog_conflict", "The material revision already exists or the catalog is full.")
	_records[key] = definition.to_record()
	return ServiceResult.success()


func get_definition(definition_id: String, revision: int) -> ServiceResult:
	var key: String = JSON.stringify([definition_id, revision])
	if not _records.has(key):
		return ServiceResult.failure(&"unknown_material", "The material revision is not in the trusted catalog.")
	return MaterialDefinition.from_record(_records[key].duplicate(true))
