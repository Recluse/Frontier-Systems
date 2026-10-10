extends SceneTree

var _failures: int = 0


func _initialize() -> void:
	var catalog := InventoryItemCatalog.new()
	var definitions: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/inventory/items.default.v1.json"))
	for definition in definitions:
		_check(catalog.register_definition(definition).is_success, "item fixture must register")
	var profile_record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/inventory/human.v1.json"))
	var profile: InventoryEquipmentProfile = InventoryEquipmentProfile.from_record(profile_record).value
	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/inventory/body.default.v1.json"))
	var parsed: ServiceResult = BodyInventoryState.from_record(record, profile, catalog)
	_check(parsed.is_success, "default body fixture must restore")
	if not parsed.is_success:
		quit(1)
		return
	var body: BodyInventoryState = parsed.value
	_check(body.switch_hand(0).is_success, "active hand must switch")
	_check(body.to_record()["active_hand_slot_id"] == "hand.right" and int(body.to_record()["ledger"]["state_revision"]) == 0, "selection must not move physical items")
	_check(body.equip_item("crowbar-1", "storage.pouch-1", "hand.right", 1).is_success, "nested owned tool must equip into active hand")
	var before: Dictionary = body.to_record()
	_check(not body.equip_item("backpack-1", "body.human-1", "hand.right", 2).is_success, "occupied hand must reject another item")
	_check(not body.equip_item("crowbar-1", "body.human-1", "clothing.uniform", 2).is_success, "incompatible clothing slot must reject tool")
	_check(body.to_record() == before, "failed equip must preserve equipment and ledger atomically")
	_check(not body.move_item("crowbar-1", "body.human-1", "world.tray-1", 2).is_success, "ordinary transfer must not bypass equipment ownership")
	_check(body.unequip_item("hand.right", "storage.backpack-1", 2).is_success, "tool must unequip into backpack")
	_check(body.equip_item("crowbar-1", "storage.backpack-1", "hand.left", 3).is_success, "tool must equip into other hand")
	var ledger_revision: int = int(body.to_record()["ledger"]["state_revision"])
	_check(body.equip_item("crowbar-1", "body.human-1", "hand.right", 4).is_success, "equipped tool may move to a free hand")
	_check(int(body.to_record()["ledger"]["state_revision"]) == ledger_revision, "hand reassignment must not duplicate or relocate item")
	before = body.to_record()
	_check(not body.switch_hand(4).is_success and body.to_record() == before, "stale body revision must reject selection")
	_check(not body.select_hand("invented", 5).is_success, "unknown hands must reject")
	_check(BodyInventoryState.from_record(JSON.parse_string(JSON.stringify(body.to_record())), profile, catalog).is_success, "combined state must recover through JSON")
	var invalid: Dictionary = record.duplicate(true)
	invalid["equipped"].append({"slot_id": "hand.left", "item_id": "backpack-1"})
	_check(not BodyInventoryState.from_record(invalid, profile, catalog).is_success, "same item cannot occupy two slots in v1")
	invalid = record.duplicate(true)
	invalid["equipped"].append({"slot_id": "back", "item_id": "crowbar-1"})
	_check(not BodyInventoryState.from_record(invalid, profile, catalog).is_success, "duplicate slot occupancy must reject")
	invalid = record.duplicate(true)
	invalid["equipped"] = [{"slot_id": "hand.left", "item_id": "crowbar-1"}]
	_check(not BodyInventoryState.from_record(invalid, profile, catalog).is_success, "nested item cannot claim direct equipped location")
	invalid = record.duplicate(true)
	invalid["ledger"]["containers"][0]["capacity"]["max_mass_milligrams"] = 40000001
	_check(not BodyInventoryState.from_record(invalid, profile, catalog).is_success, "body root capacity cannot exceed trusted profile")
	var limited_rules: Dictionary = profile_record.duplicate(true)
	for slot in limited_rules["slots"]:
		if slot["slot_id"] == "back":
			slot["max_mass_milligrams"] = 2000000
	var limited_profile: InventoryEquipmentProfile = InventoryEquipmentProfile.from_record(limited_rules).value
	_check(not BodyInventoryState.from_record(record, limited_profile, catalog).is_success, "loaded backpack mass must count against equipment slot")
	var light_record: Dictionary = record.duplicate(true)
	light_record["ledger"]["items"][2]["container_id"] = "world.tray-1"
	var light: BodyInventoryState = BodyInventoryState.from_record(light_record, limited_profile, catalog).value
	before = light.to_record()
	_check(not light.move_item("crowbar-1", "world.tray-1", "storage.pouch-1", 0).is_success, "filling equipped backpack must revalidate loaded slot mass")
	_check(light.to_record() == before, "failed backpack fill must preserve both root locations")
	var detached: Dictionary = body.to_record()
	detached["equipped"].clear()
	_check(body.to_record()["equipped"].size() == 2, "combined snapshots must be detached")
	var ai_record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/inventory/station-ai.v1.json"))
	var ai_profile: InventoryEquipmentProfile = InventoryEquipmentProfile.from_record(ai_record).value
	var ai_state := {"schema_version": 1, "body_id": "station-ai-1", "state_revision": 0,
		"profile_id": "inventory.body.station-ai", "profile_revision": 1, "body_container_id": "ai.root", "active_hand_slot_id": "", "equipped": [],
		"ledger": {"schema_version": 1, "ledger_id": "ai.inventory", "state_revision": 0, "items": [], "containers": [{"container_id": "ai.root", "owner_item_id": "", "capacity": {"max_mass_milligrams": 0, "max_volume_millilitres": 0, "max_items": 0, "accepted_tags": ["item.handheld"]}}]}}
	var ai: ServiceResult = BodyInventoryState.from_record(ai_state, ai_profile, catalog)
	_check(ai.is_success and not ai.value.switch_hand(0).is_success, "handless AI must have valid state without invented hands")
	invalid = record.duplicate(true)
	invalid["state_revision"] = BodyInventoryState.MAX_EXACT_INTEGER
	var exhausted: BodyInventoryState = BodyInventoryState.from_record(invalid, profile, catalog).value
	_check(not exhausted.switch_hand(BodyInventoryState.MAX_EXACT_INTEGER).is_success, "exhausted revisions must reject changes")
	if _failures == 0:
		print("Body equipment and active-hand transaction scenarios passed.")
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
