extends RefCounted
class_name MachineModuleRegistry

## Stores detached definition revisions behind a trusted handler allowlist.
## This catalog does not instantiate handlers or execute imported content.

const MAX_DEFINITION_REVISIONS: int = 4096

var _handler_ids := PackedStringArray()
var _definitions: Dictionary = {}
var _revision_count: int = 0


func _init(trusted_handler_ids: PackedStringArray = PackedStringArray()) -> void:
	_handler_ids = trusted_handler_ids.duplicate()


func register_definition(record: Dictionary) -> ServiceResult:
	var decoded: ServiceResult = MachineModuleDefinition.from_record(record)
	if not decoded.is_success:
		return decoded
	var module: MachineModuleDefinition = decoded.value
	if not _handler_ids.has(module.handler_id):
		return ServiceResult.failure(&"unknown_module_handler", "The module refers to a handler not registered by the server.")
	var revisions: Dictionary = _definitions.get(module.definition_id, {})
	if revisions.has(module.revision):
		return ServiceResult.failure(&"module_revision_exists", "This module definition revision is already registered.")
	if _revision_count >= MAX_DEFINITION_REVISIONS:
		return ServiceResult.failure(&"module_catalog_full", "The module definition catalog has reached its revision limit.")
	revisions[module.revision] = module.to_record()
	_definitions[module.definition_id] = revisions
	_revision_count += 1
	return ServiceResult.success({"definition_id": module.definition_id, "revision": module.revision})


func get_definition(definition_id: String, revision: int) -> ServiceResult:
	var revisions: Dictionary = _definitions.get(definition_id, {})
	if not revisions.has(revision):
		return ServiceResult.failure(&"unknown_module_definition", "The module definition revision is not registered.")
	return MachineModuleDefinition.from_record(revisions[revision].duplicate(true))
