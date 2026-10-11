extends RefCounted
class_name InventoryRuntimeCommandGate

## Explicit same-process composition. Never a network payload or fixture fallback.
## Lifecycle callers and authenticated contexts must come from trusted owners.
var _inventory: InventorySimulationSystem
var _authority: InventoryControllerAuthority
var _rejections: int = 0
var _applications: int = 0
var _observations: int = 0


func initialize(inventory: InventorySimulationSystem, world: StringName, region: StringName, provider: InventoryControllerSessionProvider) -> ServiceResult:
	if _authority != null or not is_instance_valid(inventory):
		return _reject(&"invalid_candidate")
	var authority := InventoryControllerAuthority.new()
	var initialized: ServiceResult = authority.initialize(world, region, InventoryRuntimeControllerOwner.new(inventory), provider)
	if not initialized.is_success:
		return _reject(initialized.error_code)
	_inventory = inventory
	_authority = authority
	return ServiceResult.success()


## Trusted lifecycle surface; caller must not expose this object to clients.
func controller_authority() -> InventoryControllerAuthority:
	return _authority


## Validate at application, even if a queue previously pinned this token.
## Body comes from the same canonical runtime; scope comes from composition.
func apply(token: InventoryControllerToken, context: AuthenticatedCommandContext, request_id: String, operation: String, payload: Dictionary, tick: int) -> ServiceResult:
	if _authority == null or not is_instance_valid(_inventory):
		return _reject(&"invalid_candidate")
	var actor: ServiceResult = _inventory.authorize(context, true)
	if not actor.is_success:
		return _reject(actor.error_code)
	# Pin canonical ownership across synchronous session-provider callbacks.
	var snapshot: ServiceResult = _inventory.capture_snapshot()
	if not snapshot.is_success:
		return _reject(&"invalid_candidate")
	var generation: int = _inventory.controller_restore_generation()
	var admitted: ServiceResult = _authority.validate(token, context, StringName(actor.value))
	if not is_instance_valid(_inventory):
		return _reject(&"invalid_candidate")
	if _inventory.controller_restore_generation() != generation:
		return _reject(&"invalid_candidate")
	var rechecked: ServiceResult = _inventory.capture_snapshot()
	if not rechecked.is_success or int(rechecked.value["last_tick"]) != int(snapshot.value["last_tick"]):
		return _reject(&"invalid_candidate")
	if not admitted.is_success:
		return _reject(admitted.error_code)
	if operation not in ["open_container", "close_container", "self", "world", "start", "cancel", "resume", "resist", "close_search", "grip_join", "grip_release", "grip_resume"]:
		return _reject(&"unsupported_operation")
	# Synchronous canonical dispatch; no callbacks/await or fallback after admission.
	var result: ServiceResult = _inventory.apply_local(context, request_id, operation, payload.duplicate(true), tick)
	_applications = mini(_applications + 1, InventoryControllerAuthority.MAX_EXACT_INTEGER)
	return result


## Reads share this gate's exact command runtime/authority. No actor/scope input.
## Read-only projections need no voluntary-action grant; search retains its own.
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
	if _authority == null or not is_instance_valid(_inventory):
		return _reject(&"invalid_candidate")
	var actor: ServiceResult = _inventory.authorize(context)
	if not actor.is_success:
		return _reject(actor.error_code)
	var admitted: ServiceResult = _authority.validate(token, context, StringName(actor.value))
	if not admitted.is_success:
		return _reject(admitted.error_code)
	# Synchronous scoped dispatch, after provider callbacks and restore fencing.
	var result: ServiceResult
	match projection:
		&"own": result = _inventory.own_inventory_observation(context, include_details)
		&"world": result = _inventory.world_inventory_observation(context)
		&"grip": result = _inventory.local_grip_observation(context)
		&"local": result = _inventory.local_observation(context)
		&"search": result = _inventory.read_search(context, view_id)
		_: return _reject(&"unsupported_operation")
	_observations = mini(_observations + 1, InventoryControllerAuthority.MAX_EXACT_INTEGER)
	return ServiceResult.success(result.value.duplicate(true)) if result.is_success else result


func profiling_counters() -> Dictionary:
	return {"applications": _applications, "observations": _observations, "rejections": _rejections}


func _reject(code: StringName) -> ServiceResult:
	_rejections = mini(_rejections + 1, InventoryControllerAuthority.MAX_EXACT_INTEGER)
	return ServiceResult.failure(code, "Inventory runtime command gate rejected admission.")
