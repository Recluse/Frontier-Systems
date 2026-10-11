extends RefCounted
class_name BodyInventoryState

## One body owns this combined ledger/equipment transaction boundary.
## Pure domain foundation: authenticated tick commands must wrap these operations.
const MAX_EXACT_INTEGER: int = 9007199254740990
var _record: Dictionary = {}
var _catalog: InventoryItemCatalog
var _profile: InventoryEquipmentProfile
var _ledger: InventoryLedger


func to_record() -> Dictionary:
	return _record.duplicate(true)


func select_hand(slot_id: String, expected_revision: int) -> ServiceResult:
	if not _profile.to_record()["hand_slot_ids"].has(slot_id):
		return ServiceResult.failure(&"unknown_body_hand", "Select a hand configured for this body.")
	var candidate: Dictionary = to_record()
	candidate["active_hand_slot_id"] = slot_id
	return _commit(candidate, expected_revision)


func switch_hand(expected_revision: int) -> ServiceResult:
	var next: ServiceResult = _profile.next_hand(_record["active_hand_slot_id"])
	return select_hand(next.value, expected_revision) if next.is_success else next


func equip_item(item_id: String, source_container_id: String, slot_id: String, expected_revision: int) -> ServiceResult:
	var candidate: Dictionary = to_record()
	for binding in candidate["equipped"]:
		if binding["slot_id"] == slot_id:
			return ServiceResult.failure(&"equipment_slot_occupied", "Unequip the existing item before using this slot.")
	var transferred: ServiceResult = _transfer(candidate, item_id, source_container_id, _record["body_container_id"])
	if not transferred.is_success:
		return transferred
	var remaining: Array = []
	for binding in candidate["equipped"]:
		if binding["item_id"] != item_id:
			remaining.append(binding)
	remaining.append({"slot_id": slot_id, "item_id": item_id})
	candidate["equipped"] = remaining
	return _commit(candidate, expected_revision)


func unequip_item(slot_id: String, destination_container_id: String, expected_revision: int) -> ServiceResult:
	var candidate: Dictionary = to_record()
	var item_id: String = ""
	var remaining: Array = []
	for binding in candidate["equipped"]:
		if binding["slot_id"] == slot_id:
			item_id = binding["item_id"]
		else:
			remaining.append(binding)
	if item_id.is_empty():
		return ServiceResult.failure(&"equipment_slot_empty", "The slot has no equipped item.")
	var transferred: ServiceResult = _transfer(candidate, item_id, _record["body_container_id"], destination_container_id)
	if not transferred.is_success:
		return transferred
	candidate["equipped"] = remaining
	return _commit(candidate, expected_revision)


## Equipment must use unequip_item; moving other contents rechecks loaded slot fit.
func move_item(item_id: String, source_container_id: String, destination_container_id: String, expected_revision: int) -> ServiceResult:
	if source_container_id == destination_container_id:
		return ServiceResult.failure(&"inventory_same_location", "The item is already in that location.")
	for binding in _record["equipped"]:
		if binding["item_id"] == item_id:
			return ServiceResult.failure(&"equipped_item_move", "Unequip this item through the equipment operation.")
	var candidate: Dictionary = to_record()
	var transferred: ServiceResult = _transfer(candidate, item_id, source_container_id, destination_container_id)
	return _commit(candidate, expected_revision) if transferred.is_success else transferred


func _transfer(candidate: Dictionary, item_id: String, source: String, destination: String) -> ServiceResult:
	var parsed: ServiceResult = InventoryLedger.from_record(candidate["ledger"], _catalog)
	if not parsed.is_success:
		return parsed
	var ledger: InventoryLedger = parsed.value
	for container_id in [source, destination]:
		var access: ServiceResult = ledger.contents_access(container_id)
		if not access.is_success: return access
	if source == destination:
		var observed: ServiceResult = ledger.item_observation(item_id)
		if not observed.is_success or observed.value["item"]["container_id"] != source:
			return ServiceResult.failure(&"inventory_source_conflict", "The item is not at the declared source.")
	else:
		var moved: ServiceResult = ledger.move_item(item_id, source, destination, int(candidate["ledger"]["state_revision"]))
		if not moved.is_success:
			return moved
	candidate["ledger"] = ledger.to_record()
	return ServiceResult.success()


