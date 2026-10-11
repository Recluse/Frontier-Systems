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
var _gate := InventoryRuntimeCommandGate.new()
var _authority: InventoryControllerAuthority
var _sessions := Sessions.new()


func _initialize() -> void:
	_inventory = InventorySimulationSystem.new()
	_health = HealthSimulationSystem.new()
	_check(_inventory.configure_defaults().is_success, "actual canonical runtime configured")
	_check(_health.configure_bodies(["body.human-1", "body.human-2"]).is_success and _inventory.bind_health(_health).is_success, "actual health provider")
	_denied(null, _context(), "uninitialized")
	_check(_gate.initialize(_inventory, &"world.test", &"region.test", _sessions).is_success, "explicit one runtime gate composition")
	_authority = _gate.controller_authority()
	_denied(null, _context(), "unbound")
	_check(_authority.bind(&"body.human-2", ACTOR, &"one", 0).is_success, "trusted actor bind")
	_check(_authority.bind(&"body.human-1", TARGET, &"target", 0).is_success, "trusted target bind")
	var token: InventoryControllerToken = _authority.pin(_context()).value
	var target_token: InventoryControllerToken = _authority.pin(_context(TARGET, &"target")).value
	_fresh(token, _context(), false)
	_fresh(target_token, _context(TARGET, &"target"), false)
	_check(_gate.own_inventory_observation(token, _context(), true).value["items"].is_empty(), "actor cannot observe other body's nested possessions")
	_check(_gate.own_inventory_observation(target_token, _context(TARGET, &"target"), true).value["items"].size() == 3, "owner sees its loaded subtree")
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

	_search(token, _context(), "search.live")
	_send(token, _context(), "grip_join", {"session_id": "session.crate", "expected_revision": 0, "target_id": "fixture.salvage-crate", "action": "move_world_object", "hand_ids": ["hand.right"]}, "grip.live")
	_send(token, _context(), "start", _intent(), "job.live")
	_fresh(token, _context(), true)
	_check(_gate.local_grip_observation(token, _context()).value["sessions"].size() == 1, "own canonical grip exposed")
	_check(_gate.local_grip_observation(target_token, _context(TARGET, &"target")).value["sessions"].is_empty(), "other actor has no participant grip view")
	_check(_gate.local_observation(target_token, _context(TARGET, &"target")).value["jobs"].is_empty(), "other actor has no job/outcome view")
	var before: Dictionary = _inventory.capture_snapshot().value
	var counters: Dictionary = _inventory.profiling_counters()
	var foreign_view: ServiceResult = _gate.read_search(target_token, _context(TARGET, &"target"), "search.live")
	_check(not foreign_view.is_success and foreign_view.value == null, "valid other controller cannot read actor search")
	_check(_inventory.capture_snapshot().value == before and _inventory.profiling_counters() == counters, "foreign search does not consume or revoke owner view")
	_denied(InventoryControllerToken.new(), _context(), "denial conserves live jobs grips views")
	_sessions.allowed = false
	_denied(token, _context(), "provider revocation with live views")
	_sessions.allowed = true

	_check(_authority.replace(&"body.human-2", ACTOR, &"two", 1).is_success, "same command authority replaces actor")
	_denied(token, _context(), "replaced token")
	_denied(token, _context(ACTOR, &"two"), "stale token with fresh context")
	var replacement: InventoryControllerToken = _authority.pin(_context(ACTOR, &"two")).value
	_fresh(replacement, _context(ACTOR, &"two"), false)
	_check(not _gate.read_search(replacement, _context(ACTOR, &"two"), "search.live").is_success, "actor replacement retires completed search")
	_search(replacement, _context(ACTOR, &"two"), "search.target")
	_check(_authority.replace(&"body.human-1", TARGET, &"target-two", 1).is_success, "target replacement through same authority")
	_check(not _gate.read_search(replacement, _context(ACTOR, &"two"), "search.target").is_success and _inventory.profiling_counters()["search_views"] == 0, "target invalidation retires completed actor view")
	_fresh(replacement, _context(ACTOR, &"two"), false)
	_check(_authority.revoke(&"body.human-2", ACTOR, 2).is_success, "trusted revoke")
	_denied(replacement, _context(ACTOR, &"two"), "revoked token")
	_check(_authority.bind(&"body.human-2", ACTOR, &"one", 3).is_success, "fresh bind")
	token = _authority.pin(_context()).value
	_search(token, _context(), "search.restore")
	var saved: Dictionary = _inventory.capture_snapshot().value
	_check(_inventory.restore_snapshot_record(saved, _tick).is_success, "identical epoch canonical restore")
	_denied(token, _context(), "unreconciled restore")
	_check(_authority.reconcile_after_restore().is_success, "explicit trusted reconciliation")
	_denied(token, _context(), "restored retired token")
	_check(_authority.bind(&"body.human-2", ACTOR, &"one", 4).is_success, "same-session fresh restored bind")
	var fresh: InventoryControllerToken = _authority.pin(_context()).value
	_denied(token, _context(), "old identity after restored rebind")
	_fresh(fresh, _context(), false)
	_check(not _gate.read_search(fresh, _context(), "search.restore").is_success, "restored completion does not resurrect a view")

	# Internal fixture movement remains separate; read gate uses current reach.
	_check(_inventory.apply_local(_context(), "move.internal", "move", {"x_millimetres": 10000}, _tick + 1).is_success, "trusted internal fixture movement")
	_step(1)
	_check(_gate.world_inventory_observation(fresh, _context()).value["containers"].is_empty(), "current world reach excludes distant tray")
	_fresh(fresh, _context(), false)
	_check(not _gate.initialize(_inventory, &"world.test", &"region.test", _sessions).is_success, "no authority replacement via read composition")
	# Provider callbacks occur before admission: identical restore must deny.
	saved = _inventory.capture_snapshot().value
	_sessions.on_check = func() -> void: _check(_inventory.restore_snapshot_record(saved, _tick).is_success, "provider callback restore")
	var interrupted: ServiceResult = _gate.own_inventory_observation(fresh, _context(), true)
	_check(not interrupted.is_success and interrupted.value == null and _inventory.capture_snapshot().value == saved, "provider restore fenced before any projection")
	_check(_gate.profiling_counters()["observations"] > 0 and _gate.profiling_counters()["rejections"] > 0, "bounded read profiling")
	_inventory.free()
	_denied(fresh, _context(), "freed runtime")
	_health.free()
	print("Inventory controller observations: %d failures" % _failures)
	quit(0 if _failures == 0 else 1)


