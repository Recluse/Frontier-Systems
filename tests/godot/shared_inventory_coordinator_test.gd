extends SceneTree

var _failures: int = 0


func _initialize() -> void:
	var catalog := InventoryItemCatalog.new()
	for definition in JSON.parse_string(FileAccess.get_file_as_string("res://data/inventory/items.default.v1.json")):
		catalog.register_definition(definition)
	var profile: InventoryEquipmentProfile = InventoryEquipmentProfile.from_record(JSON.parse_string(FileAccess.get_file_as_string("res://data/inventory/human.v1.json"))).value
	var profiles := {JSON.stringify(["inventory.body.human", 1]): profile}
	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/inventory/shared.default.v1.json"))
	var parsed: ServiceResult = SharedInventoryCoordinator.from_record(record, profiles, catalog)
	_check(parsed.is_success, "shared fixture must restore")
	if not parsed.is_success:
		quit(1)
		return
	var owner: SharedInventoryCoordinator = parsed.value
	var take: Dictionary = _request("take-1", "take", "crowbar-1", "storage.pouch-1", "body.human-2", "", 0)
	var moved: ServiceResult = owner.transact(take)
	_check(moved.is_success, "nested target item must transfer to actor")
	var after: Dictionary = owner.to_record()
	_check(int(after["state_revision"]) == 1 and int(after["bodies"][0]["state_revision"]) == 1 and int(after["bodies"][1]["state_revision"]) == 1, "shared transfer must advance both body revisions together")
	_check(after["ledger"]["items"][2]["container_id"] == "body.human-2" and after["ledger"]["items"].size() == 3, "transfer must preserve one item identity")
	_check(after["ledger"]["items"][2]["condition_permille"] == 750, "cross-body transfer must preserve item condition")
	_check(owner.transact(JSON.parse_string(JSON.stringify(take))).is_success and owner.to_record() == after, "identical JSON retry must return receipt without mutation")
	var changed: Dictionary = take.duplicate(true)
	changed["destination_container_id"] = "world.tray-1"
	_check(not owner.transact(changed).is_success and owner.to_record() == after, "changed intent under retained ID must reject")
	var stale: Dictionary = _request("stale", "insert", "crowbar-1", "body.human-2", "storage.pouch-1", "", 0)
	_check(not owner.transact(stale).is_success, "stale global revision must reject")
	var incompatible: Dictionary = _request("bad-equip", "equip", "crowbar-1", "body.human-2", "body.human-1", "clothing.uniform", 1)
	_check(not owner.transact(incompatible).is_success and owner.to_record() == after, "incompatible target equipment must reject atomically")
	var equip: Dictionary = _request("equip-1", "equip", "crowbar-1", "body.human-2", "body.human-1", "hand.left", 1)
	_check(owner.transact(equip).is_success, "actor must equip owned tool onto target's free hand")
	_check(owner.to_record()["bodies"][0]["equipped"].size() == 2, "target must gain equipment binding")
	after = owner.to_record()
	_check(not owner.transact(_request("bad-take", "take", "crowbar-1", "body.human-1", "body.human-2", "", 2)).is_success, "taking fitted hardware must require unequip action")
	_check(owner.to_record() == after, "failed fitted take must preserve bindings")
	_check(owner.transact(_request("unequip-1", "unequip", "crowbar-1", "body.human-1", "body.human-2", "hand.left", 2)).is_success, "target unequip must transfer and clear binding atomically")
	_check(owner.to_record()["bodies"][0]["equipped"].size() == 1, "target slot must be released")
	_check(SharedInventoryCoordinator.from_record(JSON.parse_string(JSON.stringify(owner.to_record())), profiles, catalog).is_success, "shared snapshot must round-trip with receipts")
	var loaded: Dictionary = record.duplicate(true)
	loaded["ledger"]["containers"][4]["capacity"]["max_volume_millilitres"] = 1
	var limited: SharedInventoryCoordinator = SharedInventoryCoordinator.from_record(loaded, profiles, catalog).value
	after = limited.to_record()
	_check(not limited.transact(take).is_success and limited.to_record() == after, "destination capacity must reject without changing either body")
	var job_rules: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/inventory/body-interactions.default.v1.json"))
	job_rules["duration_ticks"]["take"] = 1
	var policy: BodyInventoryInteractionPolicy = BodyInventoryInteractionPolicy.from_record(job_rules).value
	var job_record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/inventory/interaction-job.default.v1.json"))
	var observed := {"distance_millimetres": 1000, "actor_can_manipulate": true, "target_available": true, "target_resisting": false, "target_moved": false, "path_accessible": true}
	var context := {"actor_control_epoch": 0, "target_action_epoch": 0, "actor_inventory_revision": 0, "target_inventory_revision": 0}
	var job: BodyInventoryInteractionJob = BodyInventoryInteractionJob.start(job_record, policy, observed).value
	var fresh: SharedInventoryCoordinator = SharedInventoryCoordinator.from_record(record, profiles, catalog).value
	var completion: Dictionary = _request(job_record["job_id"], "take", "crowbar-1", "storage.pouch-1", "body.human-2", "", 0)
	_check(not fresh.complete_job(job, 0, context, observed, completion).is_success, "unfinished job must not transfer")
	job.advance(1, context, observed)
	_check(fresh.complete_job(job, 1, context, observed, completion).is_success, "fresh timed completion must transfer and record receipt")
	after = fresh.to_record()
	_check(fresh.complete_job(job, 2, context, observed, completion).is_success and fresh.to_record() == after, "acknowledged retry must not require another physical effect")
	var stale_owner: SharedInventoryCoordinator = SharedInventoryCoordinator.from_record(record, profiles, catalog).value
	_check(stale_owner.transact(take).is_success, "another transfer must change current body revisions")
	after = stale_owner.to_record()
	_check(not stale_owner.complete_job(job, 1, context, observed, completion).is_success and stale_owner.to_record() == after, "fresh job candidate must still match actual participating body revisions")
	var churn: SharedInventoryCoordinator = SharedInventoryCoordinator.from_record(record, profiles, catalog).value
	for index in range(130):
		var outgoing: bool = index % 2 == 0
		var source: String = "storage.pouch-1" if index == 0 else ("body.human-1" if outgoing else "body.human-2")
		var request: Dictionary = _request("churn-%d" % index, "take" if outgoing else "insert", "crowbar-1", source, "body.human-2" if outgoing else "body.human-1", "", index)
		_check(churn.transact(request).is_success, "bounded receipt churn must preserve valid transfers")
	_check(churn.to_record()["receipts"].size() == 128, "retained receipts must stay bounded")
	_check(not churn.transact(take).is_success, "old unretained revision cannot reapply transfer")
	var bag_owner: SharedInventoryCoordinator = SharedInventoryCoordinator.from_record(record, profiles, catalog).value
	_check(bag_owner.transact(_request("bag-remove", "unequip", "backpack-1", "body.human-1", "body.human-2", "back", 0)).is_success, "loaded backpack removal must transfer its subtree")
	var bag_ledger: InventoryLedger = InventoryLedger.from_record(bag_owner.to_record()["ledger"], catalog).value
	_check(bag_ledger.container_load("body.human-1").value["mass_milligrams"] == 0 and bag_ledger.container_load("body.human-2").value["mass_milligrams"] == 3500000, "loaded bag transfer must conserve all descendant mass")
	_check(bag_ledger.root_for_container("storage.pouch-1").value == "body.human-2", "nested container ancestry must follow the transferred item")
	var invalid: Dictionary = record.duplicate(true)
	invalid["bodies"][1]["body_container_id"] = "body.human-1"
	_check(not SharedInventoryCoordinator.from_record(invalid, profiles, catalog).is_success, "two bodies cannot claim one root")
	invalid = owner.to_record()
	invalid["receipts"].append(invalid["receipts"][0].duplicate(true))
	_check(not SharedInventoryCoordinator.from_record(invalid, profiles, catalog).is_success, "duplicate retained receipts must reject recovery")
	after = bag_owner.to_record()
	var wrong_root: Dictionary = _request("wrong-root", "insert", "crowbar-1", "storage.pouch-1", "world.tray-1", "", 1)
	_check(not bag_owner.transact(wrong_root).is_success and bag_owner.to_record() == after, "foreign destination roots must reject atomically")
	if _failures == 0:
		print("Shared inventory atomic transfer and receipt scenarios passed.")
	quit(0 if _failures == 0 else 1)


func _request(id: String, action: String, item: String, source: String, destination: String, slot: String, revision: int) -> Dictionary:
	return {"request_id": id, "action": action, "actor_body_id": "body.human-2", "target_body_id": "body.human-1", "item_id": item,
		"source_container_id": source, "destination_container_id": destination, "slot_id": slot, "expected_revision": revision}


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