func _commit(candidate: Dictionary, expected_revision: int) -> ServiceResult:
	if expected_revision != int(_record["state_revision"]) or expected_revision >= MAX_EXACT_INTEGER:
		return ServiceResult.failure(&"body_inventory_revision_conflict", "The body inventory revision is stale or exhausted.")
	candidate["state_revision"] = expected_revision + 1
	var parsed: ServiceResult = from_record(candidate, _profile, _catalog)
	if not parsed.is_success:
		return parsed
	var next: BodyInventoryState = parsed.value
	_record = next._record
	_ledger = next._ledger
	return ServiceResult.success({"state_revision": int(_record["state_revision"])})


static func from_record(record: Dictionary, profile: InventoryEquipmentProfile, catalog: InventoryItemCatalog) -> ServiceResult:
	var fields := PackedStringArray(["schema_version", "body_id", "state_revision", "profile_id", "profile_revision", "body_container_id", "active_hand_slot_id", "equipped", "ledger"])
	if profile == null or catalog == null or not ControlContractValidation.has_exact_fields(record, fields) or not ControlContractValidation.is_integer(record.get("schema_version"), 1, 2):
		return _failure("A complete record and trusted body/item definitions are required.")
	for field in ["body_id", "profile_id", "body_container_id"]:
		if not ControlContractValidation.is_id(record[field]):
			return _failure("Body, profile and container identities must be valid.")
	if not ControlContractValidation.is_integer(record["state_revision"], 0, MAX_EXACT_INTEGER) or not ControlContractValidation.is_integer(record["profile_revision"], 1, MAX_EXACT_INTEGER):
		return _failure("Body inventory revisions must be exact bounded integers.")
	var rules: Dictionary = profile.to_record()
	if record["profile_id"] != rules["definition_id"] or int(record["profile_revision"]) != int(rules["revision"]):
		return _failure("The body profile must resolve to the pinned trusted revision.")
	if typeof(record["active_hand_slot_id"]) != TYPE_STRING or (rules["hand_slot_ids"].is_empty() and record["active_hand_slot_id"] != "") or (not rules["hand_slot_ids"].is_empty() and not rules["hand_slot_ids"].has(record["active_hand_slot_id"])):
		return _failure("The active hand must match the body's configured hands.")
	if typeof(record["ledger"]) != TYPE_DICTIONARY or typeof(record["equipped"]) != TYPE_ARRAY or record["equipped"].size() > rules["slots"].size():
		return _failure("Ledger and bounded equipment records are required.")
	var parsed: ServiceResult = InventoryLedger.from_record(record["ledger"], catalog)
	if not parsed.is_success:
		return parsed
	var ledger: InventoryLedger = parsed.value
	if int(record["schema_version"]) != int(record["ledger"]["schema_version"]): return _failure("Body and ledger versions must agree.")
	var root_found: bool = false
	for container in record["ledger"]["containers"]:
		if container["container_id"] == record["body_container_id"]:
			root_found = container["owner_item_id"] == "" and int(container["capacity"]["max_mass_milligrams"]) == int(rules["max_carried_mass_milligrams"])
	if not root_found:
		return _failure("The body must reference a root with its trusted carried-mass limit.")
	var slots: Dictionary = {}
	var items: Dictionary = {}
	for raw in record["equipped"]:
		if typeof(raw) != TYPE_DICTIONARY:
			return _failure("Each equipment binding must be a record.")
		var binding: Dictionary = raw
		if not ControlContractValidation.has_exact_fields(binding, PackedStringArray(["slot_id", "item_id"])) or not ControlContractValidation.is_id(binding.get("slot_id")) or not ControlContractValidation.is_id(binding.get("item_id")) or slots.has(binding["slot_id"]) or items.has(binding["item_id"]):
			return _failure("Equipment slot and item bindings must be valid and unique.")
		var observed: ServiceResult = ledger.item_observation(binding["item_id"])
		if not observed.is_success:
			return observed
		var item: Dictionary = observed.value
		if item["item"]["container_id"] != record["body_container_id"]:
			return _failure("Equipped items must be direct possessions of this body root.")
		var fit: ServiceResult = profile.assess_slot(binding["slot_id"], PackedStringArray(item["tags"]), item["mass_milligrams"], item["volume_millilitres"])
		if not fit.is_success:
			return fit
		slots[binding["slot_id"]] = true
		items[binding["item_id"]] = true
	var state := BodyInventoryState.new()
	state._record = record.duplicate(true)
	state._record["state_revision"] = int(record["state_revision"])
	state._profile = InventoryEquipmentProfile.from_record(rules).value
	state._catalog = catalog
	state._ledger = ledger
	return ServiceResult.success(state)


static func _failure(message: String) -> ServiceResult:
	return ServiceResult.failure(&"invalid_body_inventory", message)
