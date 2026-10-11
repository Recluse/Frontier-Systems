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

const ACTOR: StringName = &"local-inventory-actor"
var _failures: int = 0
var _tick: int = 0
var _inventory: InventorySimulationSystem
var _health: HealthSimulationSystem
var _gate := InventoryRuntimeCommandGate.new()
var _authority: InventoryControllerAuthority
var _sessions := Sessions.new()


func _initialize() -> void:
	_inventory = InventorySimulationSystem.new()
	_health = HealthSimulationSystem.new()
	_check(_inventory.configure_defaults().is_success, "actual inventory configured")
	_check(_health.configure_bodies(["body.human-1", "body.human-2"]).is_success and _inventory.bind_health(_health).is_success, "actual health owner")
	_denied(null, _context(), "uninitialized gate")
	_check(_gate.initialize(_inventory, &"world.test", &"region.test", _sessions).is_success, "explicit gate composition")
	_authority = _gate.controller_authority()
	_denied(null, _context(), "no binding")
	_check(_authority.bind(&"body.human-2", ACTOR, &"one", 0).is_success, "bind through actual runtime owner")
	var token: InventoryControllerToken = _authority.pin(_context()).value
	_denied(null, _context(), "missing token")
	_denied(InventoryControllerToken.new(), _context(), "foreign token")
	_denied(token, AuthenticatedCommandContext.for_local_development(ACTOR, &"world.test", &"region.test"), "no fixture fallback")
	for field in ["world_id", "region_id", "principal_id", "session_id"]:
		var context: AuthenticatedCommandContext = _context()
		context.set(field, &"foreign")
		_denied(token, context, "foreign " + field)
	var ungranted: AuthenticatedCommandContext = _context()
	ungranted.permissions.clear()
	_denied(token, ungranted, "missing permission")
	_denied(token, null, "missing context")
	_sessions.allowed = false
	_denied(token, _context(), "provider revocation")
	_sessions.allowed = true
	# Live canonical effects through this gate: receipts, scoped view, grip, job.
	_send(token, _context(), "self", _self(0), "hand.first")
	var saved: Dictionary = _inventory.capture_snapshot().value
	_check(saved["owner"]["receipts"].size() == 1, "valid self command creates canonical receipt")
	var retried: ServiceResult = _gate.apply(token, _context(), "hand.first", "self", _self(0), _tick + 1)
	_check(retried.is_success and _inventory.capture_snapshot().value == saved, "existing idempotent receipt retry preserved")
	_send(token, _context(), "start", _search(), "search.live")
	_step(120)
	_check(_inventory.read_search(_context(), "search.live").is_success, "valid command creates live search view")
	_send(token, _context(), "grip_join", _join(), "grip.live")
	_send(token, _context(), "start", _search(), "job.live")
	_check(_inventory.profiling_counters()["jobs"] == 1 and _inventory.profiling_counters()["search_views"] == 1, "live job and view before denial")
	_denied(InventoryControllerToken.new(), _context(), "foreign token with live state")
	_check(_authority.replace(&"body.human-2", ACTOR, &"two", 1).is_success, "replace invalidates actual canonical work")
	_denied(token, _context(), "replaced queued token")
	var replacement: InventoryControllerToken = _authority.pin(_context(&"two")).value
	_denied(token, _context(&"two"), "old token with new context")
	_send(replacement, _context(&"two"), "self", _self(1), "hand.replaced")
	_check(_authority.revoke(&"body.human-2", ACTOR, 2).is_success, "trusted revoke")
	_denied(replacement, _context(&"two"), "revoked token")
	_check(_authority.bind(&"body.human-2", ACTOR, &"one", 3).is_success, "fresh bind after revoke")
	token = _authority.pin(_context()).value
	_send(token, _context(), "start", _search(), "job.restore")
	saved = _inventory.capture_snapshot().value
	_check(_inventory.restore_snapshot_record(saved, _tick).is_success, "identical epoch actual restore")
	_denied(token, _context(), "unreconciled restored token")
	_check(_authority.reconcile_after_restore().is_success, "explicit reconciliation")
	_denied(token, _context(), "reconciled stale token")
	_check(_authority.bind(&"body.human-2", ACTOR, &"one", 4).is_success, "same session fresh post-restore token")
	var fresh: InventoryControllerToken = _authority.pin(_context()).value
	_denied(token, _context(), "old token after same session rebind")
	_send(fresh, _context(), "self", _self(2), "hand.restored")
	# Neither trusted context nor valid token permits client actor/scope overrides.
	for field in ["body_id", "principal_id", "world_id", "region_id"]:
		var forged: Dictionary = _self(3)
		forged[field] = "body.human-1"
		var before: Dictionary = _inventory.capture_snapshot().value
		_check(not _gate.apply(fresh, _context(), "forged." + field, "self", forged, _tick + 1).is_success and _inventory.capture_snapshot().value == before, "reject client " + field)
	var before: Dictionary = _inventory.capture_snapshot().value
	_check(not _gate.apply(fresh, _context(), "movement", "move", {"x_millimetres": 10}, _tick + 1).is_success and _inventory.capture_snapshot().value == before, "gate excludes fixture locomotion")
	_check(not _gate.apply(fresh, _context(), "wrong.tick", "self", _self(3), _tick).is_success and _inventory.capture_snapshot().value == before, "canonical fixed boundary preserved")
	_check(not _gate.initialize(_inventory, &"world.test", &"region.test", _sessions).is_success, "cannot replace composed authority")
	# Restore during trusted provider validation must still fence this dispatch.
	saved = _inventory.capture_snapshot().value
	_sessions.on_check = func() -> void: _check(_inventory.restore_snapshot_record(saved, _tick).is_success, "provider callback restore")
	_check(not _gate.apply(fresh, _context(), "callback.restore", "self", _self(3), _tick + 1).is_success and _inventory.capture_snapshot().value == saved, "provider restore cannot slip between actor resolution and dispatch")
	_check(_gate.profiling_counters()["rejections"] > 0 and _gate.profiling_counters()["applications"] > 0, "bounded gate profiling")
	_inventory.free()
	_denied(fresh, _context(), "freed runtime")
	_health.free()
	print("Inventory runtime command gate: %d failures" % _failures)
	quit(0 if _failures == 0 else 1)


