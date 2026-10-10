extends RefCounted
class_name InventoryEquipmentProfile

## Body-specific inventory limits. This contract owns no items or permissions.
const MAX_EXACT_INTEGER: int = 9007199254740990
var _record: Dictionary = {}


func to_record() -> Dictionary:
	return _record.duplicate(true)


## Returns the next configured hand. Selecting a hand does not move its item.
func next_hand(current_hand_id: String) -> ServiceResult:
	var hands: Array = _record["hand_slot_ids"]
	if hands.is_empty():
		return ServiceResult.failure(&"body_has_no_hands", "This body has no hand slots.")
	var index: int = hands.find(current_hand_id)
	if index < 0:
		return ServiceResult.failure(&"unknown_active_hand", "The selected hand is not part of this body profile.")
	return ServiceResult.success(hands[(index + 1) % hands.size()])


## Preliminary single-slot fit only. Inputs must come from trusted item records.
## Aggregate load, occupancy, accessibility and ownership need an inventory owner.
func assess_slot(slot_id: String, item_tags: PackedStringArray, mass_milligrams: int, volume_millilitres: int) -> ServiceResult:
	if mass_milligrams < 0 or mass_milligrams > MAX_EXACT_INTEGER or volume_millilitres < 0 or volume_millilitres > MAX_EXACT_INTEGER:
		return ServiceResult.failure(&"invalid_item_dimensions", "Item dimensions must be bounded non-negative integers.")
	for slot in _record["slots"]:
		if slot["slot_id"] != slot_id:
			continue
		if mass_milligrams > slot["max_mass_milligrams"] or volume_millilitres > slot["max_volume_millilitres"]:
			return ServiceResult.failure(&"equipment_slot_capacity", "The item exceeds this slot's capacity.")
		for tag in slot["accepted_tags"]:
			if item_tags.has(tag):
				return ServiceResult.success()
		return ServiceResult.failure(&"equipment_slot_incompatible", "The slot does not accept this item's equipment tags.")
	return ServiceResult.failure(&"unknown_equipment_slot", "The slot is not present on this body profile.")


static func from_record(record: Dictionary) -> ServiceResult:
	var fields := PackedStringArray(["schema_version", "definition_id", "revision", "max_carried_mass_milligrams", "hand_slot_ids", "slots"])
	if not ControlContractValidation.has_exact_fields(record, fields) or not ControlContractValidation.is_integer(record.get("schema_version"), 1, 1):
		return ServiceResult.failure(&"invalid_inventory_profile", "A complete versioned inventory profile is required.")
	if not ControlContractValidation.is_id(record["definition_id"]) or not ControlContractValidation.is_integer(record["revision"], 1, MAX_EXACT_INTEGER) or not ControlContractValidation.is_integer(record["max_carried_mass_milligrams"], 0, MAX_EXACT_INTEGER):
		return ServiceResult.failure(&"invalid_inventory_profile_identity", "Profile identity, revision and carry limit must be valid.")
	var hands: ServiceResult = ControlContractValidation.decode_ids(record["hand_slot_ids"], 0, 16)
	if not hands.is_success:
		return hands
	if typeof(record["slots"]) != TYPE_ARRAY or record["slots"].size() > 64:
		return ServiceResult.failure(&"invalid_inventory_slots", "Slots must be a bounded array.")
	var ids := PackedStringArray()
	for raw_slot in record["slots"]:
		if typeof(raw_slot) != TYPE_DICTIONARY:
			return ServiceResult.failure(&"invalid_inventory_slot", "Every slot must be a record.")
		var slot: Dictionary = raw_slot
		if not ControlContractValidation.has_exact_fields(slot, PackedStringArray(["slot_id", "accepted_tags", "max_mass_milligrams", "max_volume_millilitres"])) or not ControlContractValidation.is_id(slot.get("slot_id")) or ids.has(slot["slot_id"]):
			return ServiceResult.failure(&"invalid_inventory_slot", "Slot IDs must be valid and unique with exact fields.")
		var tags: ServiceResult = ControlContractValidation.decode_ids(slot["accepted_tags"], 1, 32)
		if not tags.is_success:
			return tags
		for field in ["max_mass_milligrams", "max_volume_millilitres"]:
			if not ControlContractValidation.is_integer(slot[field], 0, MAX_EXACT_INTEGER):
				return ServiceResult.failure(&"invalid_inventory_slot_capacity", "Slot capacities must be bounded non-negative integers.")
		ids.append(slot["slot_id"])
	for hand in hands.value:
		if not ids.has(hand):
			return ServiceResult.failure(&"unknown_profile_hand", "Every hand must reference a configured slot.")
	var profile := InventoryEquipmentProfile.new()
	profile._record = record.duplicate(true)
	return ServiceResult.success(profile)
