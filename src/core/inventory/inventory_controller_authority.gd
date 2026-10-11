extends RefCounted
class_name InventoryControllerAuthority

## FP-01 session/token component. Canonical epochs belong exclusively to owner.
## Not composed into production admission. Lifecycle calls are trusted/synchronous.
const MAX_BINDINGS: int = 32
const MAX_EXACT_INTEGER: int = 9007199254740990

var _world: StringName
var _region: StringName
var _provider: InventoryControllerSessionProvider
var _owner: InventoryControllerOwner
var _bindings: Dictionary = {}
var _restore_generation: int = -1
var _initialized: bool = false
var _rejections: int = 0


func initialize(world: StringName, region: StringName, owner: InventoryControllerOwner, provider: InventoryControllerSessionProvider) -> ServiceResult:
	if _initialized or not ControlContractValidation.is_id(String(world)) or not ControlContractValidation.is_id(String(region)) or owner == null or provider == null:
		return _reject(&"invalid_candidate")
	var checked: ServiceResult = _read_candidate(owner)
	if not checked.is_success:
		return _reject(&"invalid_candidate")
	var generation: ServiceResult = _read_generation(owner)
	if not generation.is_success:
		return _reject(&"invalid_candidate")
	var candidate: Dictionary = _empty_bindings(checked.value)
	_world = world
	_region = region
	_provider = provider
	_owner = owner
	_restore_generation = generation.value
	_bindings = candidate
	_initialized = true
	return ServiceResult.success()


## Trusted synchronous reset after successful canonical restore. No auto-binding.
## Validate the complete bounded owner before atomically retiring all identities.
func reconcile_after_restore() -> ServiceResult:
	if not _initialized:
		return _reject(&"invalid_candidate")
	var generation: ServiceResult = _read_generation(_owner)
	if not generation.is_success or generation.value <= _restore_generation:
		return _reject(&"restore_conflict")
	var checked: ServiceResult = _read_candidate(_owner)
	if not checked.is_success:
		return _reject(&"invalid_candidate")
	var candidate: Dictionary = _empty_bindings(checked.value)
	_bindings = candidate
	_restore_generation = generation.value
	return ServiceResult.success()


func _empty_bindings(bodies: Dictionary) -> Dictionary:
	var candidate: Dictionary = {}
	for id in bodies:
		var body: Dictionary = bodies[id]
		candidate[id] = {"principal_id": body["principal_id"], "body_container_id": body["body_container_id"],
			"session_id": &"", "token": null, "token_epoch": -1}
	return candidate


func bind(body_id: StringName, principal: StringName, session: StringName, expected_epoch: int) -> ServiceResult:
	return _transition(body_id, principal, session, expected_epoch, &"bind")


func replace(body_id: StringName, principal: StringName, session: StringName, expected_epoch: int) -> ServiceResult:
	return _transition(body_id, principal, session, expected_epoch, &"replace")


func revoke(body_id: StringName, principal: StringName, expected_epoch: int) -> ServiceResult:
	return _transition(body_id, principal, &"", expected_epoch, &"revoke")


func pin(context: AuthenticatedCommandContext) -> ServiceResult:
	if not _context_valid(context):
		return _reject(&"session_denied")
	var checked: ServiceResult = _current()
	if not checked.is_success:
		return _reject(&"invalid_candidate")
	for id in _bindings:
		var binding: Dictionary = _bindings[id]
		if StringName(binding["principal_id"]) == context.principal_id and binding["session_id"] == context.session_id and binding["token"] != null and binding["token_epoch"] == checked.value[id]["control_epoch"]:
			return ServiceResult.success(binding["token"])
	return _reject(&"session_denied")


## Server-derived expected body; current owner agreement precedes token admission.
func validate(token: InventoryControllerToken, context: AuthenticatedCommandContext, expected_body: StringName) -> ServiceResult:
	if token == null or not _bindings.has(String(expected_body)):
		return _reject(&"stale_or_foreign_token")
	if not _context_valid(context):
		return _reject(&"session_denied")
	var checked: ServiceResult = _current()
	if not checked.is_success:
		return _reject(&"invalid_candidate")
	var binding: Dictionary = _bindings[String(expected_body)]
	if binding["token"] != token or binding["token_epoch"] != checked.value[String(expected_body)]["control_epoch"]:
		return _reject(&"stale_or_foreign_token")
	if StringName(binding["principal_id"]) != context.principal_id or binding["session_id"] != context.session_id:
		return _reject(&"session_denied")
	return ServiceResult.success(checked.value[String(expected_body)].duplicate(true))


## Detached live projection, never durable state. Invalid owner yields no claims.
func observation() -> Dictionary:
	var checked: ServiceResult = _current()
	if not checked.is_success:
		return {}
	var result: Dictionary = {}
	for id in _bindings:
		var binding: Dictionary = _bindings[id]
		result[id] = {"principal_id": binding["principal_id"], "body_container_id": binding["body_container_id"],
			"control_epoch": checked.value[id]["control_epoch"],
			"active": binding["token"] != null and binding["token_epoch"] == checked.value[id]["control_epoch"]}
	return result


func profiling_counters() -> Dictionary:
	var active: int = 0
	for body in observation().values():
		if body["active"]:
			active += 1
	return {"bindings": _bindings.size(), "active_controllers": active, "rejections": _rejections, "reconciled_restore_generation": _restore_generation}


