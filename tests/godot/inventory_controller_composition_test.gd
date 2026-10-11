extends SceneTree

class Sessions extends InventoryControllerSessionProvider:
	var allowed: bool = true
	var on_check: Callable
	func permits_inventory(principal: StringName, session: StringName, world: StringName, region: StringName) -> bool:
		if on_check.is_valid():
			var callback: Callable = on_check
			on_check = Callable()
			callback.call()
		return allowed and principal in [ACTOR, TARGET] and session in [&"one", &"two", &"target", &"target-two"] and world == &"world.test" and region == &"region.test"

const ACTOR: StringName = &"local-inventory-actor"
const TARGET: StringName = &"local-inventory-target"
var _failures: int = 0
var _tick: int = 0
var _inventory: InventorySimulationSystem
var _health: HealthSimulationSystem
var _queue := InventoryRuntimeCommandQueue.new()
var _authority: InventoryControllerAuthority
var _sessions := Sessions.new()


func _initialize() -> void:
	_inventory = InventorySimulationSystem.new()
	_health = HealthSimulationSystem.new()
	_check(_inventory.configure_defaults().is_success, "actual canonical runtime configured")
	_check(_health.configure_bodies(["body.human-1", "body.human-2"]).is_success and _inventory.bind_health(_health).is_success, "actual health provider")
	_denied(null, _context(), "uninitialized")
	_check(_queue.initialize(_inventory, &"world.test", &"region.test", _sessions).is_success, "explicit one runtime gate composition")
	_authority = _queue.controller_authority()
	_denied(null, _context(), "unbound")
	_check(_authority.bind(&"body.human-2", ACTOR, &"one", 0).is_success, "trusted actor bind")
	_check(_authority.bind(&"body.human-1", TARGET, &"target", 0).is_success, "trusted target bind")
	var token: InventoryControllerToken = _authority.pin(_context()).value
	var target_token: InventoryControllerToken = _authority.pin(_context(TARGET, &"target")).value
	_fresh(token, _context(), false)
	_fresh(target_token, _context(TARGET, &"target"), false)
	_send(target_token, _context(TARGET, &"target"), "self", {"operation": "switch_hand", "item_id": "", "source_container_id": "", "destination_container_id": "", "slot_id": "", "expected_revision": int(_inventory.capture_snapshot().value["owner"]["state_revision"])}, "target.self")
	_fresh(target_token, _context(TARGET, &"target"), false)
	_check(_queue.own_inventory_observation(token, _context(), true).value["items"].is_empty(), "actor cannot observe other body's nested possessions")
	_check(_queue.own_inventory_observation(target_token, _context(TARGET, &"target"), true).value["items"].size() == 3, "owner sees its loaded subtree")
	_denied(null, _context(), "missing token")
	_denied(InventoryControllerToken.new(), _context(), "foreign token")
	_denied(target_token, _context(), "other body's token")
	_denied(token, _context(TARGET, &"target"), "other authenticated principal")
	_denied(token, null, "missing context")
	_denied(token, AuthenticatedCommandContext.for_local_development(ACTOR, &"world.test", &"region.test"), "development context cannot bypass")
	for field in ["world_id", "region_id", "principal_id", "session_id"]:
		var context: AuthenticatedCommandContext = _context()
		context.set(field, &"foreign")
		_denied(token, context, "wrong " + field)
	var ungranted: AuthenticatedCommandContext = _context()
	ungranted.permissions.clear()
	_denied(token, ungranted, "missing permission")
	_sessions.allowed = false
	_denied(token, _context(), "provider revoked")
	_sessions.allowed = true

	_sessions.on_check = func() -> void: _busy_attempts(token)
	_check(_queue.own_inventory_observation(token, _context()).is_success, "outer observation survives denied reentry")
	_sessions.on_check = func() -> void: _busy_attempts(token)
	_search(token, _context(), "search.live")
	_send(token, _context(), "grip_join", {"session_id": "session.crate", "expected_revision": 0, "target_id": "fixture.salvage-crate", "action": "move_world_object", "hand_ids": ["hand.right"]}, "grip.live")
	_send(token, _context(), "start", _intent(), "job.live")
	_fresh(token, _context(), true)
	_check(_queue.local_grip_observation(token, _context()).value["sessions"].size() == 1, "own canonical grip exposed")
	_check(_queue.local_grip_observation(target_token, _context(TARGET, &"target")).value["sessions"].is_empty(), "other actor has no participant grip view")
	_check(_queue.local_observation(target_token, _context(TARGET, &"target")).value["jobs"].is_empty(), "other actor has no job/outcome view")
	var before: Dictionary = _inventory.capture_snapshot().value
	var counters: Dictionary = _inventory.profiling_counters()
	var foreign_view: ServiceResult = _queue.read_search(target_token, _context(TARGET, &"target"), "search.live")
	_check(not foreign_view.is_success and foreign_view.value == null, "valid other controller cannot read actor search")
	_check(_inventory.capture_snapshot().value == before and _inventory.profiling_counters() == counters, "foreign search does not consume or revoke owner view")
	_denied(InventoryControllerToken.new(), _context(), "denial conserves live jobs grips views")
	_sessions.allowed = false
	_denied(token, _context(), "provider revocation with live views")
	_sessions.allowed = true

	_check(_authority.replace(&"body.human-2", ACTOR, &"two", 1).is_success, "same command authority replaces actor")
	_denied(token, _context(), "replaced token")
	_stale_command(token, _context(), "replace.queued")
	_denied(token, _context(ACTOR, &"two"), "stale token with fresh context")
	var replacement: InventoryControllerToken = _authority.pin(_context(ACTOR, &"two")).value
	_fresh(replacement, _context(ACTOR, &"two"), false)
	_check(not _queue.read_search(replacement, _context(ACTOR, &"two"), "search.live").is_success, "actor replacement retires completed search")
	_search(replacement, _context(ACTOR, &"two"), "search.target")
	_check(_authority.replace(&"body.human-1", TARGET, &"target-two", 1).is_success, "target replacement through same authority")
	_check(not _queue.read_search(replacement, _context(ACTOR, &"two"), "search.target").is_success and _inventory.profiling_counters()["search_views"] == 0, "target invalidation retires completed actor view")
	_fresh(replacement, _context(ACTOR, &"two"), false)
	_check(_authority.revoke(&"body.human-2", ACTOR, 2).is_success, "trusted revoke")
	_denied(replacement, _context(ACTOR, &"two"), "revoked token")
	_stale_command(replacement, _context(ACTOR, &"two"), "revoke.queued")
	_check(_authority.bind(&"body.human-2", ACTOR, &"one", 3).is_success, "fresh bind")
	token = _authority.pin(_context()).value
	_search(token, _context(), "search.restore")
	var saved: Dictionary = _inventory.capture_snapshot().value
	_check(_inventory.restore_snapshot_record(saved, _tick).is_success, "identical epoch canonical restore")
	_denied(token, _context(), "unreconciled restore")
	_stale_command(token, _context(), "restore.queued")
	_check(_authority.reconcile_after_restore().is_success, "explicit trusted reconciliation")
	_denied(token, _context(), "restored retired token")
	_check(_authority.bind(&"body.human-2", ACTOR, &"one", 4).is_success, "same-session fresh restored bind")
	var fresh: InventoryControllerToken = _authority.pin(_context()).value
	_denied(token, _context(), "old identity after restored rebind")
	_fresh(fresh, _context(), false)
	_check(not _queue.read_search(fresh, _context(), "search.restore").is_success, "restored completion does not resurrect a view")

	# Internal fixture movement remains separate; read gate uses current reach.
	_check(_inventory.apply_local(_context(), "move.internal", "move", {"x_millimetres": 10000}, _tick + 1).is_success, "trusted internal fixture movement")
	_step(1)
	_check(_queue.world_inventory_observation(fresh, _context()).value["containers"].is_empty(), "current world reach excludes distant tray")
	_fresh(fresh, _context(), false)
	_check(not _queue.initialize(_inventory, &"world.test", &"region.test", _sessions).is_success, "no authority replacement via read composition")
	# Provider callbacks occur before admission: identical restore must deny.
	saved = _inventory.capture_snapshot().value
	_sessions.on_check = func() -> void: _check(_inventory.restore_snapshot_record(saved, _tick).is_success, "provider callback restore")
	_check(_queue.enqueue(fresh, _context(), "restore.pending", "self", {}).is_success, "pending intent before read callback restore")
	var interrupted: ServiceResult = _queue.own_inventory_observation(fresh, _context(), true)
	_check(not interrupted.is_success and interrupted.value == null and _inventory.capture_snapshot().value == saved, "provider restore fenced before any projection")
	_check(_queue.profiling_counters()["pending"] == 0, "read callback restore discards volatile intent")
	_check(_queue.profiling_counters()["rejections"] > 0, "bounded read profiling")
	_inventory.simulate_tick(_tick + 1, 1.0 / 60.0)
	var externally_advanced: Dictionary = _inventory.capture_snapshot().value
	_denied(fresh, _context(), "external advance")
	_check(not _queue.advance_tick(_tick + 1, 1.0 / 60.0).is_success and _inventory.capture_snapshot().value == externally_advanced, "external advancement never doubled")
	_inventory.free()
	_denied(fresh, _context(), "freed runtime")
	_health.free()
	_callback_boundaries()
	print("Inventory controller composition: %d failures" % _failures)
	quit(0 if _failures == 0 else 1)


