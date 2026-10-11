extends SceneTree

class Sessions extends InventoryControllerSessionProvider:
	func permits_inventory(_principal: StringName, session: StringName, world: StringName, region: StringName) -> bool:
		return session in [&"one", &"two", &"other"] and world == &"world.test" and region == &"region.test"

var _failures: int = 0
var _inventory: InventorySimulationSystem
var _health: HealthSimulationSystem
var _authority: InventoryControllerAuthority
var _tick: int = 0
const ACTOR: StringName = &"local-inventory-actor"
const TARGET: StringName = &"local-inventory-target"
const OTHER: StringName = &"local-extra-c"

func _initialize() -> void:
	_setup()
	_check(_authority.bind(&"body.human-2", ACTOR, &"one", 0).is_success, "initial canonical bind")
	var token: InventoryControllerToken = _authority.pin(_context(ACTOR, &"one")).value
	_searches()
	_grips()
	_jobs()
	var before: Dictionary = _inventory.capture_snapshot().value
	var other_job: Dictionary = before["jobs"][1].duplicate(true)
	_check(_inventory.profiling_counters()["search_views"] == 2, "two live canonical search views")
	_check(_authority.replace(&"body.human-2", ACTOR, &"two", 1).value == 2, "replacement commits lifecycle")
	var after: Dictionary = _inventory.capture_snapshot().value
	_check(not _authority.validate(token, _context(ACTOR, &"one"), &"body.human-2").is_success, "replacement fences actual old token")
	_check(after["jobs"] == [other_job], "replacement removes only participating job")
	_check(_inventory.profiling_counters()["search_views"] == 1 and _inventory.read_search(_context(OTHER), "search.other").is_success, "unrelated body view survives")
	_check(not _inventory.read_search(_context(ACTOR), "search.actor").is_success, "old actor search unavailable immediately")
	_check(after["owner"] == before["owner"] and after["world_storage"] == before["world_storage"], "stable items equipment roots and receipts conserved")
	_check(after["bodies"][0] == before["bodies"][0] and after["bodies"][2] == before["bodies"][2] and after["bodies"][3] == before["bodies"][3], "other canonical body metadata unchanged")
	_check(after["grips"]["state_revision"] == int(before["grips"]["state_revision"]) + 1 and after["grips"]["receipts"] == before["grips"]["receipts"], "one grip lifecycle revision without player receipt")
	_check(after["grips"]["sessions"][0]["participants"] == [{"body_id": "body.human-1", "hand_ids": ["hand.right"]}], "cooperative grip preserves remaining physical reservation")
	_check(after["grips"]["sessions"][1] == before["grips"]["sessions"][1], "unrelated grip session preserved exactly")
	_check(not _inventory.local_grip_observation(_context(TARGET)).value["sessions"][0]["movement_available"], "remaining group reassessed without sufficient force")
	_check(_inventory.local_observation(_context(ACTOR)).value["outcomes"].back()["error_code"] == "controller_invalidated", "existing bounded outcome API reports cancellation")
	# New work is possible under the new canonical epoch; failed transitions must
	# preserve live views, progress, reservations and opaque token identity.
	_send(ACTOR, "start", _intent("search", "body.human-1", "storage.pouch-1"), "search.fresh")
	_step(120)
	_send(ACTOR, "grip_join", _join("session.crate", "fixture.salvage-crate", "move_world_object", 4), "grip.fresh")
	_send(ACTOR, "start", _intent("take", "body.human-1", "storage.pouch-1"), "job.fresh")
	token = _authority.pin(_context(ACTOR, &"two")).value
	before = _inventory.capture_snapshot().value
	_check(not _authority.replace(&"body.human-2", ACTOR, &"one", 1).is_success, "stale lifecycle rejected")
	var expected: Dictionary = _inventory.controller_candidate().value["body.human-2"]
	_check(not _inventory.commit_control_epoch(expected, 4).is_success, "nonsequential canonical transition rejected")
	var foreign: Dictionary = expected.duplicate(true)
	foreign["principal_id"] = "foreign"
	_check(not _inventory.commit_control_epoch(foreign, 3).is_success, "canonical compare rejects mismatch")
	_check(_inventory.capture_snapshot().value == before and _authority.pin(_context(ACTOR, &"two")).value == token and _inventory.read_search(_context(ACTOR), "search.fresh").is_success, "failed compare preserves full canonical state token and view")
	# Exact bound reached by test-only owner construction, not millions of commands.
	var exhausted: Dictionary = before["grips"].duplicate(true)
	exhausted["state_revision"] = PhysicalGripOwner.MAX_EXACT_INTEGER
	_inventory._grips = PhysicalGripOwner.from_record(exhausted, false).value
	before = _inventory.capture_snapshot().value
	_check(not _authority.revoke(&"body.human-2", ACTOR, 2).is_success, "grip exhaustion rejects entire revoke")
	_check(_inventory.capture_snapshot().value == before and _authority.pin(_context(ACTOR, &"two")).value == token and _inventory.read_search(_context(ACTOR), "search.fresh").is_success, "failed preparation preserves epoch jobs grips token and search")
	exhausted["state_revision"] = 5
	_inventory._grips = PhysicalGripOwner.from_record(exhausted, false).value
	_check(_authority.revoke(&"body.human-2", ACTOR, 2).value == 3, "trusted revoke commits after valid preparation")
	_check(not _authority.validate(token, _context(ACTOR, &"two"), &"body.human-2").is_success and _inventory.capture_snapshot().value["jobs"].is_empty() and _inventory.profiling_counters()["search_views"] == 2 and not _inventory.read_search(_context(ACTOR), "search.fresh").is_success, "revoke retires scoped work view and token while unrelated views survive")
	_test_restore()
	_inventory.free()
	_health.free()
	print("Inventory controller lifecycle invalidation: %d failures" % _failures)
	quit(0 if _failures == 0 else 1)

