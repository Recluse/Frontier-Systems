extends RefCounted
class_name InventoryControllerAuthority

## Standalone FP-01 binding domain. Not composed into inventory or admission.
## Lifecycle entrypoints are trusted tick-boundary calls, never client payloads.
const MAX_BINDINGS: int = 32
const MAX_EXACT_INTEGER: int = 9007199254740990

var _world: StringName
var _region: StringName
var _provider: InventoryControllerSessionProvider
var _bindings: Dictionary = {}
var _initialized: bool = false
var _rejections: int = 0


## Atomic initial candidate: body IDs must exactly match the supplied owner IDs.
## Records are isolated fixtures, not canonical inventory metadata or persistence.
func initialize(world: StringName, region: StringName, bodies: Array, owner_body_ids: PackedStringArray, provider: InventoryControllerSessionProvider) -> ServiceResult:
	if _initialized or not ControlContractValidation.is_id(String(world)) or not ControlContractValidation.is_id(String(region)) or provider == null or bodies.size() > MAX_BINDINGS or owner_body_ids.size() != bodies.size():
		return _reject(&"invalid_candidate")
	var candidate: Dictionary = {}
	var principals: Dictionary = {}
	for id in owner_body_ids:
		if not ControlContractValidation.is_id(id) or owner_body_ids.count(id) != 1:
			return _reject(&"invalid_candidate")
	for raw in bodies:
		if typeof(raw) != TYPE_DICTIONARY:
			return _reject(&"invalid_candidate")
		var body: Dictionary = raw
		if not ControlContractValidation.has_exact_fields(body, PackedStringArray(["body_id", "principal_id", "control_epoch"])) or not ControlContractValidation.is_id(body.get("body_id")) or not ControlContractValidation.is_id(body.get("principal_id")) or not ControlContractValidation.is_integer(body.get("control_epoch"), 0, MAX_EXACT_INTEGER):
			return _reject(&"invalid_candidate")
		if candidate.has(body["body_id"]) or principals.has(body["principal_id"]) or not owner_body_ids.has(body["body_id"]):
			return _reject(&"invalid_candidate")
		candidate[body["body_id"]] = {"principal_id": body["principal_id"], "control_epoch": int(body["control_epoch"]), "session_id": &"", "token": null}
		principals[body["principal_id"]] = true
	_world = world
	_region = region
	_provider = provider
	_bindings = candidate
	_initialized = true
	return ServiceResult.success()


func bind(body_id: StringName, principal: StringName, session: StringName, expected_epoch: int) -> ServiceResult:
	return _transition(body_id, principal, session, expected_epoch, &"bind")


func replace(body_id: StringName, principal: StringName, session: StringName, expected_epoch: int) -> ServiceResult:
	return _transition(body_id, principal, session, expected_epoch, &"replace")


func revoke(body_id: StringName, principal: StringName, expected_epoch: int) -> ServiceResult:
	return _transition(body_id, principal, &"", expected_epoch, &"revoke")


## At most one opaque token per active binding; repeated pin has bounded storage.
func pin(context: AuthenticatedCommandContext) -> ServiceResult:
	if not _context_valid(context):
		return _reject(&"session_denied")
	for id in _bindings:
		var binding: Dictionary = _bindings[id]
		if StringName(binding["principal_id"]) == context.principal_id and binding["session_id"] == context.session_id and binding["token"] != null:
			return ServiceResult.success(binding["token"])
	return _reject(&"session_denied")


## Recheck current identity, grant, session liveness and issuing object identity.
## Expected body is server-owned command routing, never a client-selected actor.
func validate(token: InventoryControllerToken, context: AuthenticatedCommandContext, expected_body: StringName) -> ServiceResult:
	if token == null or not _bindings.has(String(expected_body)):
		return _reject(&"stale_or_foreign_token")
	var binding: Dictionary = _bindings[String(expected_body)]
	if binding["token"] != token:
		return _reject(&"stale_or_foreign_token")
	if not _context_valid(context) or StringName(binding["principal_id"]) != context.principal_id or binding["session_id"] != context.session_id:
		return _reject(&"session_denied")
	return ServiceResult.success({"body_id": String(expected_body), "control_epoch": binding["control_epoch"]})


## Detached observation, explicitly not a durable snapshot or canonical body copy.
func observation() -> Dictionary:
	var result: Dictionary = {}
	for id in _bindings:
		var binding: Dictionary = _bindings[id]
		result[id] = {"principal_id": binding["principal_id"], "control_epoch": binding["control_epoch"], "active": binding["token"] != null}
	return result


func profiling_counters() -> Dictionary:
	var active: int = 0
	for binding in _bindings.values():
		if binding["token"] != null:
			active += 1
	return {"bindings": _bindings.size(), "active_controllers": active, "rejections": _rejections}


func _transition(body_id: StringName, principal: StringName, session: StringName, expected_epoch: int, operation: StringName) -> ServiceResult:
	if not _initialized or not _bindings.has(String(body_id)):
		return _reject(&"unknown_body")
	var current: Dictionary = _bindings[String(body_id)]
	if StringName(current["principal_id"]) != principal or current["control_epoch"] != expected_epoch:
		return _reject(&"binding_conflict")
	if current["control_epoch"] >= MAX_EXACT_INTEGER:
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
	# No fallible mutation after candidate preparation. Retired identities are dropped.
	var candidate: Dictionary = current.duplicate()
	candidate["control_epoch"] = int(current["control_epoch"]) + 1
	candidate["session_id"] = session
	candidate["token"] = null if operation == &"revoke" else InventoryControllerToken.new()
	_bindings[String(body_id)] = candidate
	return ServiceResult.success(candidate["control_epoch"])


func _context_valid(context: AuthenticatedCommandContext) -> bool:
	return _initialized and context != null and context.origin == AuthenticatedCommandContext.Origin.AUTHENTICATED_SESSION and context.is_valid_for(_world, _region) and context.has_permission(&"inventory.operate") and _provider.permits_inventory(context.principal_id, context.session_id, _world, _region)


func _reject(code: StringName) -> ServiceResult:
	_rejections = mini(_rejections + 1, MAX_EXACT_INTEGER)
	return ServiceResult.failure(code, "Inventory controller authority rejected the candidate.")
