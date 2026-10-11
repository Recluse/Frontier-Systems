extends SceneTree

class Sessions extends InventoryControllerSessionProvider:
	func permits_inventory(principal: StringName, session: StringName, world: StringName, region: StringName) -> bool:
		return principal in [ACTOR, TARGET, OTHER] and session in [&"one", &"two", &"target", &"other"] and world == &"world.test" and region == &"region.test"

const ACTOR: StringName = &"local-inventory-actor"
const TARGET: StringName = &"local-inventory-target"
const OTHER: StringName = &"local-extra-c"
var _failures: int = 0
var _tick: int = 0
var _inventory: InventorySimulationSystem
var _health: HealthSimulationSystem
var _queue: InventoryRuntimeCommandQueue
var _authority: InventoryControllerAuthority
var _actor: InventoryControllerToken
var _target: InventoryControllerToken
var _other: InventoryControllerToken
var _session: StringName = &"one"
var _trace: Array = []


func _initialize() -> void:
	var first: Array = _run()
	_check(_run() == first, "independent fixed-tick runs produce identical checkpoints and observations")
	print("Queued inventory job lifecycle: %d failures" % _failures)
	quit(0 if _failures == 0 else 1)


func _run() -> Array:
	_setup()
	_send(_actor, _context(), "search.actor", "start", _intent("search"))
	_check(_job("search.actor")["progress_ticks"] == 0, "admitted start gains no immediate progress")
	_step(119)
	_check(_job("search.actor")["progress_ticks"] == 119 and not _queue.read_search(_actor, _context(), "search.actor").is_success, "default search takes exactly 120 progress ticks")
	_step(1)
	_check(_queue.read_search(_actor, _context(), "search.actor").value["items"].size() == 1, "completed search exposes direct pouch item")
	_check(not _queue.read_search(_other, _context(OTHER, &"other"), "search.actor").is_success, "other bound actor cannot read search")
	_send(_other, _context(OTHER, &"other"), "search.other", "start", _intent("search", true))
	_step(120)
	_send(_actor, _context(), "grip.actor", "grip_join", _join("session.crate", "fixture.salvage-crate", "move_world_object", 0))
	_send(_target, _context(TARGET, &"target"), "grip.target", "grip_join", _join("session.crate", "fixture.salvage-crate", "move_world_object", 1))
	_send(_other, _context(OTHER, &"other"), "grip.other", "grip_join", _join("session.other", "fixture.ladder", "pull_along", 2))
	_check(_queue.local_grip_observation(_actor, _context()).value["sessions"].size() == 1, "actor sees only participating grip")
	_send(_actor, _context(), "take.replace", "start", _intent("take"))
	_step(178)
	_send(_other, _context(OTHER, &"other"), "job.other", "start", _intent("search", true))
	_check(_job("take.replace")["progress_ticks"] == 179, "transfer is one tick from completion")
	var before: Dictionary = _snapshot()
	var other_job: Dictionary = _job("job.other")
	var other_grip: Dictionary = before["grips"]["sessions"][1]
	_add(_actor, _context(), "stale.resume", "resume", {"job_id": "take.replace"})
	_add(_other, _context(OTHER, &"other"), "other.close", "close_search", {"view_id": "search.other"})
	_check(_authority.replace(&"body.human-2", ACTOR, &"two", 1).is_success, "trusted replacement invalidates participating work before final tick")
	_check(_job("job.other") == other_job and _snapshot()["grips"]["sessions"][1] == other_grip, "replacement preserves unrelated job and grip exactly")
	_check(_snapshot()["owner"] == before["owner"], "replacement conserves item matter and receipts")
	_check(_snapshot()["grips"]["sessions"][0]["participants"].size() == 1, "only replaced participant releases cooperative hands")
	var drained: Array = _step(1)
	_check(drained.size() == 1 and not drained[0]["result"].is_success and _queue.profiling_counters()["pending"] == 1, "denied stale intent consumes bounded drain budget")
	_check(_step(1)[0]["result"].is_success, "unrelated FIFO remainder succeeds next boundary")
	_session = &"two"
	_actor = _authority.pin(_context()).value
	_check(_outcomes(_actor, _context()).back()["error_code"] == "controller_invalidated", "replacement cancellation reported through scoped queue observation")
	_check(not _queue.read_search(_actor, _context(), "search.actor").is_success, "replacement retires actor search")
	_check(_queue.local_observation(_target, _context(TARGET, &"target")).value["outcomes"].is_empty(), "target cannot observe actor outcomes")
	_step(118)
	_check(_queue.read_search(_other, _context(OTHER, &"other"), "job.other").is_success, "unrelated job completes on its original timing")
	_record()
	_send(_actor, _context(), "take.revoke", "start", _intent("take"))
	_step(20)
	before = _snapshot()
	_add(_actor, _context(), "revoked.resume", "resume", {"job_id": "take.revoke"})
	_check(_authority.revoke(&"body.human-2", ACTOR, 2).is_success, "trusted revoke cancels canonical job")
	_check(not _step(1)[0]["result"].is_success, "revoked queued capability denied")
	_step(180)
	_check(_snapshot()["owner"] == before["owner"] and _snapshot()["jobs"].is_empty(), "revoked work cannot later transfer or mint receipt")
	_check(not _queue.local_observation(_actor, _context()).is_success, "revoked token receives no projection")
	_check(_authority.bind(&"body.human-2", ACTOR, &"two", 3).is_success, "fresh bind after revoke")
	_actor = _authority.pin(_context()).value
	_send(_actor, _context(), "take.restore", "start", _intent("take"))
	_step(179)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(_snapshot()))
	_add(_actor, _context(), "restore.pending", "resume", {"job_id": "take.restore"})
	_check(_inventory.restore_snapshot_record(saved, _tick).is_success, "JSON checkpoint restore at final-tick boundary")
	_check(_job("take.restore")["state"] == "paused", "recovered work is paused")
	_check(_snapshot()["grips"]["sessions"][0]["paused"] and _snapshot()["grips"]["sessions"][1]["paused"], "recovered grip reservations stay paused")
	_check(_queue.advance_tick(_tick + 1, 1.0 / 60.0).error_code == &"queue_restored" and _queue.profiling_counters()["pending"] == 0, "restore clears queued intent without advancing")
	_step(180)
	_check(_job("take.restore")["progress_ticks"] == 179 and _snapshot()["owner"] == saved["owner"], "paused restore never completes automatically")
	_check(_authority.reconcile_after_restore().is_success, "trusted reconciliation")
	_check(_authority.bind(&"body.human-2", ACTOR, &"two", 4).is_success, "fresh rebind invalidates old paused work")
	_actor = _authority.pin(_context()).value
	_other = _rebind(OTHER, &"other", &"body.extra-c", 1)
	_target = _rebind(TARGET, &"target", &"body.human-1", 1)
	_check(not _send(_actor, _context(), "resume.invalidated", "resume", {"job_id": "take.restore"}, false).is_success, "fresh identity cannot resume invalidated checkpoint job")
	_check(_snapshot()["owner"] == saved["owner"], "rebind and failed resume conserve owner")
	_record()
	var original_items: Array = saved["owner"]["ledger"]["items"]
	_send(_actor, _context(), "take.complete", "start", _intent("take"))
	_step(179)
	before = _snapshot()
	_check(before["owner"]["receipts"].is_empty(), "no receipt before default transfer duration")
	_check(not _queue.advance_tick(_tick + 2, 1.0 / 60.0).is_success and _snapshot() == before, "skipped boundary cannot fast-forward live transfer")
	_step(1)
	var completed: Dictionary = _snapshot()
	_check(completed["owner"]["receipts"].size() == 1 and completed["owner"]["ledger"]["items"][2]["container_id"] == "body.human-2", "exact final tick transfers once with one receipt")
	var conserved: Array = completed["owner"]["ledger"]["items"].duplicate(true)
	conserved[2]["container_id"] = original_items[2]["container_id"]
	_check(conserved == original_items, "all stable item records conserved except intended location")
	_check(not _queue.advance_tick(_tick, 1.0 / 60.0).is_success and _snapshot() == completed, "duplicate completion boundary is inert")
	_check(_inventory.restore_snapshot_record(JSON.parse_string(JSON.stringify(completed)), _tick).is_success, "completed receipt checkpoint recovery")
	_check(_queue.advance_tick(_tick + 1, 1.0 / 60.0).error_code == &"queue_restored", "completed restore resynchronizes without replay")
	_check(_authority.reconcile_after_restore().is_success, "completed recovery reconciliation")
	_actor = _rebind(ACTOR, &"two", &"body.human-2", 5)
	var recovered_owner: Dictionary = _snapshot()["owner"]
	_check(JSON.parse_string(JSON.stringify(recovered_owner)) == JSON.parse_string(JSON.stringify(completed["owner"])), "recovery preserves serialized owner")
	var retry: Dictionary = _intent("take")
	retry["expected_revision"] = 0
	_check(not _send(_actor, _context(), "take.complete", "start", retry, false).is_success, "retained completion request cannot start duplicate transfer")
	_step(180)
	_check(_snapshot()["owner"] == recovered_owner, "recovered retry and further ticks preserve exactly one transfer receipt")
	_record()
	_inventory.free()
	_health.free()
	return _trace.duplicate(true)