func _setup() -> void:
	_inventory = InventorySimulationSystem.new()
	_check(_inventory.configure_defaults().is_success, "canonical inventory fixture configured")
	var snapshot: Dictionary = _inventory.capture_snapshot().value
	for suffix in ["c", "d"]:
		var id: String = "body.extra-" + suffix
		var body: Dictionary = snapshot["owner"]["bodies"][1].duplicate(true)
		body["body_id"] = id
		body["body_container_id"] = id
		snapshot["owner"]["bodies"].append(body)
		var container: Dictionary = snapshot["owner"]["ledger"]["containers"].back().duplicate(true)
		container["container_id"] = id
		snapshot["owner"]["ledger"]["containers"].append(container)
		var metadata: Dictionary = snapshot["bodies"][1].duplicate(true)
		metadata["body_id"] = id
		metadata["principal_id"] = "local-extra-" + suffix
		snapshot["bodies"].append(metadata)
	_check(_inventory.restore_snapshot_record(snapshot, 0).is_success, "validated four-body canonical fixture")
	_health = HealthSimulationSystem.new()
	_check(_health.configure_bodies(["body.human-1", "body.human-2", "body.extra-c", "body.extra-d"]).is_success and _inventory.bind_health(_health).is_success, "actual health owner enables fixture actions")
	_authority = InventoryControllerAuthority.new()
	_check(_authority.initialize(&"world.test", &"region.test", InventoryRuntimeControllerOwner.new(_inventory), Sessions.new()).is_success, "actual runtime controller owner")

func _searches() -> void:
	_send(ACTOR, "start", _intent("search", "body.human-1", "storage.pouch-1"), "search.actor")
	_send(OTHER, "start", _intent("search", "body.extra-d", "body.extra-d"), "search.other")
	_step(120)
	_check(_inventory.read_search(_context(ACTOR), "search.actor").is_success and _inventory.read_search(_context(OTHER), "search.other").is_success, "search jobs complete through canonical runtime")

func _grips() -> void:
	_send(ACTOR, "grip_join", _join("session.crate", "fixture.salvage-crate", "move_world_object", 0), "grip.actor")
	_send(TARGET, "grip_join", _join("session.crate", "fixture.salvage-crate", "move_world_object", 1), "grip.target")
	_send(OTHER, "grip_join", _join("session.other", "fixture.ladder", "pull_along", 2), "grip.other")

