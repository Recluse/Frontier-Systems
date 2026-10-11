extends RefCounted
class_name InventoryRuntimeCommandGate

## Explicit same-process composition. Never a network payload or fixture fallback.
## Lifecycle callers and authenticated contexts must come from trusted owners.
var _inventory: InventorySimulationSystem
var _authority: InventoryControllerAuthority
var _rejections: int = 0
var _applications: int = 0


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
	var admitted: ServiceResult = _authority.validate(token, context, StringName(actor.value))
	if not admitted.is_success:
		return _reject(admitted.error_code)
	if operation not in ["self", "world", "start", "cancel", "resume", "resist", "close_search", "grip_join", "grip_release", "grip_resume"]:
		return _reject(&"unsupported_operation")
	# Synchronous canonical dispatch; no callbacks/await or fallback after admission.
	var result: ServiceResult = _inventory.apply_local(context, request_id, operation, payload.duplicate(true), tick)
	_applications = mini(_applications + 1, InventoryControllerAuthority.MAX_EXACT_INTEGER)
	return result


func profiling_counters() -> Dictionary:
	return {"applications": _applications, "rejections": _rejections}


func _reject(code: StringName) -> ServiceResult:
	_rejections = mini(_rejections + 1, InventoryControllerAuthority.MAX_EXACT_INTEGER)
	return ServiceResult.failure(code, "Inventory runtime command gate rejected the command.")