func _setup() -> void:
	_tick = 0
	_session = &"one"
	_trace = []
	_inventory = InventorySimulationSystem.new()
	_check(_inventory.configure_defaults().is_success, "actual default inventory")
	var saved: Dictionary = _snapshot()
	# Reuse lifecycle fixture's validated empty extra bodies; add no item matter.
	for suffix in ["c", "d"]:
		var id: String = "body.extra-" + suffix
		var body: Dictionary = saved["owner"]["bodies"][1].duplicate(true)
		body["body_id"] = id
		body["body_container_id"] = id
		saved["owner"]["bodies"].append(body)
		var container: Dictionary = saved["owner"]["ledger"]["containers"].back().duplicate(true)
		container["container_id"] = id
		saved["owner"]["ledger"]["containers"].append(container)
		var metadata: Dictionary = saved["bodies"][1].duplicate(true)
		metadata["body_id"] = id
		metadata["principal_id"] = "local-extra-" + suffix
		saved["bodies"].append(metadata)
	_check(_inventory.restore_snapshot_record(saved, 0).is_success, "validated four-body fixture")
	_health = HealthSimulationSystem.new()
	_check(_health.configure_bodies(["body.human-1", "body.human-2", "body.extra-c", "body.extra-d"]).is_success and _inventory.bind_health(_health).is_success, "actual health provider")
	_queue = InventoryRuntimeCommandQueue.new()
	_check(_queue.initialize(_inventory, &"world.test", &"region.test", Sessions.new(), 4, 1).is_success, "one exact gate with bounded FIFO")
	_authority = _queue.controller_authority()
	_actor = _rebind(ACTOR, &"one", &"body.human-2", 0)
	_target = _rebind(TARGET, &"target", &"body.human-1", 0)
	_other = _rebind(OTHER, &"other", &"body.extra-c", 0)


