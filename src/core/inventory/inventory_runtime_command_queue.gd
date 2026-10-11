extends RefCounted
class_name InventoryRuntimeCommandQueue

## Trusted same-process owner calls advance_tick after lifecycle changes.
## This object owns inventory advancement; never also register that inventory
## with a runner. No network admission, callbacks, persistence or receipt layer.
const MAX_PENDING: int = 64
const MAX_INTENT_NODES: int = 128
const MAX_TEXT: int = 256
const OPERATIONS := ["self", "world", "start", "cancel", "resume", "resist", "close_search", "grip_join", "grip_release", "grip_resume"]
var _inventory: InventorySimulationSystem
var _gate := InventoryRuntimeCommandGate.new()
var _pending: Array[Dictionary] = []
var _capacity: int = 0
var _per_tick: int = 0
var _last_tick: int = 0
var _generation: int = 0
var _sequence: int = 0
var _busy: bool = false
var _rejections: int = 0
var _attempts: int = 0
var _discarded: int = 0
var _peak: int = 0


func initialize(inventory: InventorySimulationSystem, world: StringName, region: StringName, provider: InventoryControllerSessionProvider, capacity: int = 64, per_tick: int = 16) -> ServiceResult:
	if _inventory != null or not is_instance_valid(inventory) or capacity < 1 or capacity > MAX_PENDING or per_tick < 1 or per_tick > capacity:
		return _reject(&"invalid_candidate")
	var snapshot: ServiceResult = inventory.capture_snapshot()
	if not snapshot.is_success:
		return _reject(snapshot.error_code)
	var result: ServiceResult = _gate.initialize(inventory, world, region, provider)
	if not result.is_success:
		return _reject(result.error_code)
	_inventory = inventory
	_capacity = capacity
	_per_tick = per_tick
	_last_tick = int(snapshot.value["last_tick"])
	_generation = inventory.controller_restore_generation()
	return ServiceResult.success()


func controller_authority() -> InventoryControllerAuthority:
	return _gate.controller_authority()


## Scoped reads use this queue's exact gate/authority without exposing dispatch.
## Busy reads fence provider reentrancy; restore detection clears volatile intent.
func own_inventory_observation(token: InventoryControllerToken, context: AuthenticatedCommandContext, include_details: bool = false) -> ServiceResult:
	return _observe(token, context, &"own", include_details)


func world_inventory_observation(token: InventoryControllerToken, context: AuthenticatedCommandContext) -> ServiceResult:
	return _observe(token, context, &"world")


func local_grip_observation(token: InventoryControllerToken, context: AuthenticatedCommandContext) -> ServiceResult:
	return _observe(token, context, &"grip")


func local_observation(token: InventoryControllerToken, context: AuthenticatedCommandContext) -> ServiceResult:
	return _observe(token, context, &"local")


func read_search(token: InventoryControllerToken, context: AuthenticatedCommandContext, view_id: String) -> ServiceResult:
	return _observe(token, context, &"search", false, view_id)


func _observe(token: InventoryControllerToken, context: AuthenticatedCommandContext, projection: StringName, include_details: bool = false, view_id: String = "") -> ServiceResult:
	if _busy or not is_instance_valid(_inventory):
		return _reject(&"queue_unavailable")
	if _sync_restore():
		return _reject(&"queue_restored")
	var snapshot: ServiceResult = _inventory.capture_snapshot()
	if not snapshot.is_success or int(snapshot.value["last_tick"]) != _last_tick:
		return _reject(&"queue_tick_mismatch")
	_busy = true
	var result: ServiceResult
	match projection:
		&"own": result = _gate.own_inventory_observation(token, context, include_details)
		&"world": result = _gate.world_inventory_observation(token, context)
		&"grip": result = _gate.local_grip_observation(token, context)
		&"local": result = _gate.local_observation(token, context)
		&"search": result = _gate.read_search(token, context, view_id)
		_: result = _reject(&"unsupported_operation")
	# The session provider is synchronous trusted code, but may free or advance
	# the actual runtime. Recheck ownership before publishing any projection.
	if not is_instance_valid(_inventory):
		_busy = false
		return _reject(&"queue_unavailable")
	if _sync_restore():
		_busy = false
		return _reject(&"queue_restored")
	snapshot = _inventory.capture_snapshot()
	_busy = false
	if not snapshot.is_success or int(snapshot.value["last_tick"]) != _last_tick:
		return _reject(&"queue_tick_mismatch")
	return result


## Token is opaque identity; trusted context and bounded plain intent are detached.
## Acceptance is only queue admission, never a canonical operation receipt.
func enqueue(token: InventoryControllerToken, context: AuthenticatedCommandContext, request_id: String, operation: String, payload: Dictionary) -> ServiceResult:
	if _busy or not is_instance_valid(_inventory):
		return _reject(&"queue_unavailable")
	if _sync_restore():
		return _reject(&"queue_restored")
	if _pending.size() >= _capacity:
		return _reject(&"queue_full")
	if _sequence >= InventoryControllerAuthority.MAX_EXACT_INTEGER:
		return _reject(&"queue_sequence_exhausted")
	var budget: Array[int] = [MAX_INTENT_NODES]
	if token == null or context == null or context.origin != AuthenticatedCommandContext.Origin.AUTHENTICATED_SESSION or not ControlContractValidation.is_id(request_id) or operation not in OPERATIONS or not _plain_intent(payload, 0, budget):
		return _reject(&"invalid_intent")
	if context.permissions.size() > 32:
		return _reject(&"invalid_intent")
	var detached := AuthenticatedCommandContext.new()
	detached.principal_id = context.principal_id
	detached.session_id = context.session_id
	detached.world_id = context.world_id
	detached.region_id = context.region_id
	for id in [detached.principal_id, detached.session_id, detached.world_id, detached.region_id]:
		if not ControlContractValidation.is_id(String(id)):
			return _reject(&"invalid_intent")
	for permission in context.permissions:
		if typeof(permission) not in [TYPE_STRING, TYPE_STRING_NAME] or String(permission).length() > MAX_TEXT or typeof(context.permissions[permission]) != TYPE_BOOL:
			return _reject(&"invalid_intent")
	detached.permissions = context.permissions.duplicate(true)
	# Inventory operations use no tool grants; never retain arbitrary tool objects.
	_sequence += 1
	_pending.append({"sequence": _sequence, "token": token, "context": detached, "request_id": request_id, "operation": operation, "payload": payload.duplicate(true)})
	_peak = maxi(_peak, _pending.size())
	return ServiceResult.success({"sequence": _sequence})


