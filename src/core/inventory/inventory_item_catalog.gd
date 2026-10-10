extends RefCounted
class_name InventoryItemCatalog

## Trusted, detached item dimensions and optional storage capacities.
const MAX_EXACT_INTEGER: int = 9007199254740990
const MAX_DEFINITIONS: int = 4096
var _definitions: Dictionary = {}
var _payload_mass_provider: Callable
var _payload_mass_override: Dictionary = {}
var _has_mass_override: bool = false


## Trusted component owner only; payloads are never supplied by transport clients.
func bind_payload_mass_provider(provider: Callable) -> ServiceResult:
	if _payload_mass_provider.is_valid() or not provider.is_valid():
		return ServiceResult.failure(&"payload_mass_binding", "Bind one canonical payload mass provider.")
	_payload_mass_provider = provider
	return ServiceResult.success()


func payload_mass(item_id: String) -> ServiceResult:
	var value: Variant = _payload_mass_override.get(item_id, 0) if _has_mass_override else (_payload_mass_provider.call(item_id) if _payload_mass_provider.is_valid() else 0)
	if not ControlContractValidation.is_integer(value, 0, MAX_EXACT_INTEGER):
		return ServiceResult.failure(&"payload_mass_invalid", "Payload mass must be bounded integral milligrams.")
	return ServiceResult.success(int(value))


## Disposable prospective view for atomic transaction/restore capacity checks.
func with_payload_masses(masses: Dictionary) -> InventoryItemCatalog:
	var view := InventoryItemCatalog.new()
	view._definitions = _definitions.duplicate(false)
	view._payload_mass_override = masses.duplicate(true)
	view._has_mass_override = true
	return view


func register_definition(record: Dictionary) -> ServiceResult:
	var fields := PackedStringArray(["schema_version", "definition_id", "revision", "tags", "mass_milligrams", "volume_millilitres", "storage"])
	if not ControlContractValidation.has_exact_fields(record, fields) or not ControlContractValidation.is_integer(record.get("schema_version"), 1, 1):
		return ServiceResult.failure(&"invalid_inventory_item_definition", "A complete versioned item definition is required.")
	if not ControlContractValidation.is_id(record["definition_id"]) or not ControlContractValidation.is_integer(record["revision"], 1, MAX_EXACT_INTEGER):
		return ServiceResult.failure(&"invalid_inventory_item_identity", "A valid item identity and revision are required.")
	for field in ["mass_milligrams", "volume_millilitres"]:
		if not ControlContractValidation.is_integer(record[field], 0, MAX_EXACT_INTEGER):
			return ServiceResult.failure(&"invalid_inventory_item_dimensions", "Dimensions must be exact non-negative quantities.")
	var tags: ServiceResult = ControlContractValidation.decode_ids(record["tags"], 1, 32)
	if not tags.is_success:
		return tags
	if record["storage"] != null:
		var storage_check: ServiceResult = validate_capacity(record["storage"])
		if not storage_check.is_success:
			return storage_check
	var key: String = JSON.stringify([record["definition_id"], int(record["revision"])])
	if _definitions.has(key) or _definitions.size() >= MAX_DEFINITIONS:
		return ServiceResult.failure(&"inventory_item_catalog_conflict", "This revision exists or the catalog is full.")
	_definitions[key] = record.duplicate(true)
	return ServiceResult.success()


func get_definition(definition_id: String, revision: int) -> ServiceResult:
	var key: String = JSON.stringify([definition_id, revision])
	if not _definitions.has(key):
		return ServiceResult.failure(&"unknown_inventory_item_definition", "The pinned item definition is not trusted.")
	return ServiceResult.success(_definitions[key].duplicate(true))


static func validate_capacity(value: Variant) -> ServiceResult:
	if typeof(value) != TYPE_DICTIONARY:
		return ServiceResult.failure(&"invalid_inventory_capacity", "Storage capacity must be a record.")
	var record: Dictionary = value
	if not ControlContractValidation.has_exact_fields(record, PackedStringArray(["max_mass_milligrams", "max_volume_millilitres", "max_items", "accepted_tags"])):
		return ServiceResult.failure(&"invalid_inventory_capacity", "Storage capacity has missing or unsupported fields.")
	for field in ["max_mass_milligrams", "max_volume_millilitres"]:
		if not ControlContractValidation.is_integer(record[field], 0, MAX_EXACT_INTEGER):
			return ServiceResult.failure(&"invalid_inventory_capacity", "Capacity quantities must be exact and non-negative.")
	if not ControlContractValidation.is_integer(record["max_items"], 0, 512):
		return ServiceResult.failure(&"invalid_inventory_capacity", "The direct item limit is outside the supported bounds.")
	return ControlContractValidation.decode_ids(record["accepted_tags"], 1, 32)


## Already-validated capacities compare exact quantities, independent of JSON numeric representation.
static func capacities_match(first: Dictionary, second: Dictionary) -> bool:
	for field in ["max_mass_milligrams", "max_volume_millilitres", "max_items"]:
		if int(first[field]) != int(second[field]):
			return false
	return first["accepted_tags"] == second["accepted_tags"]
