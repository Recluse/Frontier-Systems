extends SceneTree

class Sessions extends InventoryControllerSessionProvider:
	var allowed: bool = true
	var on_check: Callable
	func permits_inventory(principal: StringName, session: StringName, world: StringName, region: StringName) -> bool:
		if on_check.is_valid():
			var callback: Callable = on_check
			on_check = Callable()
			callback.call()
		return allowed and principal == &"local-inventory-actor" and session in [&"one", &"two"] and world == &"world.test" and region == &"region.test"

var _failures: int = 0
var _inventory := InventorySimulationSystem.new()
var _health := HealthSimulationSystem.new()
var _queue := InventoryRuntimeCommandQueue.new()
var _sessions := Sessions.new()
var _authority: InventoryControllerAuthority
var _token: InventoryControllerToken
var _tick: int = 0


func _initialize() -> void:
	_check(_inventory.configure_defaults().is_success, "actual inventory")
	_check(_health.configure_bodies(["body.human-1", "body.human-2"]).is_success and _inventory.bind_health(_health).is_success, "actual health")
	_check(_queue.initialize(_inventory, &"world.test", &"region.test", _sessions, 3, 2).is_success, "explicit bounded composition")
	_check(not _queue.initialize(_inventory, &"world.test", &"region.test", _sessions).is_success, "one-shot")
	_authority = _queue.controller_authority()
	_bind(0)
	# FIFO, partial drain and detached mutable input. No mutation on enqueue.
	var before: Dictionary = _snapshot()
	var context: AuthenticatedCommandContext = _context()
	var intent: Dictionary = _self(0)
	_check(_queue.enqueue(_token, context, "first", "self", intent).is_success, "first enqueue")
	context.permissions.clear()
	context.session_id = &"two"
	intent["expected_revision"] = 999
	_add("second", _self(1))
	_add("third", _self(2))
	_check(_snapshot() == before, "enqueue never mutates canonical state")
	_check(_queue.enqueue(_token, _context(), "full", "self", _self(0)).error_code == &"queue_full", "full refuses newest")
	_check(not _queue.advance_tick(2, 1.0 / 60.0).is_success and _snapshot() == before and _pending() == 3, "skipped tick retains queue and state")
	var results: Array = _advance().value
	_check(results.size() == 2 and results[0]["request_id"] == "first" and results[1]["request_id"] == "second" and results[0]["result"].is_success and results[1]["result"].is_success, "FIFO detached context and intent")
	before = _snapshot()
	_check(not _queue.advance_tick(_tick, 1.0 / 60.0).is_success and _snapshot() == before and _pending() == 1, "duplicate boundary cannot replay")
	_check(_advance().value[0]["result"].is_success and _pending() == 0, "per-tick remainder applies next tick")
	_check(_snapshot()["owner"]["receipts"].size() == 3, "canonical receipts only")
	# Existing canonical retry remains a receipt retry, with no queue deduplication.
	before = _snapshot()
	_add("third", _self(2))
	_check(_advance().value[0]["result"].is_success, "canonical retry succeeds")
	_check(_snapshot()["owner"] == before["owner"], "retry preserves canonical owner and receipts")
	_add("bad.revision", _self(999))
	_add("third", _self(2))
	_add("third", _self(2))
	results = _advance().value
	_check(results.size() == 2 and not results[0]["result"].is_success and results[1]["result"].is_success and _pending() == 1, "failed attempt consumes budget and FIFO continues")
	_check(_advance().value[0]["result"].is_success and _snapshot()["owner"] == before["owner"], "budget remainder preserves canonical retry semantics")
	# Lifecycle transitions run before queued application. Snapshot after transition
	# is conserved by failed dispatch (except the designated tick counter).
	_add("replace.stale", _self(3))
	_check(_authority.replace(&"body.human-2", &"local-inventory-actor", &"two", 1).is_success, "replace actual controller")
	_denied_boundary("replace")
	_token = _authority.pin(_context(&"two")).value
	_check(_queue.enqueue(_token, _context(&"two"), "revoke.stale", "self", _self(3)).is_success, "queued replacement")
	_check(_authority.revoke(&"body.human-2", &"local-inventory-actor", 2).is_success, "revoke actual controller")
	_denied_boundary("revoke")
	_bind(3)
	_add("provider.stale", _self(3))
	_sessions.allowed = false
	_denied_boundary("provider disconnect")
	_sessions.allowed = true
	# Unknown operations and reference-bearing/unbounded intent never enter queue.
	for payload in [{"object": _inventory}, {"huge": "x".repeat(257)}, {"nested": [[[[[1]]]]]}]:
		_check(not _queue.enqueue(_token, _context(), "bad", "self", payload).is_success, "bounded plain detached intent")
	_check(not _queue.enqueue(_token, _context(), "unknown", "move", {}).is_success and _pending() == 0, "no unknown replay")
	# Start is applied at boundary; new job does not progress until following tick.
	var revision: int = _snapshot()["owner"]["state_revision"]
	_check(_queue.enqueue(_token, _context(), "job.queued", "start", {"action": "search", "target_body_id": "body.human-1", "target_container_id": "storage.pouch-1", "item_id": "", "slot_id": "", "destination_container_id": "", "expected_revision": revision}).is_success, "queue real job")
	_check(_advance().value[0]["result"].is_success, "job starts through gate")
	_check(_snapshot()["jobs"][0]["job"]["progress_ticks"] == 0, "commands precede job advance")
	_advance()
	_check(_snapshot()["jobs"][0]["job"]["progress_ticks"] == 1, "job advances next fixed tick")
	# Restore clears all old volatile intent and resynchronizes tick; no replay.
	_add("restore.old", _self(3))
	before = _snapshot()
	_check(_inventory.restore_snapshot_record(before, _tick).is_success, "actual identical epoch restore")
	before = _snapshot()
	_check(_queue.advance_tick(_tick + 1, 1.0 / 60.0).error_code == &"queue_restored" and _snapshot() == before and _pending() == 0, "restore clears without advancement")
	_add("restore.stale", _self(3))
	_denied_boundary("unreconciled restore")
	_check(_authority.reconcile_after_restore().is_success, "trusted reconciliation")
	_bind(4)
	_add("restore.fresh", _self(3))
	_check(_advance().value[0]["result"].is_success, "fresh post-restore success")
	# Trusted disconnect cleanup is scoped and leaves canonical work to revoke.
	_add("disconnect.old", _self(4))
	before = _snapshot()
	_check(_queue.discard_session(&"other", &"one").value["discarded"] == 0 and _pending() == 1, "disconnect scope")
	_check(_queue.discard_session(&"local-inventory-actor", &"one").value["discarded"] == 1 and _pending() == 0 and _snapshot() == before, "disconnect discards volatile intent only")
	# Restore inside provider validation interrupts the entire drain and job tick.
	_add("callback.restore", _self(4))
	_add("callback.remainder", _self(5))
	before = _snapshot()
	_sessions.on_check = func() -> void:
		_check(not _queue.enqueue(_token, _context(), "reentrant", "self", _self(4)).is_success, "reentrant enqueue refused")
		_check(not _queue.advance_tick(_tick + 1, 1.0 / 60.0).is_success, "reentrant drain refused")
		_check(_inventory.restore_snapshot_record(before, _tick).is_success, "provider restore")
	_check(_queue.advance_tick(_tick + 1, 1.0 / 60.0).error_code == &"queue_restored" and _snapshot() == before and _pending() == 0, "restore callback cannot replay remainder or advance jobs")
	_check(_authority.reconcile_after_restore().is_success, "callback restore reconcile")
	_bind(5)
	_queue.set("_sequence", InventoryControllerAuthority.MAX_EXACT_INTEGER - 1)
	_add("last.sequence", _self(4))
	_check(_queue.enqueue(_token, _context(), "exhausted", "self", _self(5)).error_code == &"queue_sequence_exhausted", "sequence never wraps")
	_check(_advance().value[0]["result"].is_success, "last sequence drains")
	_check(_queue.profiling_counters()["peak"] == 3 and _queue.profiling_counters()["discarded"] >= 3, "bounded profiling")
	before = _snapshot()
	_inventory.simulate_tick(_tick + 1, 1.0 / 60.0)
	_check(_queue.advance_tick(_tick + 1, 1.0 / 60.0).error_code == &"queue_tick_mismatch", "external advancement fails closed")
	_inventory.free()
	_check(not _queue.advance_tick(_tick + 1, 1.0 / 60.0).is_success, "freed owner")
	_health.free()
	print("Inventory runtime command queue: %d failures" % _failures)
	quit(0 if _failures == 0 else 1)