func _callback_boundaries() -> void:
	for projection in ["own", "details", "world", "grip", "local", "search"]:
		for effect in ["advance", "free"]:
			var inventory := InventorySimulationSystem.new()
			var queue := InventoryRuntimeCommandQueue.new()
			var sessions := Sessions.new()
			_check(inventory.configure_defaults().is_success, "callback fixture runtime")
			_check(queue.initialize(inventory, &"world.test", &"region.test", sessions).is_success, "callback fixture queue")
			var authority: InventoryControllerAuthority = queue.controller_authority()
			_check(authority.bind(&"body.human-2", ACTOR, &"one", 0).is_success, "callback fixture bind")
			var token: InventoryControllerToken = authority.pin(_context()).value
			var generation: int = inventory.controller_restore_generation()
			var before: Dictionary = inventory.capture_snapshot().value
			sessions.on_check = func() -> void:
				if effect == "free":
					inventory.free()
				else:
					inventory.simulate_tick(1, 1.0 / 60.0)
			var result: ServiceResult
			match projection:
				"own": result = queue.own_inventory_observation(token, _context())
				"details": result = queue.own_inventory_observation(token, _context(), true)
				"world": result = queue.world_inventory_observation(token, _context())
				"grip": result = queue.local_grip_observation(token, _context())
				"local": result = queue.local_observation(token, _context())
				"search": result = queue.read_search(token, _context(), "callback.search")
			var expected: StringName = &"queue_unavailable" if effect == "free" else &"queue_tick_mismatch"
			_check(not result.is_success and result.value == null and result.error_code == expected, projection + " callback " + effect + " returns no projection")
			_check(not queue.get("_busy"), projection + " callback " + effect + " releases busy guard")
			if effect == "advance":
				_check(inventory.controller_restore_generation() == generation, "callback tick changes without restore")
				var after: Dictionary = inventory.capture_snapshot().value
				_check(after["last_tick"] == 1, "callback actual runtime advanced once")
				after["last_tick"] = before["last_tick"]
				_check(after == before, "read adds no canonical mutation after callback tick")
				_check(not queue.advance_tick(1, 1.0 / 60.0).is_success, "callback advance cannot be doubled")
				inventory.free()


