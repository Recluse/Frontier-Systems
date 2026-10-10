extends SceneTree

var _failures: int = 0


func _initialize() -> void:
	var catalog := InventoryItemCatalog.new()
	for definition in JSON.parse_string(FileAccess.get_file_as_string("res://data/inventory/items.default.v1.json")):
		catalog.register_definition(definition)
	var profile: InventoryEquipmentProfile = InventoryEquipmentProfile.from_record(JSON.parse_string(FileAccess.get_file_as_string("res://data/inventory/human.v1.json"))).value
	var profiles := {JSON.stringify(["inventory.body.human", 1]): profile}
	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/inventory/shared.default.v1.json"))
	var owner: SharedInventoryCoordinator = SharedInventoryCoordinator.from_record(record, profiles, catalog).value
	var before: Dictionary = owner.to_record()
	var rules: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/inventory/body-interactions.default.v1.json"))
	rules["duration_ticks"]["search"] = 1
	var policy: BodyInventoryInteractionPolicy = BodyInventoryInteractionPolicy.from_record(rules).value
	var observation := {"distance_millimetres": 1000, "actor_can_manipulate": true, "target_available": true, "target_resisting": false, "target_moved": false, "path_accessible": true}
	var context := {"actor_control_epoch": 0, "target_action_epoch": 0, "actor_inventory_revision": 0, "target_inventory_revision": 0}
	var job_record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/inventory/interaction-job.default.v1.json"))
	job_record["action"] = "search"
	job_record["item_id"] = ""
	job_record["target_container_id"] = "storage.backpack-1"
	var job: BodyInventoryInteractionJob = BodyInventoryInteractionJob.start(job_record, policy, observation).value
	var views := InventorySearchViews.new(3)
	_check(not views.grant(job, 0, owner, "principal.actor", context, observation).is_success, "unfinished search must not reveal contents")
	job.advance(1, context, observation)
	var granted: ServiceResult = views.grant(job, 1, owner, "principal.actor", context, observation)
	_check(granted.is_success, "fresh completed search must produce a scoped view")
	if not granted.is_success:
		quit(1)
		return
	var id: String = granted.value["view_id"]
	_check(granted.value["items"].size() == 1 and granted.value["items"][0]["item_id"] == "pouch-1", "backpack search must reveal direct pouch but not its crowbar contents")
	_check(granted.value["items"][0]["has_storage"] and not granted.value.has("ledger"), "view must describe storage without dumping canonical ledger")
	granted.value["items"].clear()
	_check(views.read(id, 1, owner, "principal.actor", context, observation).value["items"].size() == 1, "view reads must be detached")
	_check(not views.read(id, 1, owner, "principal.other", context, observation).is_success, "different principal must not read view")
	_check(not views.close(id, "principal.other").is_success and views.diagnostics()["active_views"] == 1, "different principal must not close another view")
	_check(views.grant(job, 2, owner, "principal.actor", context, observation).is_success, "retained identical search delivery may return its existing view")
	_check(views.read(id, 3, owner, "principal.actor", context, observation).is_success, "view must remain usable before expiry")
	_check(not views.read(id, 4, owner, "principal.actor", context, observation).is_success and views.diagnostics()["active_views"] == 0, "view must expire exactly at its lifetime boundary")
	_check(not views.grant(job, 4, owner, "principal.actor", context, observation).is_success, "expired view must not renew from old completion tick")
	for field in BodyInventoryInteractionJob.CONTEXT_FIELDS:
		var guarded := InventorySearchViews.new()
		guarded.grant(job, 1, owner, "principal.actor", context, observation)
		var changed: Dictionary = context.duplicate(true)
		changed[field] = 1
		_check(not guarded.read(id, 2, owner, "principal.actor", changed, observation).is_success and guarded.diagnostics()["active_views"] == 0, "context change must revoke view: " + field)
	for field in ["target_resisting", "target_moved", "path_accessible", "target_available", "actor_can_manipulate"]:
		var guarded := InventorySearchViews.new()
		guarded.grant(job, 1, owner, "principal.actor", context, observation)
		var changed: Dictionary = observation.duplicate(true)
		changed[field] = field in ["target_resisting", "target_moved"]
		_check(not guarded.read(id, 2, owner, "principal.actor", context, changed).is_success and guarded.diagnostics()["active_views"] == 0, "physical change must revoke view: " + field)
	var reach_guard := InventorySearchViews.new()
	reach_guard.grant(job, 1, owner, "principal.actor", context, observation)
	var far: Dictionary = observation.duplicate(true)
	far["distance_millimetres"] = 1501
	_check(not reach_guard.read(id, 2, owner, "principal.actor", context, far).is_success, "lost reach must revoke view")
	var identity_guard := InventorySearchViews.new()
	identity_guard.grant(job, 1, owner, "principal.actor", context, observation)
	var replacement: SharedInventoryCoordinator = SharedInventoryCoordinator.from_record(record, profiles, catalog).value
	_check(not identity_guard.read(id, 2, replacement, "principal.actor", context, observation).is_success, "owner replacement must revoke even with identical IDs and revision")
	var changed_owner: SharedInventoryCoordinator = SharedInventoryCoordinator.from_record(record, profiles, catalog).value
	var mutation_guard := InventorySearchViews.new()
	mutation_guard.grant(job, 1, changed_owner, "principal.actor", context, observation)
	var request := {"request_id": "take-after-search", "action": "take", "actor_body_id": "body.human-2", "target_body_id": "body.human-1", "item_id": "crowbar-1", "source_container_id": "storage.pouch-1", "destination_container_id": "body.human-2", "slot_id": "", "expected_revision": 0}
	changed_owner.transact(request)
	_check(not mutation_guard.read(id, 2, changed_owner, "principal.actor", context, observation).is_success, "canonical inventory change must revoke even if caller supplies old context")
	var closed := InventorySearchViews.new()
	closed.grant(job, 1, owner, "principal.actor", context, observation)
	closed.revoke_principal("principal.actor")
	_check(closed.diagnostics()["active_views"] == 0, "disconnect/control cleanup must revoke principal views")
	var bounded := InventorySearchViews.new()
	for index in range(65):
		var next_record: Dictionary = job_record.duplicate(true)
		next_record["job_id"] = "search-%d" % index
		var next_job: BodyInventoryInteractionJob = BodyInventoryInteractionJob.start(next_record, policy, observation).value
		next_job.advance(1, context, observation)
		var result: ServiceResult = bounded.grant(next_job, 1, owner, "principal.actor", context, observation)
		_check(result.is_success == (index < 64), "search admission must enforce capacity")
	_check(bounded.diagnostics()["active_views"] == 64, "search views must remain bounded")
	_check(owner.to_record() == before, "search projection/grants must not mutate canonical inventory")
	if _failures == 0:
		print("Scoped inventory search and revocation scenarios passed.")
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
