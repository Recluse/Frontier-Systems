extends SceneTree

var _failures: int = 0


func _initialize() -> void:
	var catalog := InventoryItemCatalog.new()
	var definitions: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/inventory/items.default.v1.json"))
	for definition in definitions:
		_check(catalog.register_definition(definition).is_success, "item fixture must register")
	_check(not catalog.register_definition(definitions[0]).is_success, "duplicate catalog revision must reject")
	var detached_definition: Dictionary = catalog.get_definition("item.backpack.prototype", 1).value
	detached_definition["mass_milligrams"] = 0
	_check(catalog.get_definition("item.backpack.prototype", 1).value["mass_milligrams"] == 1000000, "catalog must return detached definitions")
	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/inventory/ledger.default.v1.json"))
	var restored: ServiceResult = InventoryLedger.from_record(record, catalog)
	_check(restored.is_success, "default nested ledger must restore")
	if not restored.is_success:
		quit(1)
		return
	var ledger: InventoryLedger = restored.value
	_check(ledger.container_load("body.human-1").value["mass_milligrams"] == 3500000, "root must count backpack, pouch and tool once")
	_check(ledger.container_load("storage.backpack-1").value["mass_milligrams"] == 2500000, "backpack load must include nested tool")
	_check(ledger.container_load("body.human-1").value["volume_millilitres"] == 20000, "rigid external backpack volume must not count inner contents again")
	var before: Dictionary = ledger.to_record()
	_check(not ledger.move_item("backpack-1", "body.human-1", "storage.pouch-1", 0).is_success, "moving backpack inside its descendant must reject")
	_check(ledger.to_record() == before, "rejected cyclic move must be atomic")
	_check(not ledger.move_item("crowbar-1", "wrong-source", "world.tray-1", 0).is_success, "wrong source must reject")
	_check(not ledger.move_item("crowbar-1", "storage.pouch-1", "missing", 0).is_success, "missing destination must reject")
	_check(ledger.move_item("backpack-1", "body.human-1", "world.tray-1", 0).is_success, "container move must carry descendants")
	_check(ledger.container_load("body.human-1").value["mass_milligrams"] == 0 and ledger.container_load("world.tray-1").value["mass_milligrams"] == 3500000, "moving a loaded bag must transfer total mass")
	_check(ledger.to_record()["items"][2]["condition_permille"] == 750, "movement must preserve condition")
	before = ledger.to_record()
	_check(not ledger.move_item("backpack-1", "world.tray-1", "body.human-1", 0).is_success, "stale revision must reject")
	_check(ledger.to_record() == before, "stale move must leave ledger unchanged")
	_check(ledger.move_item("crowbar-1", "storage.pouch-1", "body.human-1", 1).is_success, "tool must leave nested bag independently")
	_check(ledger.container_load("world.tray-1").value["mass_milligrams"] == 1500000 and ledger.container_load("body.human-1").value["mass_milligrams"] == 2000000, "independent move must conserve graph mass")
	_check(InventoryLedger.from_record(JSON.parse_string(JSON.stringify(ledger.to_record())), catalog).is_success, "ledger must round-trip through JSON")
	var detached: Dictionary = ledger.to_record()
	detached["items"].clear()
	_check(ledger.to_record()["items"].size() == 3, "snapshot must be detached")
	var invalid: Dictionary = record.duplicate(true)
	invalid["items"].append(invalid["items"][0].duplicate(true))
	_check(not InventoryLedger.from_record(invalid, catalog).is_success, "duplicate item location must reject")
	invalid = record.duplicate(true)
	invalid["containers"][2]["capacity"]["max_mass_milligrams"] = 16000000
	_check(not InventoryLedger.from_record(invalid, catalog).is_success, "hosted capacity inflation must reject")
	invalid = record.duplicate(true)
	invalid["containers"][0]["capacity"]["max_mass_milligrams"] = 3499999
	_check(not InventoryLedger.from_record(invalid, catalog).is_success, "nested carry mass must enforce root limit")
	invalid = record.duplicate(true)
	invalid["containers"][0]["capacity"]["max_volume_millilitres"] = 19999
	_check(not InventoryLedger.from_record(invalid, catalog).is_success, "volume capacity must enforce limit")
	invalid = record.duplicate(true)
	invalid["containers"][0]["capacity"]["max_items"] = 0
	_check(not InventoryLedger.from_record(invalid, catalog).is_success, "direct item count must enforce limit")
	invalid = record.duplicate(true)
	invalid["items"][2]["definition_id"] = "invented"
	_check(not InventoryLedger.from_record(invalid, catalog).is_success, "unknown definitions must reject")
	invalid = record.duplicate(true)
	invalid["items"][2]["condition_permille"] = 750.5
	_check(not InventoryLedger.from_record(invalid, catalog).is_success, "fractional condition must reject")
	invalid = record.duplicate(true)
	invalid["containers"].remove_at(2)
	_check(not InventoryLedger.from_record(invalid, catalog).is_success, "missing hosted container must reject")
	var limited: Dictionary = record.duplicate(true)
	limited["containers"].append({"container_id": "tiny", "owner_item_id": "", "capacity": {"max_mass_milligrams": 1, "max_volume_millilitres": 1, "max_items": 1, "accepted_tags": ["item.handheld"]}})
	var constrained: InventoryLedger = InventoryLedger.from_record(limited, catalog).value
	before = constrained.to_record()
	_check(not constrained.move_item("crowbar-1", "storage.pouch-1", "tiny", 0).is_success, "full destination must reject transfer")
	_check(constrained.to_record() == before, "capacity rejection must leave both locations unchanged")
	invalid = record.duplicate(true)
	invalid["containers"][0]["capacity"]["accepted_tags"] = ["unsupported.category"]
	_check(not InventoryLedger.from_record(invalid, catalog).is_success, "incompatible container tags must reject")
	var roomy_capacity := {"max_mass_milligrams": InventoryLedger.MAX_EXACT_INTEGER, "max_volume_millilitres": InventoryLedger.MAX_EXACT_INTEGER, "max_items": 512, "accepted_tags": ["item.handheld"]}
	_check(catalog.register_definition({"schema_version": 1, "definition_id": "item.nesting-test", "revision": 1,
		"tags": ["item.handheld"], "mass_milligrams": 1, "volume_millilitres": 1, "storage": roomy_capacity}).is_success, "nesting test definition must register")
	_check(InventoryLedger.from_record(_nested_record(7, roomy_capacity), catalog).is_success, "eight containers of ancestry must be accepted")
	var too_deep: ServiceResult = InventoryLedger.from_record(_nested_record(8, roomy_capacity), catalog)
	_check(not too_deep.is_success and too_deep.message.contains("maximum depth"), "ninth ancestor container must reject")
	_check(catalog.register_definition({"schema_version": 1, "definition_id": "item.overflow-test", "revision": 1,
		"tags": ["item.handheld"], "mass_milligrams": InventoryLedger.MAX_EXACT_INTEGER,
		"volume_millilitres": 1, "storage": null}).is_success, "overflow test definition must register")
	var overflow := {"schema_version": 1, "ledger_id": "overflow", "state_revision": 0,
		"containers": [{"container_id": "root", "owner_item_id": "", "capacity": roomy_capacity}],
		"items": [{"item_id": "large-1", "definition_id": "item.overflow-test", "definition_revision": 1, "condition_permille": 1000, "container_id": "root"},
			{"item_id": "large-2", "definition_id": "item.overflow-test", "definition_revision": 1, "condition_permille": 1000, "container_id": "root"}]}
	var over_mass: ServiceResult = InventoryLedger.from_record(overflow, catalog)
	_check(not over_mass.is_success and over_mass.message.contains("mass overflow"), "exact mass accumulation must reject overflow")
	invalid = record.duplicate(true)
	invalid["state_revision"] = InventoryLedger.MAX_EXACT_INTEGER
	var exhausted: InventoryLedger = InventoryLedger.from_record(invalid, catalog).value
	_check(not exhausted.move_item("backpack-1", "body.human-1", "world.tray-1", InventoryLedger.MAX_EXACT_INTEGER).is_success, "exhausted revision must reject movement")
	if _failures == 0:
		print("Inventory ownership and bounded container scenarios passed.")
	quit(0 if _failures == 0 else 1)


func _nested_record(host_count: int, capacity: Dictionary) -> Dictionary:
	var record := {"schema_version": 1, "ledger_id": "nesting", "state_revision": 0,
		"containers": [{"container_id": "root", "owner_item_id": "", "capacity": capacity.duplicate(true)}], "items": []}
	var parent: String = "root"
	for index in range(host_count):
		var item_id: String = "host-%d" % index
		var container_id: String = "contents-%d" % index
		record["items"].append({"item_id": item_id, "definition_id": "item.nesting-test", "definition_revision": 1, "condition_permille": 1000, "container_id": parent})
		record["containers"].append({"container_id": container_id, "owner_item_id": item_id, "capacity": capacity.duplicate(true)})
		parent = container_id
	record["items"].append({"item_id": "tool", "definition_id": "item.crowbar.prototype", "definition_revision": 1, "condition_permille": 1000, "container_id": parent})
	return record


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