## Strict consecutive boundary: duplicate/skipped ticks retain pending commands.
## Returns bounded transient results, then advances jobs once; never emits callbacks.
func advance_tick(tick: int, fixed_delta: float) -> ServiceResult:
	if _busy or not is_instance_valid(_inventory):
		return _reject(&"queue_unavailable")
	if _sync_restore():
		return _reject(&"queue_restored")
	if tick != _last_tick + 1 or tick > InventoryControllerAuthority.MAX_EXACT_INTEGER or not is_finite(fixed_delta) or fixed_delta <= 0.0:
		return _reject(&"queue_tick_mismatch")
	# Fail closed if another caller advanced this runtime outside this composition.
	var snapshot: ServiceResult = _inventory.capture_snapshot()
	if not snapshot.is_success or int(snapshot.value["last_tick"]) != _last_tick:
		return _reject(&"queue_tick_mismatch")
	_busy = true
	var outcomes: Array[Dictionary] = []
	var count: int = mini(_per_tick, _pending.size())
	for index in range(count):
		var entry: Dictionary = _pending.pop_front()
		var result: ServiceResult = _gate.apply(entry["token"], entry["context"], entry["request_id"], entry["operation"], entry["payload"], tick)
		_attempts = mini(_attempts + 1, InventoryControllerAuthority.MAX_EXACT_INTEGER)
		outcomes.append({"sequence": entry["sequence"], "request_id": entry["request_id"], "result": result})
		# Recheck after admission even when the gate denied the command. Never
		# touch a freed runtime or drain another intent after losing tick ownership.
		if not is_instance_valid(_inventory):
			return _interrupt_drain(&"queue_unavailable")
		if _sync_restore():
			return _interrupt_drain(&"queue_restored")
		snapshot = _inventory.capture_snapshot()
		if not snapshot.is_success or int(snapshot.value["last_tick"]) != _last_tick:
			return _interrupt_drain(&"queue_tick_mismatch")
	_inventory.simulate_tick(tick, fixed_delta)
	_last_tick = tick
	_busy = false
	return ServiceResult.success(outcomes)


## Trusted disconnect cleanup is volatile; authority revoke remains caller-owned.
func discard_session(principal: StringName, session: StringName) -> ServiceResult:
	if _busy or not is_instance_valid(_inventory):
		return _reject(&"queue_unavailable")
	_sync_restore()
	var removed: int = 0
	for index in range(_pending.size() - 1, -1, -1):
		var context: AuthenticatedCommandContext = _pending[index]["context"]
		if context.principal_id == principal and context.session_id == session:
			_pending.remove_at(index)
			removed += 1
	_discarded = mini(_discarded + removed, InventoryControllerAuthority.MAX_EXACT_INTEGER)
	return ServiceResult.success({"discarded": removed})


func profiling_counters() -> Dictionary:
	return {"pending": _pending.size(), "peak": _peak, "attempts": _attempts, "rejections": _rejections, "discarded": _discarded, "sequence": _sequence}


## Attempted entries stay consumed; unattempted intent is never replayed after
## an interrupted boundary. Earlier successful commands are not rolled back.
func _interrupt_drain(code: StringName) -> ServiceResult:
	_discard_pending()
	_busy = false
	return _reject(code)


func _discard_pending() -> void:
	_discarded = mini(_discarded + _pending.size(), InventoryControllerAuthority.MAX_EXACT_INTEGER)
	_pending.clear()


func _sync_restore() -> bool:
	var generation: int = _inventory.controller_restore_generation()
	if generation == _generation:
		return false
	_discard_pending()
	_generation = generation
	_last_tick = int(_inventory.capture_snapshot().value["last_tick"])
	return true


func _plain_intent(value: Variant, depth: int, budget: Array[int]) -> bool:
	budget[0] -= 1
	if budget[0] < 0 or depth > 4:
		return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT:
			return true
		TYPE_STRING:
			return value.length() <= MAX_TEXT
		TYPE_ARRAY, TYPE_DICTIONARY:
			if value.size() > MAX_INTENT_NODES:
				return false
			for key in value:
				if typeof(value) == TYPE_DICTIONARY:
					if typeof(key) != TYPE_STRING or key.length() > MAX_TEXT:
						return false
					if not _plain_intent(value[key], depth + 1, budget):
						return false
				elif not _plain_intent(key, depth + 1, budget):
					return false
			return true
	return false


func _reject(code: StringName) -> ServiceResult:
	_rejections = mini(_rejections + 1, InventoryControllerAuthority.MAX_EXACT_INTEGER)
	return ServiceResult.failure(code, "Inventory runtime command queue rejected the request.")