func _transition(body_id: StringName, principal: StringName, session: StringName, expected_epoch: int, operation: StringName) -> ServiceResult:
	if not _initialized or not _bindings.has(String(body_id)):
		return _reject(&"unknown_body")
	var checked: ServiceResult = _current()
	if not checked.is_success:
		return _reject(&"invalid_candidate")
	var transition_generation: int = _restore_generation
	var body: Dictionary = checked.value[String(body_id)]
	var current: Dictionary = _bindings[String(body_id)]
	if StringName(body["principal_id"]) != principal or body["control_epoch"] != expected_epoch:
		return _reject(&"binding_conflict")
	if body["control_epoch"] >= MAX_EXACT_INTEGER:
		return _reject(&"epoch_exhausted")
	var active: bool = current["token"] != null
	if (operation == &"bind" and active) or (operation != &"bind" and not active) or (operation == &"replace" and current["session_id"] == session):
		return _reject(&"invalid_lifecycle")
	if operation != &"revoke":
		if not ControlContractValidation.is_id(String(session)) or not _provider.permits_inventory(principal, session, _world, _region):
			return _reject(&"session_denied")
		for other in _bindings.values():
			if other["session_id"] == session:
				return _reject(&"binding_conflict")
	var next_epoch: int = int(body["control_epoch"]) + 1
	var candidate: Dictionary = current.duplicate()
	candidate["session_id"] = session
	candidate["token"] = null if operation == &"revoke" else InventoryControllerToken.new()
	candidate["token_epoch"] = next_epoch if operation != &"revoke" else -1
	# Provider callbacks may restore identical epochs; recheck the volatile fence.
	var rechecked: ServiceResult = _current()
	if not rechecked.is_success or _restore_generation != transition_generation:
		return _reject(&"restore_conflict")
	var committed: ServiceResult = _owner.commit_control_epoch(body, next_epoch)
	if not committed.is_success:
		return _reject(committed.error_code)
	# No fallible work/callback between canonical commit and token publication.
	_bindings[String(body_id)] = candidate
	return ServiceResult.success(next_epoch)


func _current() -> ServiceResult:
	if not _initialized:
		return ServiceResult.failure(&"invalid_candidate", "Uninitialized authority.")
	var generation: ServiceResult = _read_generation(_owner)
	if not generation.is_success or generation.value != _restore_generation:
		return ServiceResult.failure(&"restore_conflict", "Canonical restore requires explicit reconciliation.")
	var checked: ServiceResult = _read_candidate(_owner)
	if not checked.is_success or checked.value.size() != _bindings.size():
		return ServiceResult.failure(&"invalid_candidate", "Canonical owner changed.")
	for id in checked.value:
		var body: Dictionary = checked.value[id]
		if not _bindings.has(id) or body["principal_id"] != _bindings[id]["principal_id"] or body["body_container_id"] != _bindings[id]["body_container_id"]:
			return ServiceResult.failure(&"invalid_candidate", "Canonical body/root identity changed.")
	return checked


func _read_generation(owner: InventoryControllerOwner) -> ServiceResult:
	var generation: ServiceResult = owner.controller_restore_generation()
	if not generation.is_success or not ControlContractValidation.is_integer(generation.value, 0, MAX_EXACT_INTEGER):
		return ServiceResult.failure(&"invalid_candidate", "Invalid restore generation.")
	return generation


func _read_candidate(owner: InventoryControllerOwner) -> ServiceResult:
	var checked: ServiceResult = owner.controller_candidate()
	if not checked.is_success or typeof(checked.value) != TYPE_DICTIONARY or checked.value.size() > MAX_BINDINGS:
		return ServiceResult.failure(&"invalid_candidate", "Invalid canonical owner.")
	var principals: Dictionary = {}
	var roots: Dictionary = {}
	for id in checked.value:
		var body: Variant = checked.value[id]
		if typeof(body) != TYPE_DICTIONARY or not ControlContractValidation.has_exact_fields(body, PackedStringArray(["body_id", "principal_id", "body_container_id", "control_epoch"])):
			return ServiceResult.failure(&"invalid_candidate", "Invalid canonical body.")
		if id != body["body_id"] or not ControlContractValidation.is_id(id) or not ControlContractValidation.is_id(body["principal_id"]) or not ControlContractValidation.is_id(body["body_container_id"]) or not ControlContractValidation.is_integer(body["control_epoch"], 0, MAX_EXACT_INTEGER):
			return ServiceResult.failure(&"invalid_candidate", "Invalid canonical body identity.")
		if principals.has(body["principal_id"]) or roots.has(body["body_container_id"]):
			return ServiceResult.failure(&"invalid_candidate", "Duplicate canonical principal/root.")
		principals[body["principal_id"]] = true
		roots[body["body_container_id"]] = true
	return ServiceResult.success(checked.value.duplicate(true))


func _context_valid(context: AuthenticatedCommandContext) -> bool:
	return _initialized and context != null and context.origin == AuthenticatedCommandContext.Origin.AUTHENTICATED_SESSION and context.is_valid_for(_world, _region) and context.has_permission(&"inventory.operate") and _provider.permits_inventory(context.principal_id, context.session_id, _world, _region)


func _reject(code: StringName) -> ServiceResult:
	_rejections = mini(_rejections + 1, MAX_EXACT_INTEGER)
	return ServiceResult.failure(code, "Inventory controller authority rejected the candidate.")