func _denied(token: InventoryControllerToken, context: AuthenticatedCommandContext, label: String) -> void:
	var before: Dictionary = _inventory.capture_snapshot().value if is_instance_valid(_inventory) else {}
	var counters: Dictionary = _inventory.profiling_counters() if is_instance_valid(_inventory) else {}
	var observation: ServiceResult = _inventory.local_observation(_context()) if is_instance_valid(_inventory) else ServiceResult.success()
	var view: ServiceResult = _inventory.read_search(_context(), "search.live") if is_instance_valid(_inventory) else ServiceResult.success()
	var commands: Dictionary = {"self": _self(0), "world": {"operation": "drop", "item_id": "crowbar-1", "world_container_id": "world.tray-1", "destination_container_id": "world.tray-1", "slot_id": "", "expected_revision": 0},
		"start": _search(), "cancel": {"job_id": "job.live"}, "resume": {"job_id": "job.restore"}, "resist": {}, "close_search": {"view_id": "search.live"},
		"grip_join": _join(), "grip_release": {"session_id": "session.crate", "expected_revision": 0}, "grip_resume": {"session_id": "session.crate", "expected_revision": 0}}
	for operation in commands:
		_check(not _gate.apply(token, context, "denied." + operation, operation, commands[operation], _tick + 1).is_success, label + " / " + operation)
	if is_instance_valid(_inventory):
		_check(_inventory.capture_snapshot().value == before and _inventory.profiling_counters() == counters, label + " conserves complete snapshot jobs grips views items receipts and outcomes")
		var after: ServiceResult = _inventory.local_observation(_context())
		var after_view: ServiceResult = _inventory.read_search(_context(), "search.live")
		_check(after.is_success == observation.is_success and after.value == observation.value and after_view.is_success == view.is_success and after_view.value == view.value, label + " conserves volatile outcome and search contents")


func _send(token: InventoryControllerToken, context: AuthenticatedCommandContext, operation: String, payload: Dictionary, id: String) -> void:
	var result: ServiceResult = _gate.apply(token, context, id, operation, payload, _tick + 1)
	_check(result.is_success, id + ": " + result.message)
	_step(1)


func _step(count: int) -> void:
	for index in range(count):
		_tick += 1
		_inventory.simulate_tick(_tick, 1.0 / 60.0)


func _context(session: StringName = &"one") -> AuthenticatedCommandContext:
	return AuthenticatedCommandContext.from_authenticated_session(ACTOR, session, &"world.test", &"region.test", PackedStringArray(["inventory.operate"]))


func _self(revision: int) -> Dictionary:
	return {"operation": "switch_hand", "item_id": "", "source_container_id": "", "destination_container_id": "", "slot_id": "", "expected_revision": revision}


func _search() -> Dictionary:
	var revision: int = _inventory.capture_snapshot().value["owner"]["state_revision"] if is_instance_valid(_inventory) else 0
	return {"action": "search", "target_body_id": "body.human-1", "target_container_id": "storage.pouch-1", "item_id": "", "slot_id": "", "destination_container_id": "", "expected_revision": revision}


func _join() -> Dictionary:
	return {"session_id": "session.crate", "expected_revision": 0, "target_id": "fixture.salvage-crate", "action": "move_world_object", "hand_ids": ["hand.right"]}


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