func _stale_command(token: InventoryControllerToken, context: AuthenticatedCommandContext, id: String) -> void:
	var before: Dictionary = _inventory.capture_snapshot().value
	_check(_queue.enqueue(token, context, id, "start", _intent()).is_success, "volatile stale admission " + id)
	_tick += 1
	var result: ServiceResult = _queue.advance_tick(_tick, 1.0 / 60.0)
	_check(result.is_success and result.value.size() == 1 and not result.value[0]["result"].is_success, "same authority denies queued stale command " + id)
	var after: Dictionary = _inventory.capture_snapshot().value
	after["last_tick"] = before["last_tick"]
	_check(after == before, "stale command conserves canonical state " + id)


func _busy_attempts(token: InventoryControllerToken) -> void:
	var before: Dictionary = _inventory.capture_snapshot().value
	for result in _reads(token, _context()):
		_check(not result.is_success and result.value == null and result.error_code == &"queue_unavailable", "busy scoped read fails closed")
	_check(not _queue.enqueue(token, _context(), "busy", "self", {}).is_success, "read callback cannot enqueue")
	_check(not _queue.advance_tick(_tick + 1, 1.0 / 60.0).is_success, "read callback cannot advance")
	_check(not _queue.discard_session(ACTOR, &"one").is_success, "read callback cannot discard")
	_check(_inventory.capture_snapshot().value == before, "busy callback conserves canonical state")


func _reads(token: InventoryControllerToken, context: AuthenticatedCommandContext, view: String = "search.live") -> Array[ServiceResult]:
	return [_queue.own_inventory_observation(token, context), _queue.own_inventory_observation(token, context, true),
		_queue.world_inventory_observation(token, context), _queue.local_grip_observation(token, context),
		_queue.local_observation(token, context), _queue.read_search(token, context, view)]