func _jobs() -> void:
	_send(ACTOR, "start", _intent("take", "body.human-1", "storage.pouch-1"), "job.actor")
	_send(OTHER, "start", _intent("search", "body.extra-d", "body.extra-d"), "job.other")
	_check(_inventory.profiling_counters()["jobs"] == 2, "both bodies own real runtime jobs")

func _test_restore() -> void:
	_check(_authority.bind(&"body.human-2", ACTOR, &"one", 3).is_success, "fresh binding after revoke")
	_send(ACTOR, "grip_join", _join("session.crate", "fixture.salvage-crate", "move_world_object", 6), "grip.restore")
	_send(ACTOR, "start", _intent("take", "body.human-1", "storage.pouch-1"), "job.restore")
	_step(179)
	var saved: Dictionary = _inventory.capture_snapshot().value
	var token: InventoryControllerToken = _authority.pin(_context(ACTOR, &"one")).value
	_check(saved["jobs"][0]["job"]["progress_ticks"] == 179, "actual transfer is one tick from completion")
	_check(_inventory.restore_snapshot_record(saved, _tick).is_success, "actual canonical restore pauses work")
	_check(not _authority.revoke(&"body.human-2", ACTOR, 4).is_success and _inventory.profiling_counters()["jobs"] == 1, "unreconciled restore blocks lifecycle without cancelling restored work")
	_check(_authority.reconcile_after_restore().is_success, "explicit restore reconciliation")
	var before: Dictionary = _inventory.capture_snapshot().value
	_check(_authority.bind(&"body.human-2", ACTOR, &"one", 4).value == 5, "same-session fresh restored bind invalidates paused ownership")
	_check(not _authority.validate(token, _context(ACTOR, &"one"), &"body.human-2").is_success and _inventory.capture_snapshot().value["jobs"].is_empty(), "restored stale job/token cannot revive")
	_check(_inventory.capture_snapshot().value["owner"] == before["owner"] and _inventory.capture_snapshot().value["grips"]["sessions"][0]["paused"], "restore bind conserves inventory and remaining paused grip")
	_send(ACTOR, "start", _intent("search", "body.human-1", "storage.pouch-1"), "search.target-transition")
	_step(120)
	_send(ACTOR, "start", _intent("take", "body.human-1", "storage.pouch-1"), "job.final")
	_step(179)
	before = _inventory.capture_snapshot().value
	var target: Dictionary = _inventory.controller_candidate().value["body.human-1"]
	_check(_inventory.commit_control_epoch(target, int(target["control_epoch"]) + 1).is_success, "target controller transition before final tick")
	_check(_inventory.profiling_counters()["search_views"] == 0, "target lifecycle revokes observing actor view immediately")
	_step(1)
	_check(_inventory.capture_snapshot().value["owner"] == before["owner"] and _inventory.capture_snapshot().value["jobs"].is_empty(), "target invalidation prevents same-boundary transfer and receipt")
	_check(_inventory.capture_snapshot().value["grips"]["sessions"].size() == 1 and _inventory.capture_snapshot().value["grips"]["sessions"][0]["session_id"] == "session.other", "last affected participant releases target without touching unrelated grip")

func _send(principal: StringName, operation: String, payload: Dictionary, id: String) -> void:
	var result: ServiceResult = _inventory.apply_local(_context(principal), id, operation, payload, _tick + 1)
	_check(result.is_success, id + ": " + result.message)
	_step(1)

func _step(count: int) -> void:
	for index in range(count):
		_tick += 1
		_inventory.simulate_tick(_tick, 1.0 / 60.0)

func _context(principal: StringName, session: StringName = &"one") -> AuthenticatedCommandContext:
	return AuthenticatedCommandContext.from_authenticated_session(principal, session, &"world.test", &"region.test", PackedStringArray(["inventory.operate"]))

func _intent(action: String, target: String, container: String) -> Dictionary:
	return {"action": action, "target_body_id": target, "target_container_id": container, "item_id": "crowbar-1" if action == "take" else "", "slot_id": "", "destination_container_id": "body.human-2" if action == "take" else "", "expected_revision": 0}

func _join(id: String, target: String, action: String, revision: int) -> Dictionary:
	return {"session_id": id, "expected_revision": revision, "target_id": target, "action": action, "hand_ids": ["hand.right"]}

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
