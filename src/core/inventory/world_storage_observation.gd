extends RefCounted
class_name WorldStorageObservation

## Detached client-facing world storage v2 contract; no mesh or resource paths.
var _record: Dictionary = {}


func to_record() -> Dictionary:
	return _record.duplicate(true)


static func from_record(record: Dictionary) -> ServiceResult:
	if not ControlContractValidation.has_exact_fields(record, PackedStringArray(["schema_version", "inventory_revision", "containers"])) or not ControlContractValidation.is_integer(record.get("schema_version"), 2, 2) or not ControlContractValidation.is_integer(record.get("inventory_revision"), 0, 9007199254740990) or typeof(record.get("containers")) != TYPE_ARRAY or record["containers"].size() > 32:
		return _failure("A bounded world storage v2 observation is required.")
	var ids: Dictionary = {}
	var item_ids: Dictionary = {}
	for raw in record["containers"]:
		if typeof(raw) != TYPE_DICTIONARY or not ControlContractValidation.has_exact_fields(raw, PackedStringArray(["container_id", "distance_millimetres", "position_millimetres", "items"])) or not ControlContractValidation.is_id(raw.get("container_id")) or ids.has(raw["container_id"]) or not ControlContractValidation.is_integer(raw.get("distance_millimetres"), 0, 1500) or typeof(raw.get("position_millimetres")) != TYPE_ARRAY or raw["position_millimetres"].size() != 3 or typeof(raw.get("items")) != TYPE_ARRAY or raw["items"].size() > 512:
			return _failure("Each visible container requires unique identity, position and bounded contents.")
		for coordinate in raw["position_millimetres"]:
			if not ControlContractValidation.is_integer(coordinate, -10000000, 10000000):
				return _failure("World display positions must be bounded integer millimetres.")
		ids[raw["container_id"]] = true
		for item in raw["items"]:
			if typeof(item) != TYPE_DICTIONARY or not ControlContractValidation.has_exact_fields(item, PackedStringArray(["item_id", "definition_id", "definition_revision", "condition_permille", "container_id"])) or not ControlContractValidation.is_id(item.get("item_id")) or item_ids.has(item["item_id"]) or not ControlContractValidation.is_id(item.get("definition_id")) or item.get("container_id") != raw["container_id"] or not ControlContractValidation.is_integer(item.get("definition_revision"), 1, 9007199254740990) or not ControlContractValidation.is_integer(item.get("condition_permille"), 0, 1000):
				return _failure("Visible items must have unique identities and match their container.")
			item_ids[item["item_id"]] = true
			if item_ids.size() > 512:
				return _failure("The observation exceeds its total item bound.")
	var observation := WorldStorageObservation.new()
	observation._record = record.duplicate(true)
	return ServiceResult.success(observation)


static func _failure(message: String) -> ServiceResult:
	return ServiceResult.failure(&"invalid_world_storage_observation", message)