func _rebind(principal: StringName, session: StringName, body: StringName, epoch: int) -> InventoryControllerToken:
	_check(_authority.bind(body, principal, session, epoch).is_success, "bind " + String(body))
	return _authority.pin(_context(principal, session)).value


func _context(principal: StringName = ACTOR, session: StringName = &"") -> AuthenticatedCommandContext:
	return AuthenticatedCommandContext.from_authenticated_session(principal, _session if session == &"" else session, &"world.test", &"region.test", PackedStringArray(["inventory.operate"]))


func _intent(action: String, other: bool = false) -> Dictionary:
	return {"action": action, "target_body_id": "body.extra-d" if other else "body.human-1", "target_container_id": "body.extra-d" if other else "storage.pouch-1", "item_id": "crowbar-1" if action == "take" else "", "slot_id": "", "destination_container_id": "body.human-2" if action == "take" else "", "expected_revision": int(_snapshot()["owner"]["state_revision"])}


func _join(id: String, target: String, action: String, revision: int) -> Dictionary:
	return {"session_id": id, "expected_revision": revision, "target_id": target, "action": action, "hand_ids": ["hand.right"]}


func _add(token: InventoryControllerToken, context: AuthenticatedCommandContext, id: String, operation: String, payload: Dictionary) -> void:
	_check(_queue.enqueue(token, context, id, operation, payload).is_success, "enqueue " + id)


func _send(token: InventoryControllerToken, context: AuthenticatedCommandContext, id: String, operation: String, payload: Dictionary, success: bool = true) -> ServiceResult:
	_add(token, context, id, operation, payload)
	var result: ServiceResult = _step(1)[0]["result"]
	_check(result.is_success == success, id + ": " + result.message)
	return result


func _step(count: int) -> Array:
	var results: Array = []
	for index in range(count):
		_tick += 1
		var advanced: ServiceResult = _queue.advance_tick(_tick, 1.0 / 60.0)
		_check(advanced.is_success, "consecutive queue tick")
		if advanced.is_success:
			results = advanced.value
	return results


func _snapshot() -> Dictionary:
	return _inventory.capture_snapshot().value


func _job(id: String) -> Dictionary:
	for entry in _snapshot()["jobs"]:
		if entry["job"]["job_id"] == id:
			return entry["job"]
	return {}


func _outcomes(token: InventoryControllerToken, context: AuthenticatedCommandContext) -> Array:
	return _queue.local_observation(token, context).value["outcomes"]


func _record() -> void:
	var before: Dictionary = _snapshot()
	_trace.append({"snapshot": before, "local": _queue.local_observation(_actor, _context()).value, "own": _queue.own_inventory_observation(_actor, _context(), true).value, "grip": _queue.local_grip_observation(_actor, _context()).value, "counters": _queue.profiling_counters()})
	_check(_snapshot() == before, "scoped observations preserve canonical state")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