func _reads(token: InventoryControllerToken, context: AuthenticatedCommandContext, view: String = "search.live") -> Array[ServiceResult]:
	return [_gate.own_inventory_observation(token, context), _gate.own_inventory_observation(token, context, true),
		_gate.world_inventory_observation(token, context), _gate.local_grip_observation(token, context),
		_gate.local_observation(token, context), _gate.read_search(token, context, view)]


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
	_step(120)
	_check(_gate.read_search(token, context, id).is_success, "actual completed scoped search " + id)


func _intent() -> Dictionary:
	return {"action": "search", "target_body_id": "body.human-1", "target_container_id": "storage.pouch-1", "item_id": "", "slot_id": "", "destination_container_id": "", "expected_revision": _inventory.capture_snapshot().value["owner"]["state_revision"]}


func _send(token: InventoryControllerToken, context: AuthenticatedCommandContext, operation: String, payload: Dictionary, id: String) -> void:
	var result: ServiceResult = _gate.apply(token, context, id, operation, payload, _tick + 1)
	_check(result.is_success, id + ": " + result.message)
	_step(1)


func _step(count: int) -> void:
	for index in range(count):
		_tick += 1
		_inventory.simulate_tick(_tick, 1.0 / 60.0)


func _context(principal: StringName = ACTOR, session: StringName = &"one") -> AuthenticatedCommandContext:
	return AuthenticatedCommandContext.from_authenticated_session(principal, session, &"world.test", &"region.test", PackedStringArray(["inventory.operate"]))


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
