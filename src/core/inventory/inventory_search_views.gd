extends RefCounted
class_name InventorySearchViews

## Volatile, bounded scoped views. Never restored from world snapshots.
const MAX_VIEWS: int = 64
const MAX_EXACT_INTEGER: int = 9007199254740990
var _views: Dictionary = {}
var _last_tick: int = 0
var _lifetime_ticks: int = 300


func _init(lifetime_ticks: int = 300) -> void:
	_lifetime_ticks = clampi(lifetime_ticks, 1, 3600)


## Principal and observations must come from authenticated server context.
func grant(job: BodyInventoryInteractionJob, tick: int, owner: SharedInventoryCoordinator, principal_id: String, context: Dictionary, observation: Dictionary) -> ServiceResult:
	if job == null or owner == null or not ControlContractValidation.is_id(principal_id) or not _advance_clock(tick):
		return _failure("A current tick, trusted owner/job/policy and authenticated principal are required.")
	var state: Dictionary = job.to_record()
	var rules: Dictionary = job.policy_record()
	if state["action"] != "search" or state["policy_id"] != rules["definition_id"] or int(state["policy_revision"]) != int(rules["revision"]):
		return _failure("Only a matching completed search policy can produce a view.")
	var id: String = state["job_id"]
	if _views.has(id):
		if JSON.stringify(_views[id]["job"]) != JSON.stringify(state):
			return _failure("A retained search job ID cannot be reused for different state or targets.")
		return read(id, tick, owner, principal_id, context, observation)
	var ready: ServiceResult = job.completion_candidate(tick, context, observation)
	if not ready.is_success:
		return ready
	var projected: ServiceResult = owner.direct_container_observation(state["actor_body_id"], state["target_body_id"], state["target_container_id"])
	if not projected.is_success:
		return projected
	if projected.value["actor_inventory_revision"] != int(state["actor_inventory_revision"]) or projected.value["target_inventory_revision"] != int(state["target_inventory_revision"]):
		return _failure("The participating inventories changed before search completion.")
	if _views.size() >= MAX_VIEWS or tick > MAX_EXACT_INTEGER - _lifetime_ticks:
		return _failure("Search views are at capacity or their expiry would overflow.")
	_views[id] = {"principal_id": principal_id, "job": state, "policy": BodyInventoryInteractionPolicy.from_record(rules).value,
		"owner": owner, "owner_id": projected.value["owner_id"], "owner_revision": projected.value["state_revision"],
		"issued_tick": tick, "expires_tick": tick + _lifetime_ticks}
	return read(id, tick, owner, principal_id, context, observation)


func read(view_id: String, tick: int, owner: SharedInventoryCoordinator, principal_id: String, context: Dictionary, observation: Dictionary) -> ServiceResult:
	if owner == null or not _advance_clock(tick) or not _views.has(view_id):
		return _failure("The scoped search view is unavailable.")
	var view: Dictionary = _views[view_id]
	# A different principal cannot consume or revoke someone else's observation.
	if principal_id != view["principal_id"]:
		return _failure("The view belongs to another authenticated principal.")
	if owner != view["owner"]:
		return _revoke(view_id, "The authoritative inventory owner instance changed.")
	var state: Dictionary = view["job"]
	if not ControlContractValidation.has_exact_fields(context, PackedStringArray(BodyInventoryInteractionJob.CONTEXT_FIELDS)):
		return _revoke(view_id, "A complete server action context is required.")
	for field in BodyInventoryInteractionJob.CONTEXT_FIELDS:
		if not ControlContractValidation.is_integer(context[field], 0, MAX_EXACT_INTEGER) or int(context[field]) != int(state[field]):
			return _revoke(view_id, "Action/control epochs or inventory revisions changed.")
	var assessed: ServiceResult = view["policy"].assess("search", observation)
	if not assessed.is_success:
		_views.erase(view_id)
		return assessed
	var projected: ServiceResult = owner.direct_container_observation(state["actor_body_id"], state["target_body_id"], state["target_container_id"])
	if not projected.is_success or projected.value["owner_id"] != view["owner_id"] or projected.value["state_revision"] != view["owner_revision"] or projected.value["actor_inventory_revision"] != int(state["actor_inventory_revision"]) or projected.value["target_inventory_revision"] != int(state["target_inventory_revision"]):
		return _revoke(view_id, "The inventory owner or searched state changed.")
	return ServiceResult.success({"schema_version": 1, "view_id": view_id, "actor_body_id": state["actor_body_id"],
		"target_body_id": state["target_body_id"], "container_id": state["target_container_id"],
		"issued_tick": view["issued_tick"], "expires_tick": view["expires_tick"], "items": projected.value["items"].duplicate(true)})


func revoke_principal(principal_id: String) -> void:
	for id in _views.keys():
		if _views[id]["principal_id"] == principal_id:
			_views.erase(id)


func close(view_id: String, principal_id: String) -> ServiceResult:
	if not _views.has(view_id) or _views[view_id]["principal_id"] != principal_id:
		return _failure("The scoped view is unavailable to this principal.")
	_views.erase(view_id)
	return ServiceResult.success()


func diagnostics() -> Dictionary:
	return {"active_views": _views.size(), "capacity": MAX_VIEWS}


func advance_tick(tick: int) -> ServiceResult:
	return ServiceResult.success() if _advance_clock(tick) else _failure("Search views require monotonic server ticks.")


func targets_for_principal(view_id: String, principal_id: String) -> ServiceResult:
	if not _views.has(view_id) or _views[view_id]["principal_id"] != principal_id:
		return _failure("The scoped view is unavailable to this principal.")
	var state: Dictionary = _views[view_id]["job"]
	return ServiceResult.success({"actor_body_id": state["actor_body_id"], "target_body_id": state["target_body_id"]})


func _advance_clock(tick: int) -> bool:
	if tick < _last_tick or tick < 0 or tick > MAX_EXACT_INTEGER:
		return false
	_last_tick = tick
	for id in _views.keys():
		if tick >= int(_views[id]["expires_tick"]):
			_views.erase(id)
	return true


func _revoke(id: String, reason: String) -> ServiceResult:
	_views.erase(id)
	return _failure(reason)


static func _failure(message: String) -> ServiceResult:
	return ServiceResult.failure(&"inventory_search_view_unavailable", message)
