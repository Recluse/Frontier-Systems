extends RefCounted
class_name InventoryLedger

## Bounded physical ownership graph. Call only from an authoritative owner.
## Root capacities are trusted host configuration, not client authorization.
const MAX_ITEMS: int = 512
const MAX_CONTAINERS: int = 256
const MAX_DEPTH: int = 8
const MAX_EXACT_INTEGER: int = 9007199254740990
var _record: Dictionary = {}
var _catalog: InventoryItemCatalog
var _loads: Dictionary = {}


func to_record() -> Dictionary:
	return _record.duplicate(true)


func container_load(container_id: String) -> ServiceResult:
	if not _loads.has(container_id):
		return ServiceResult.failure(&"unknown_inventory_container", "The container is not in this ledger.")
	return ServiceResult.success(_loads[container_id].duplicate(true))


## Detached item plus trusted dimensions, including descendant mass for storage.
func item_observation(item_id: String) -> ServiceResult:
	for item in _record["items"]:
		if item["item_id"] != item_id:
			continue
		var definition: Dictionary = _catalog.get_definition(item["definition_id"], int(item["definition_revision"])).value
		var mass: int = int(definition["mass_milligrams"])
		var payload: ServiceResult = _catalog.payload_mass(item_id)
		if not payload.is_success or int(payload.value) > MAX_EXACT_INTEGER - mass:
			return _failure("Payload mass is invalid or exceeds capacity.")
		mass += int(payload.value)
		for container in _record["containers"]:
			if container["owner_item_id"] == item_id:
				var contents_mass: int = int(_loads[container["container_id"]]["mass_milligrams"])
				if contents_mass > MAX_EXACT_INTEGER - mass:
					return _failure("Loaded item mass exceeds the exact quantity bound.")
				mass += contents_mass
		return ServiceResult.success({"item": item.duplicate(true), "tags": definition["tags"].duplicate(),
			"mass_milligrams": mass, "volume_millilitres": int(definition["volume_millilitres"])})
	return ServiceResult.failure(&"unknown_inventory_item", "The item is not in this ledger.")


## Resolve physical ancestry only; this does not grant container access.
func root_for_container(container_id: String) -> ServiceResult:
	var containers: Dictionary = {}
	var items: Dictionary = {}
	for container in _record["containers"]:
		containers[container["container_id"]] = container
	for item in _record["items"]:
		items[item["item_id"]] = item
	if not containers.has(container_id):
		return ServiceResult.failure(&"unknown_inventory_container", "The container is not in this ledger.")
	var cursor: String = container_id
	for _depth in range(MAX_DEPTH):
		var owner: String = containers[cursor]["owner_item_id"]
		if owner == "":
			return ServiceResult.success(cursor)
		cursor = items[owner]["container_id"]
	return _failure("Container ancestry exceeds the supported depth.")


## Compare-and-swap of the whole graph; rejected moves preserve all ownership.
## Reach, ACLs, equipment, request receipts and reservations are separate gates.
func move_item(item_id: String, source_container_id: String, destination_container_id: String, expected_revision: int) -> ServiceResult:
	if expected_revision != int(_record["state_revision"]) or expected_revision >= MAX_EXACT_INTEGER:
		return ServiceResult.failure(&"inventory_revision_conflict", "The inventory revision is stale or exhausted.")
	if source_container_id == destination_container_id:
		return ServiceResult.failure(&"inventory_same_location", "The item is already in that location.")
	var candidate: Dictionary = to_record()
	var found: bool = false
	for item in candidate["items"]:
		if item["item_id"] != item_id:
			continue
		if item["container_id"] != source_container_id:
			return ServiceResult.failure(&"inventory_source_conflict", "The item is not at the expected source.")
		item["container_id"] = destination_container_id
		found = true
		break
	if not found:
		return ServiceResult.failure(&"unknown_inventory_item", "The item is not in this ledger.")
	candidate["state_revision"] = expected_revision + 1
	var validated: ServiceResult = from_record(candidate, _catalog)
	if not validated.is_success:
		return validated
	var next: InventoryLedger = validated.value
	_record = next._record
	_loads = next._loads
	return ServiceResult.success({"state_revision": int(_record["state_revision"]), "item_id": item_id,
		"source_container_id": source_container_id, "destination_container_id": destination_container_id})