func _denied_boundary(label: String) -> void:
	var before: Dictionary = _snapshot()
	var result: ServiceResult = _advance()
	_check(result.is_success and result.value.size() == 1 and not result.value[0]["result"].is_success, label + " denied at dispatch")
	var after: Dictionary = _snapshot()
	after["last_tick"] = before["last_tick"]
	_check(after == before, label + " preserves complete canonical inventory")


func _bind(epoch: int) -> void:
	_check(_authority.bind(&"body.human-2", &"local-inventory-actor", &"one", epoch).is_success, "fresh bind")
	_token = _authority.pin(_context()).value


func _add(id: String, payload: Dictionary) -> void:
	_check(_queue.enqueue(_token, _context(), id, "self", payload).is_success, "enqueue " + id)


func _advance() -> ServiceResult:
	_tick += 1
	return _queue.advance_tick(_tick, 1.0 / 60.0)


func _snapshot() -> Dictionary:
	return _inventory.capture_snapshot().value


func _pending() -> int:
	return _queue.profiling_counters()["pending"]


func _context(session: StringName = &"one") -> AuthenticatedCommandContext:
	return AuthenticatedCommandContext.from_authenticated_session(&"local-inventory-actor", session, &"world.test", &"region.test", PackedStringArray(["inventory.operate"]))


func _self(revision: int) -> Dictionary:
	return {"operation": "switch_hand", "item_id": "", "source_container_id": "", "destination_container_id": "", "slot_id": "", "expected_revision": revision}


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