func _fresh(token: InventoryControllerToken, context: AuthenticatedCommandContext, search: bool) -> void:
	var before: Dictionary = _inventory.capture_snapshot().value
	var counters: Dictionary = _inventory.profiling_counters()
	var expected: Array[ServiceResult] = [_inventory.own_inventory_observation(context), _inventory.own_inventory_observation(context, true),
		_inventory.world_inventory_observation(context), _inventory.local_grip_observation(context), _inventory.local_observation(context)]
	var actual: Array[ServiceResult] = _reads(token, context)
	if search:
		expected.append(_inventory.read_search(context, "search.live"))
	for index in range(expected.size()):
		_check(actual[index].is_success and actual[index].value == expected[index].value, "exact existing scoped projection %d" % index)
		if actual[index].is_success:
			_poison(actual[index].value)
	var repeated: Array[ServiceResult] = _reads(token, context)
	for index in range(expected.size()):
		_check(repeated[index].is_success and repeated[index].value == expected[index].value, "deeply detached projection %d" % index)
	_check(_inventory.capture_snapshot().value == before and _inventory.profiling_counters() == counters, "authorized reads conserve snapshot receipts jobs grips and views")


func _poison(value: Variant) -> void:
	if value is Dictionary:
		for child in value.values(): _poison(child)
		value.clear()
	elif value is Array:
		for child in value: _poison(child)
		value.clear()


func _denied(token: InventoryControllerToken, context: AuthenticatedCommandContext, label: String) -> void:
	var before: Dictionary = _inventory.capture_snapshot().value if is_instance_valid(_inventory) else {}
	var counters: Dictionary = _inventory.profiling_counters() if is_instance_valid(_inventory) else {}
	var status: ServiceResult = _inventory.local_observation(_context()) if is_instance_valid(_inventory) else ServiceResult.success()
	for result in _reads(token, context):
		_check(not result.is_success and result.value == null, label + " returns no projection")
	if is_instance_valid(_inventory):
		_check(_inventory.capture_snapshot().value == before and _inventory.profiling_counters() == counters, label + " conserves snapshot and volatile views")
		_check(_inventory.local_observation(_context()).value == status.value, label + " conserves outcome metadata")


func _search(token: InventoryControllerToken, context: AuthenticatedCommandContext, id: String) -> void:
	_send(token, context, "start", _intent(), id)
	_check(_inventory.capture_snapshot().value["jobs"][0]["job"]["progress_ticks"] == 0, "queued job begins with zero progress")
	_step(119)
	_check(not _queue.read_search(token, context, id).is_success, "search not visible before 120 ticks")
	_check(_inventory.capture_snapshot().value["jobs"][0]["job"]["progress_ticks"] == 119, "exact deterministic progress")
	_step(1)
	_check(_queue.read_search(token, context, id).is_success, "actual completed scoped search " + id)


func _intent() -> Dictionary:
	return {"action": "search", "target_body_id": "body.human-1", "target_container_id": "storage.pouch-1", "item_id": "", "slot_id": "", "destination_container_id": "", "expected_revision": int(_inventory.capture_snapshot().value["owner"]["state_revision"])}


func _send(token: InventoryControllerToken, context: AuthenticatedCommandContext, operation: String, payload: Dictionary, id: String) -> void:
	var before: Dictionary = _inventory.capture_snapshot().value
	_check(_queue.enqueue(token, context, id, operation, payload).is_success, "queued " + id)
	_check(_inventory.capture_snapshot().value == before, "admission conserves canonical state")
	_tick += 1
	var result: ServiceResult = _queue.advance_tick(_tick, 1.0 / 60.0)
	_check(result.is_success and result.value.size() == 1 and result.value[0]["result"].is_success, "canonical boundary " + id)
	_check(_inventory.capture_snapshot().value["last_tick"] == _tick, "single inventory advancement")
	before = _inventory.capture_snapshot().value
	_check(not _queue.advance_tick(_tick, 1.0 / 60.0).is_success and _inventory.capture_snapshot().value == before, "duplicate boundary never double advances")


func _step(count: int) -> void:
	for index in range(count):
		_tick += 1
		_check(_queue.advance_tick(_tick, 1.0 / 60.0).is_success, "sole fixed tick")


func _context(principal: StringName = ACTOR, session: StringName = &"one") -> AuthenticatedCommandContext:
	return AuthenticatedCommandContext.from_authenticated_session(principal, session, &"world.test", &"region.test", PackedStringArray(["inventory.operate"]))


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