static func from_record(record: Dictionary, catalog: InventoryItemCatalog) -> ServiceResult:
	if catalog == null or not ControlContractValidation.has_exact_fields(record, PackedStringArray(["schema_version", "ledger_id", "state_revision", "containers", "items"])) or not ControlContractValidation.is_integer(record.get("schema_version"), 1, 1):
		return _failure("A complete inventory record and trusted item catalog are required.")
	if not ControlContractValidation.is_id(record["ledger_id"]) or not ControlContractValidation.is_integer(record["state_revision"], 0, MAX_EXACT_INTEGER):
		return _failure("The ledger identity or revision is invalid.")
	if typeof(record["containers"]) != TYPE_ARRAY or record["containers"].size() > MAX_CONTAINERS or typeof(record["items"]) != TYPE_ARRAY or record["items"].size() > MAX_ITEMS:
		return _failure("Item and container arrays must be bounded.")
	var containers: Dictionary = {}
	var items: Dictionary = {}
	var definitions: Dictionary = {}
	var owned_containers: Dictionary = {}
	var loads: Dictionary = {}
	for raw_container in record["containers"]:
		if typeof(raw_container) != TYPE_DICTIONARY:
			return _failure("Every container must be a record.")
		var container: Dictionary = raw_container
		if not ControlContractValidation.has_exact_fields(container, PackedStringArray(["container_id", "owner_item_id", "capacity"])) or not ControlContractValidation.is_id(container.get("container_id")) or containers.has(container["container_id"]):
			return _failure("Container IDs must be valid and unique.")
		if typeof(container["owner_item_id"]) != TYPE_STRING or (container["owner_item_id"] != "" and not ControlContractValidation.is_id(container["owner_item_id"])):
			return _failure("A container owner must be an item ID or an empty root owner.")
		var capacity_check: ServiceResult = InventoryItemCatalog.validate_capacity(container["capacity"])
		if not capacity_check.is_success:
			return capacity_check
		containers[container["container_id"]] = container
		loads[container["container_id"]] = {"mass_milligrams": 0, "volume_millilitres": 0, "direct_items": 0}
		if container["owner_item_id"] != "":
			if owned_containers.has(container["owner_item_id"]):
				return _failure("A storage item must own exactly one container.")
			owned_containers[container["owner_item_id"]] = container["container_id"]
	for raw_item in record["items"]:
		if typeof(raw_item) != TYPE_DICTIONARY:
			return _failure("Every item must be a record.")
		var item: Dictionary = raw_item
		if not ControlContractValidation.has_exact_fields(item, PackedStringArray(["item_id", "definition_id", "definition_revision", "condition_permille", "container_id"])):
			return _failure("An item has missing or unsupported fields.")
		for field in ["item_id", "definition_id", "container_id"]:
			if not ControlContractValidation.is_id(item[field]):
				return _failure("Item identifiers must be valid.")
		if items.has(item["item_id"]) or not containers.has(item["container_id"]) or not ControlContractValidation.is_integer(item["definition_revision"], 1, MAX_EXACT_INTEGER) or not ControlContractValidation.is_integer(item["condition_permille"], 0, 1000):
			return _failure("Item identity, location, condition or revision is invalid.")
		var definition: ServiceResult = catalog.get_definition(item["definition_id"], int(item["definition_revision"]))
		if not definition.is_success:
			return definition
		items[item["item_id"]] = item
		definitions[item["item_id"]] = definition.value
		var payload: ServiceResult = catalog.payload_mass(item["item_id"])
		if not payload.is_success or int(payload.value) > MAX_EXACT_INTEGER - int(definition.value["mass_milligrams"]):
			return _failure("Item payload exceeds the exact mass bound.")
		definitions[item["item_id"]]["mass_milligrams"] += int(payload.value)
	for owner_id in owned_containers:
		if not items.has(owner_id) or definitions[owner_id]["storage"] == null or not InventoryItemCatalog.capacities_match(containers[owned_containers[owner_id]]["capacity"], definitions[owner_id]["storage"]):
			return _failure("Hosted storage must match its existing item's trusted definition.")
	for item_id in items:
		if definitions[item_id]["storage"] != null and not owned_containers.has(item_id):
			return _failure("A storage item is missing its contents container.")
		var item: Dictionary = items[item_id]
		var definition: Dictionary = definitions[item_id]
		var direct_id: String = item["container_id"]
		var accepted: bool = false
		for tag in containers[direct_id]["capacity"]["accepted_tags"]:
			if definition["tags"].has(tag):
				accepted = true
		if not accepted:
			return _failure("The item's tags are incompatible with its container.")
		var direct_load: Dictionary = loads[direct_id]
		if int(definition["volume_millilitres"]) > MAX_EXACT_INTEGER - int(direct_load["volume_millilitres"]):
			return _failure("Container volume overflow.")
		direct_load["volume_millilitres"] += int(definition["volume_millilitres"])
		direct_load["direct_items"] += 1
		var visited: Dictionary = {}
		var cursor: String = direct_id
		while true:
			if visited.has(cursor) or visited.size() >= MAX_DEPTH:
				return _failure("Containment has a cycle or exceeds the maximum depth.")
			visited[cursor] = true
			var load: Dictionary = loads[cursor]
			if int(definition["mass_milligrams"]) > MAX_EXACT_INTEGER - int(load["mass_milligrams"]):
				return _failure("Container mass overflow.")
			load["mass_milligrams"] += int(definition["mass_milligrams"])
			var owner: String = containers[cursor]["owner_item_id"]
			if owner == "":
				break
			cursor = items[owner]["container_id"]
	for container_id in containers:
		var capacity: Dictionary = containers[container_id]["capacity"]
		var load: Dictionary = loads[container_id]
		if load["mass_milligrams"] > capacity["max_mass_milligrams"] or load["volume_millilitres"] > capacity["max_volume_millilitres"] or load["direct_items"] > capacity["max_items"]:
			return _failure("A container exceeds its mass, volume or direct item limit.")
	var ledger := InventoryLedger.new()
	ledger._record = record.duplicate(true)
	ledger._record["state_revision"] = int(record["state_revision"])
	ledger._catalog = catalog
	ledger._loads = loads
	return ServiceResult.success(ledger)


static func _failure(message: String) -> ServiceResult:
	return ServiceResult.failure(&"invalid_inventory_graph", message)
