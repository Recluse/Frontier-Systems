extends SimulationSystem
class_name InventorySimulationSystem

## Local development slice: logical fixture bodies, not networked player physics.
const SYSTEM_ID: StringName = &"inventory"
const MAX_JOBS: int = 32
const MAX_EXACT_INTEGER: int = 9007199254740990
var _catalog := InventoryItemCatalog.new()
var _profiles: Dictionary = {}
var _policy: BodyInventoryInteractionPolicy
var _owner: SharedInventoryCoordinator
var _bodies: Dictionary = {}
var _jobs: Dictionary = {}
var _views := InventorySearchViews.new()
var _last_tick: int = 0
var _outcomes: Array = []
var _setup: ServiceResult
var _world_storage: Dictionary = {}
var _grips: PhysicalGripOwner
var _health: HealthSimulationSystem
var _tool_capability_provider: Callable
## Logical development targets; these are not inventory items or rigid bodies.
const GRIP_TARGETS: Dictionary = {
	"fixture.salvage-crate": {"position": [0, 0, 0], "movable": true, "required_force": 300000},
	"fixture.ladder": {"position": [0, 0, 0], "movable": false, "required_force": 100000}
}
const WORLD_REACH_MILLIMETRES: int = 1500


func _init() -> void:
	system_id = SYSTEM_ID
	tick_priority = 200


func configure_defaults(include_resource_carriers: bool = false) -> ServiceResult:
	for definition in JSON.parse_string(FileAccess.get_file_as_string("res://data/inventory/items.default.v1.json")):
		var registered: ServiceResult = _catalog.register_definition(definition)
		if not registered.is_success:
			return registered
	for name in ["human", "cyborg", "station-ai"]:
		var parsed: ServiceResult = InventoryEquipmentProfile.from_record(JSON.parse_string(FileAccess.get_file_as_string("res://data/inventory/%s.v1.json" % name)))
		if not parsed.is_success:
			return parsed
		var record: Dictionary = parsed.value.to_record()
		_profiles[JSON.stringify([record["definition_id"], int(record["revision"])])] = parsed.value
	var parsed_policy: ServiceResult = BodyInventoryInteractionPolicy.from_record(JSON.parse_string(FileAccess.get_file_as_string("res://data/inventory/body-interactions.default.v1.json")))
	if not parsed_policy.is_success:
		return parsed_policy
	_policy = parsed_policy.value
	var fixture_path: String = "res://data/inventory/shared.production.v1.json" if include_resource_carriers else "res://data/inventory/shared.default.v1.json"
	var parsed_owner: ServiceResult = SharedInventoryCoordinator.from_record(JSON.parse_string(FileAccess.get_file_as_string(fixture_path)), _profiles, _catalog)
	if not parsed_owner.is_success:
		return parsed_owner
	_owner = parsed_owner.value
	_grips = PhysicalGripOwner.create("inventory.grips.prototype").value
	_bodies = {"body.human-1": _body("body.human-1", "local-inventory-target", 1000),
		"body.human-2": _body("body.human-2", "local-inventory-actor", 0)}
	_world_storage = {"world.tray-1": {"container_id": "world.tray-1", "position_millimetres": [0, 0, 0], "accessible": true}}
	_setup = ServiceResult.success()
	return _setup


func bind_health(health: HealthSimulationSystem) -> ServiceResult:
	if _health != null or health == null:
		return _failure("Bind one health capability provider to this inventory runtime.")
	_health = health
	return ServiceResult.success()


func authorize(context: AuthenticatedCommandContext, require_voluntary_action: bool = false) -> ServiceResult:
	var local_grant: bool = context != null and OS.is_debug_build() and context.origin == AuthenticatedCommandContext.Origin.DEVELOPMENT_LOCAL and context.has_permission("inventory.development")
	var session_grant: bool = context != null and context.origin == AuthenticatedCommandContext.Origin.AUTHENTICATED_SESSION and context.has_permission("inventory.operate")
	if _setup == null or not (local_grant or session_grant):
		return _failure("Inventory fixture commands require local development grants.")
	for body in _bodies.values():
		if body["principal_id"] == String(context.principal_id):
			if require_voluntary_action and not _body_can_act(body["body_id"]):
				return _failure("This body cannot perform voluntary inventory actions while unconscious or without health state.")
			return ServiceResult.success(body["body_id"])
	return _failure("The local principal has no registered inventory fixture body.")


func own_position(context: AuthenticatedCommandContext) -> ServiceResult:
	var allowed: ServiceResult = authorize(context)
	return ServiceResult.success(_bodies[allowed.value]["position_millimetres"].duplicate()) if allowed.is_success else allowed


## Resolve a usable active-hand tool from canonical equipment, never client tags.
func active_tool(context: AuthenticatedCommandContext, required_tag: String) -> ServiceResult:
	var allowed: ServiceResult = authorize(context, true)
	if not allowed.is_success:
		return allowed
	var record: Dictionary = _owner.to_record()
	for body in record["bodies"]:
		if body["body_id"] != allowed.value:
			continue
		for binding in body["equipped"]:
			if binding["slot_id"] != body["active_hand_slot_id"] or _grip_slot_reserved(allowed.value, binding["slot_id"]):
				continue
			for item in record["ledger"]["items"]:
				if item["item_id"] == binding["item_id"]:
					var definition: ServiceResult = _catalog.get_definition(item["definition_id"], int(item["definition_revision"]))
					if definition.is_success and definition.value["tags"].has(required_tag):
						if _tool_capability_provider.is_valid():
							var capable: ServiceResult = _tool_capability_provider.call(item["item_id"], required_tag)
							if capable.is_success and capable.value == true: return ServiceResult.success(item["item_id"])
						elif int(item["condition_permille"]) > 0:
							return ServiceResult.success(item["item_id"])
	return _failure("Equip a usable matching tool in your active hand.")


func bind_tool_capability_provider(provider: Callable) -> ServiceResult:
	if _tool_capability_provider.is_valid() or not provider.is_valid(): return _failure("Bind one trusted tool capability owner.")
	_tool_capability_provider = provider
	return ServiceResult.success()


## Shared workstation gate: server-owned logical reach and manipulator availability.
func bind_payload_mass_provider(provider: Callable) -> ServiceResult:
	return _catalog.bind_payload_mass_provider(provider)


func refresh_payload_loads() -> ServiceResult:
	return _owner.refresh_payload_loads()


func validate_payload_masses(masses: Dictionary, owner_record: Dictionary = {}) -> ServiceResult:
	return SharedInventoryCoordinator.from_record(_owner.to_record() if owner_record.is_empty() else owner_record, _profiles, _catalog.with_payload_masses(masses))


## Identity-scoped physical carriers. Other bodies' payloads are not observable.
func owned_resource_carriers(context: AuthenticatedCommandContext) -> ServiceResult:
	var own: ServiceResult = own_inventory_observation(context)
	if not own.is_success:
		return own
	var ids: Array = []
	for item in own.value["items"]:
		var definition: ServiceResult = _catalog.get_definition(item["definition_id"], int(item["definition_revision"]))
		if definition.is_success and definition.value["tags"].has("resource.carrier"):
			ids.append(item["item_id"])
	return ServiceResult.success(ids)


func production_capability(context: AuthenticatedCommandContext, voluntary: bool = true, target_position: Array = [0, 0, 0]) -> ServiceResult:
	var authorized: ServiceResult = authorize(context, voluntary)
	if not authorized.is_success:
		return authorized
	if not target_position.is_empty() and (not InventorySpatialMath.is_position(target_position) or InventorySpatialMath.distance_millimetres(_bodies[authorized.value]["position_millimetres"], target_position) > WORLD_REACH_MILLIMETRES):
		return _failure("Move within reach of the production workstation.")
	if voluntary and not _has_unreserved_hand(authorized.value):
		return _failure("Production controls require an available unreserved hand.")
	return authorized


## Prepare a trusted physical plate factory/recycler transaction without committing.
func prepare_plate_change(context: AuthenticatedCommandContext, request_id: String, item_id: String, create: bool, masses: Dictionary) -> ServiceResult:
	return prepare_equipment_change(context, request_id, item_id, create, masses, "item.plate.prototype")


func factory_definition(id: String) -> ServiceResult:
	return _catalog.get_definition(id, 1)


## Trusted owner chooses the catalog definition; client output records are never accepted.
func prepare_equipment_change(context: AuthenticatedCommandContext, request_id: String, item_id: String, create: bool, masses: Dictionary, definition_id: String, owner_record: Dictionary = {}) -> ServiceResult:
	var authorized: ServiceResult = authorize(context, true)
	if not authorized.is_success or not ControlContractValidation.is_id(item_id):
		return _failure("A capable bound actor and stable component identity are required.")
	var candidate: Dictionary = _owner.to_record() if owner_record.is_empty() else owner_record.duplicate(true)
	if int(candidate["state_revision"]) >= MAX_EXACT_INTEGER or int(candidate["ledger"]["state_revision"]) >= MAX_EXACT_INTEGER:
		return _failure("Inventory revisions are exhausted.")
	var body_index: int = -1
	for index in range(candidate["bodies"].size()):
		if candidate["bodies"][index]["body_id"] == authorized.value:
			body_index = index
	if body_index < 0:
		return _failure("The actor's inventory body is missing.")
	var body: Dictionary = candidate["bodies"][body_index]
	var found: int = -1
	for index in range(candidate["ledger"]["items"].size()):
		if candidate["ledger"]["items"][index]["item_id"] == item_id:
			found = index
	if create:
		if found >= 0:
			return _failure("That physical component already exists.")
		var definition: ServiceResult = factory_definition(definition_id)
		if not definition.is_success or definition.value["storage"] != null:
			return _failure("The factory requires a registered non-container inventory definition.")
		candidate["ledger"]["items"].append({"item_id": item_id, "definition_id": definition_id, "definition_revision": 1, "condition_permille": 1000, "container_id": body["body_container_id"]})
	else:
		if found < 0:
			return _failure("The recyclable component no longer exists.")
		var item: Dictionary = candidate["ledger"]["items"][found]
		var ledger: InventoryLedger = InventoryLedger.from_record(candidate["ledger"], _catalog).value
		if item["definition_id"] != definition_id or int(item["definition_revision"]) != 1 or ledger.root_for_container(item["container_id"]).value != body["body_container_id"]:
			return _failure("Only owned equipment with the matching trusted definition can be salvaged.")
		candidate["ledger"]["items"].remove_at(found)
		var bindings: Array = []
		for binding in body["equipped"]:
			if binding["item_id"] != item_id:
				bindings.append(binding)
		body["equipped"] = bindings
	if int(body["state_revision"]) >= MAX_EXACT_INTEGER:
		return _failure("The body revision is exhausted.")
	body["state_revision"] += 1
	candidate["ledger"]["state_revision"] += 1
	candidate["state_revision"] += 1
	var fingerprint: String = JSON.stringify(["equipment", definition_id, item_id, create, authorized.value]).sha256_text()
	candidate["receipts"].append({"request_id": request_id, "fingerprint": fingerprint, "state_revision": candidate["state_revision"]})
	if candidate["receipts"].size() > SharedInventoryCoordinator.MAX_RECEIPTS:
		candidate["receipts"].pop_front()
	var validated: ServiceResult = validate_payload_masses(masses, candidate)
	return ServiceResult.success(candidate) if validated.is_success else validated


func commit_prepared_owner(record: Dictionary) -> ServiceResult:
	var validated: ServiceResult = SharedInventoryCoordinator.from_record(record, _profiles, _catalog)
	if validated.is_success:
		_owner = validated.value
	return validated


func apply_local(context: AuthenticatedCommandContext, request_id: String, operation: String, payload: Dictionary, tick: int) -> ServiceResult:
	var authorized: ServiceResult = authorize(context, true)
	if not authorized.is_success or tick != _last_tick + 1:
		return _failure("Apply authorized inventory commands at the next fixed-tick boundary.")
	var actor_id: String = authorized.value
	var actor: Dictionary = _bodies[actor_id]
	if operation in ["grip_join", "grip_release", "grip_resume"]:
		return _apply_grip(actor_id, request_id, operation, payload)
	if operation == "world":
		if not _has_unreserved_hand(actor_id):
			return _failure("Release a grip before manipulating world inventory.")
		var fields := PackedStringArray(["operation", "item_id", "world_container_id", "destination_container_id", "slot_id", "expected_revision"])
		if not ControlContractValidation.has_exact_fields(payload, fields) or not _world_storage.has(payload.get("world_container_id")):
			return _failure("World interaction requires an exact intent and registered world storage.")
		var storage: Dictionary = _world_storage[payload["world_container_id"]]
		if not storage["accessible"] or InventorySpatialMath.distance_millimetres(actor["position_millimetres"], storage["position_millimetres"]) > WORLD_REACH_MILLIMETRES:
			return _failure("The logical body cannot reach or access this world container.")
		var request: Dictionary = payload.duplicate(true)
		request["request_id"] = request_id
		request["body_id"] = actor_id
		if payload["operation"] == "pickup" and _grip_slot_reserved(actor_id, payload["slot_id"]):
			return _failure("Release the grip before picking an item into this hand.")
		return _owner.apply_world(request)
	if operation == "self":
		var fields := PackedStringArray(["operation", "item_id", "source_container_id", "destination_container_id", "slot_id", "expected_revision"])
		if not ControlContractValidation.has_exact_fields(payload, fields):
			return _failure("Self-inventory commands require exact action fields.")
		if payload["operation"] not in ["switch_hand", "select_hand"] and not _has_unreserved_hand(actor_id):
			return _failure("Release a grip before manipulating inventory equipment or storage.")
		var request: Dictionary = payload.duplicate(true)
		request["request_id"] = request_id
		request["body_id"] = actor_id
		if payload["operation"] == "equip" and _grip_slot_reserved(actor_id, payload["slot_id"]):
			return _failure("Release the grip before equipping this hand.")
		return _owner.apply_self(request)
	if operation == "close_search":
		if not ControlContractValidation.has_exact_fields(payload, PackedStringArray(["view_id"])) or not ControlContractValidation.is_id(payload["view_id"]):
			return _failure("Closing a search requires its scoped view ID.")
		return _views.close(payload["view_id"], String(context.principal_id))
	if operation == "resist":
		if not payload.is_empty() or int(actor["action_epoch"]) >= MAX_EXACT_INTEGER:
			return _failure("Resistance requires empty intent and an available action epoch.")
		actor["action_epoch"] = int(actor["action_epoch"]) + 1
		actor["resisted_tick"] = tick
		_views.revoke_principal(String(context.principal_id))
		return ServiceResult.success()
	if operation in ["move", "move_to"]:
		if int(actor["action_epoch"]) >= MAX_EXACT_INTEGER:
			return _failure("The body's action epoch is exhausted.")
		if operation == "move":
			if not ControlContractValidation.has_exact_fields(payload, PackedStringArray(["x_millimetres"])) or not ControlContractValidation.is_integer(payload.get("x_millimetres"), -10000000, 10000000):
				return _failure("Legacy fixture movement requires a bounded integer x coordinate.")
			actor["position_millimetres"][0] = int(payload["x_millimetres"])
		else:
			if not ControlContractValidation.has_exact_fields(payload, PackedStringArray(["position_millimetres"])) or not InventorySpatialMath.is_position(payload.get("position_millimetres")):
				return _failure("Fixture movement requires a bounded integer 3D position.")
			actor["position_millimetres"] = InventorySpatialMath.normalized(payload["position_millimetres"])
		actor["action_epoch"] = int(actor["action_epoch"]) + 1
		_views.revoke_principal(String(context.principal_id))
		return ServiceResult.success()
	if operation in ["cancel", "resume"]:
		if not ControlContractValidation.has_exact_fields(payload, PackedStringArray(["job_id"])) or not _jobs.has(payload["job_id"]) or _jobs[payload["job_id"]]["principal_id"] != String(context.principal_id):
			return _failure("Only the initiating principal may cancel or resume this job.")
		var entry: Dictionary = _jobs[payload["job_id"]]
		var job: BodyInventoryInteractionJob = entry["job"]
		if operation == "cancel":
			_jobs.erase(payload["job_id"])
			return ServiceResult.success()
		return job.resume(tick, _context(job.to_record()), _observation(job.to_record(), tick))
	if operation != "start":
		return _failure("The inventory operation is not registered.")
	var fields := PackedStringArray(["action", "target_body_id", "target_container_id", "item_id", "slot_id", "destination_container_id", "expected_revision"])
	if not ControlContractValidation.has_exact_fields(payload, fields) or not ControlContractValidation.is_id(request_id) or _jobs.has(request_id) or _jobs.size() >= MAX_JOBS:
		return _failure("A complete bounded interaction intent and fresh request ID are required.")
	for receipt in _owner.to_record()["receipts"]:
		if receipt["request_id"] == request_id:
			return _failure("This interaction request already has a retained completion receipt.")
	if typeof(payload["action"]) != TYPE_STRING or not BodyInventoryInteractionPolicy.ACTIONS.has(payload["action"]) or not ControlContractValidation.is_id(payload["target_body_id"]) or not ControlContractValidation.is_id(payload["target_container_id"]):
		return _failure("Registered actions and stable target identities are required.")
	for field in ["item_id", "slot_id", "destination_container_id"]:
		if typeof(payload[field]) != TYPE_STRING or (payload[field] != "" and not ControlContractValidation.is_id(payload[field])):
			return _failure("Optional item, slot and destination identities must be bounded strings.")
	for entry in _jobs.values():
		if entry["job"].to_record()["actor_body_id"] == actor_id:
			return _failure("This actor already has an active or paused inventory job.")
	if not _bodies.has(payload["target_body_id"]) or payload["target_body_id"] == actor_id or not ControlContractValidation.is_integer(payload["expected_revision"], 0, MAX_EXACT_INTEGER) or int(payload["expected_revision"]) != int(_owner.to_record()["state_revision"]):
		return _failure("A distinct registered target and current inventory revision are required.")
	var projection: ServiceResult = _owner.direct_container_observation(actor_id, payload["target_body_id"], payload["target_container_id"])
	if not projection.is_success:
		return projection
	var rules: Dictionary = _policy.to_record()
	var job_record := {"schema_version": 1, "job_id": request_id, "actor_body_id": actor_id, "target_body_id": payload["target_body_id"],
		"policy_id": rules["definition_id"], "policy_revision": rules["revision"], "action": payload["action"],
		"target_container_id": payload["target_container_id"], "item_id": payload["item_id"], "slot_id": payload["slot_id"],
		"last_tick": tick, "progress_ticks": 0, "state": "active", "cancellation_code": ""}
	job_record.merge(_context(job_record))
	var started: ServiceResult = BodyInventoryInteractionJob.start(job_record, _policy, _observation(job_record, tick))
	if not started.is_success:
		return started
	var request: Variant = null
	if payload["action"] == "search":
		if payload["destination_container_id"] != "":
			return _failure("Search intent has no transfer destination.")
	else:
		var source: String = payload["target_container_id"]
		if payload["action"] in ["insert", "equip"]:
			var observed_item: ServiceResult = _item(payload["item_id"])
			if not observed_item.is_success:
				return observed_item
			source = observed_item.value["container_id"]
		request = {"request_id": request_id, "action": payload["action"], "actor_body_id": actor_id, "target_body_id": payload["target_body_id"], "item_id": payload["item_id"],
			"source_container_id": source, "destination_container_id": payload["target_container_id"] if payload["action"] in ["insert", "equip"] else payload["destination_container_id"],
			"slot_id": payload["slot_id"], "expected_revision": int(payload["expected_revision"])}
		var checked: ServiceResult = SharedInventoryCoordinator._validate_request(request)
		if not checked.is_success:
			return checked
	_jobs[request_id] = {"job": started.value, "principal_id": String(context.principal_id), "request": request}
	return ServiceResult.success({"job_id": request_id})


func simulate_tick(tick: int, _fixed_delta: float) -> void:
	_last_tick = tick
	_release_lost_grip_contacts(tick)
	for body in _bodies.values():
		if not _body_can_act(body["body_id"]):
			_views.revoke_principal(body["principal_id"])
	_views.advance_tick(tick)
	for id in _jobs.keys():
		var entry: Dictionary = _jobs[id]
		var job: BodyInventoryInteractionJob = entry["job"]
		var state: Dictionary = job.to_record()
		if not _body_can_act(state["actor_body_id"]):
			_finish(id, _failure("The initiating body became incapable of voluntary action."))
			continue
		if state["state"] == "paused" or int(state["last_tick"]) == tick:
			continue
		var context: Dictionary = _context(state)
		var observation: Dictionary = _observation(state, tick)
		var advanced: ServiceResult = job.advance(tick, context, observation)
		if not advanced.is_success:
			_finish(id, advanced)
		elif job.to_record()["state"] == "ready":
			if state["action"] == "equip" and _grip_slot_reserved(state["target_body_id"], state["slot_id"]):
				_finish(id, _failure("The destination hand is reserved by a physical grip."))
				continue
			var result: ServiceResult = _views.grant(job, tick, _owner, entry["principal_id"], context, observation) if state["action"] == "search" else _owner.complete_job(job, tick, context, observation, entry["request"])
			_finish(id, result)


func read_search(context: AuthenticatedCommandContext, view_id: String) -> ServiceResult:
	var authorized: ServiceResult = authorize(context, true)
	if not authorized.is_success:
		return authorized
	var scoped: ServiceResult = _views.targets_for_principal(view_id, String(context.principal_id))
	if not scoped.is_success or scoped.value["actor_body_id"] != authorized.value:
		return _failure("The search view is not bound to this actor.")
	return _views.read(view_id, _last_tick, _owner, String(context.principal_id), _context(scoped.value), _observation(scoped.value, _last_tick))


func profiling_counters() -> Dictionary:
	var counters := {"jobs": _jobs.size(), "bodies": _bodies.size(), "search_views": _views.diagnostics()["active_views"]}
	var grip_counters: Dictionary = _grips.profiling_counters()
	for key in grip_counters:
		counters["grip_" + key] = grip_counters[key]
	return counters


func local_observation(context: AuthenticatedCommandContext) -> ServiceResult:
	var authorized: ServiceResult = authorize(context)
	if not authorized.is_success:
		return authorized
	var outcomes: Array = []
	for outcome in _outcomes:
		if outcome["principal_id"] == String(context.principal_id):
			outcomes.append(outcome.duplicate(true))
	var jobs: Array = []
	for entry in _jobs.values():
		if entry["principal_id"] == String(context.principal_id):
			var state: Dictionary = entry["job"].to_record()
			jobs.append({"job_id": state["job_id"], "action": state["action"], "state": state["state"], "progress_ticks": int(state["progress_ticks"]), "duration_ticks": int(_policy.to_record()["duration_ticks"][state["action"]])})
	return ServiceResult.success({"schema_version": 1, "inventory_revision": int(_owner.to_record()["state_revision"]), "outcomes": outcomes, "jobs": jobs})


func own_inventory_observation(context: AuthenticatedCommandContext, include_details: bool = false) -> ServiceResult:
	var authorized: ServiceResult = authorize(context)
	if not authorized.is_success:
		return authorized
	var record: Dictionary = _owner.to_record()
	for body in record["bodies"]:
		if body["body_id"] != authorized.value:
			continue
		var items: Array = []
		var containers: Array = []
		var container_records: Array = []
		var item_details: Array = []
		var ledger: InventoryLedger = InventoryLedger.from_record(record["ledger"], _catalog).value
		var rules: Dictionary = _profiles[JSON.stringify([body["profile_id"], int(body["profile_revision"])])].to_record()
		var slot_ids: Array = []
		for slot in rules["slots"]:
			slot_ids.append(slot["slot_id"])
		for container in record["ledger"]["containers"]:
			if ledger.root_for_container(container["container_id"]).value == body["body_container_id"]:
				containers.append(container["container_id"])
				if include_details:
					var observed_container: Dictionary = container.duplicate(true)
					observed_container["load"] = ledger.container_load(container["container_id"]).value
					container_records.append(observed_container)
		for item in record["ledger"]["items"]:
			if containers.has(item["container_id"]):
				items.append(item.duplicate(true))
				if include_details:
					item_details.append(ledger.item_observation(item["item_id"]).value)
		var observed: Dictionary = {"schema_version": 2, "body_id": body["body_id"], "active_hand_slot_id": body["active_hand_slot_id"], "equipped": body["equipped"].duplicate(true),
			"items": items, "container_ids": containers, "body_container_id": body["body_container_id"], "hand_slot_ids": rules["hand_slot_ids"].duplicate(), "slot_ids": slot_ids,
			"mass_milligrams": ledger.container_load(body["body_container_id"]).value["mass_milligrams"]}
		if include_details:
			observed.merge({"schema_version": 3, "inventory_revision": record["state_revision"], "container_records": container_records, "item_details": item_details}, true)
		return ServiceResult.success(observed)
	return _failure("No owned fixture inventory is available.")


func world_inventory_observation(context: AuthenticatedCommandContext) -> ServiceResult:
	var authorized: ServiceResult = authorize(context)
	if not authorized.is_success:
		return authorized
	var actor: Dictionary = _bodies[authorized.value]
	var containers: Array = []
	var record: Dictionary = _owner.to_record()
	for storage in _world_storage.values():
		var distance: int = InventorySpatialMath.distance_millimetres(actor["position_millimetres"], storage["position_millimetres"])
		if not storage["accessible"] or distance > WORLD_REACH_MILLIMETRES:
			continue
		var items: Array = []
		for item in record["ledger"]["items"]:
			if item["container_id"] == storage["container_id"]:
				items.append(item.duplicate(true))
		containers.append({"container_id": storage["container_id"], "distance_millimetres": distance, "position_millimetres": storage["position_millimetres"].duplicate(), "items": items})
	return ServiceResult.success({"schema_version": 2, "inventory_revision": int(record["state_revision"]), "containers": containers})


func capture_snapshot() -> ServiceResult:
	var jobs: Array = []
	for entry in _jobs.values():
		jobs.append({"job": entry["job"].to_record(), "principal_id": entry["principal_id"], "request": entry["request"].duplicate(true) if entry["request"] != null else null})
	return ServiceResult.success({"schema_version": 4, "last_tick": _last_tick, "owner": _owner.to_record(), "bodies": _bodies.values().duplicate(true), "jobs": jobs, "world_storage": _world_storage.values().duplicate(true), "grips": _grips.to_record()})


func validate_snapshot_record(record: Dictionary, snapshot_tick_number: int) -> ServiceResult:
	return _decode(record, snapshot_tick_number)


func restore_snapshot_record(record: Dictionary, snapshot_tick_number: int) -> ServiceResult:
	var decoded: ServiceResult = _decode(record, snapshot_tick_number)
	if not decoded.is_success:
		return decoded
	_owner = decoded.value["owner"]
	_bodies = decoded.value["bodies"]
	_jobs = decoded.value["jobs"]
	_world_storage = decoded.value["world_storage"]
	_grips = decoded.value["grips"]
	_last_tick = snapshot_tick_number
	_views = InventorySearchViews.new()
	_outcomes.clear()
	return ServiceResult.success()


func legacy_empty_snapshot(tick: int) -> Dictionary:
	return {"schema_version": 3, "last_tick": tick, "owner": {"schema_version": 1, "owner_id": "inventory.shared.prototype", "state_revision": 0,
		"ledger": {"schema_version": 1, "ledger_id": "inventory.prototype", "state_revision": 0, "containers": [], "items": []}, "bodies": [], "receipts": []}, "bodies": [], "jobs": [], "world_storage": []}


func _decode(record: Dictionary, tick: int) -> ServiceResult:
	var fields := PackedStringArray(["schema_version", "last_tick", "owner", "bodies", "jobs"])
	if ControlContractValidation.is_integer(record.get("schema_version"), 2, 4):
		fields.append("world_storage")
	if ControlContractValidation.is_integer(record.get("schema_version"), 4, 4):
		fields.append("grips")
	if not ControlContractValidation.has_exact_fields(record, fields) or not ControlContractValidation.is_integer(record.get("schema_version"), 1, 4) or not ControlContractValidation.is_integer(record.get("last_tick"), tick, tick) or typeof(record.get("owner")) != TYPE_DICTIONARY or typeof(record.get("bodies")) != TYPE_ARRAY or record["bodies"].size() > 32 or typeof(record.get("jobs")) != TYPE_ARRAY or record["jobs"].size() > MAX_JOBS:
		return _failure("An exact bounded inventory-system snapshot at this tick is required.")
	var parsed_owner: ServiceResult = SharedInventoryCoordinator.from_record(record["owner"], _profiles, _catalog)
	if not parsed_owner.is_success:
		return parsed_owner
	var body_ids: Dictionary = {}
	for body in record["owner"]["bodies"]:
		body_ids[body["body_id"]] = true
	var bodies: Dictionary = {}
	var principals: Dictionary = {}
	var spatial_version: bool = int(record["schema_version"]) >= 3
	for raw in record["bodies"]:
		if typeof(raw) != TYPE_DICTIONARY:
			return _failure("Each logical body must be a record.")
		var body: Dictionary = raw
		var position_field: String = "position_millimetres" if spatial_version else "x_millimetres"
		if not ControlContractValidation.has_exact_fields(body, PackedStringArray(["body_id", "principal_id", "control_epoch", "action_epoch", position_field, "resisted_tick"])) or not ControlContractValidation.is_id(body.get("body_id")) or not ControlContractValidation.is_id(body.get("principal_id")) or not body_ids.has(body["body_id"]) or bodies.has(body["body_id"]) or principals.has(body["principal_id"]):
			return _failure("Logical bodies require unique identities bound to inventory owners.")
		for field in ["control_epoch", "action_epoch"]:
			if not ControlContractValidation.is_integer(body[field], 0, MAX_EXACT_INTEGER):
				return _failure("Body action epochs must be exact counters.")
		var position: Variant = body[position_field] if spatial_version else [body[position_field], 0, 0]
		if not InventorySpatialMath.is_position(position) or not ControlContractValidation.is_integer(body["resisted_tick"], -1, tick):
			return _failure("Logical position and resistance tick must be bounded.")
		bodies[body["body_id"]] = body.duplicate(true)
		bodies[body["body_id"]].erase("x_millimetres")
		bodies[body["body_id"]]["position_millimetres"] = InventorySpatialMath.normalized(position)
		principals[body["principal_id"]] = true
	if bodies.size() != body_ids.size():
		return _failure("Every inventory body requires logical runtime metadata.")
	var storage_records: Variant = record.get("world_storage", _legacy_world_storage(record["owner"]))
	if typeof(storage_records) != TYPE_ARRAY or storage_records.size() > 32:
		return _failure("World storage metadata must be bounded.")
	var world_storage: Dictionary = {}
	var roots: Dictionary = {}
	var body_roots: Dictionary = {}
	for container in record["owner"]["ledger"]["containers"]:
		if container["owner_item_id"] == "":
			roots[container["container_id"]] = true
	for body in record["owner"]["bodies"]:
		body_roots[body["body_container_id"]] = true
	for raw in storage_records:
		var position_field: String = "position_millimetres" if spatial_version else "x_millimetres"
		if typeof(raw) != TYPE_DICTIONARY or not ControlContractValidation.has_exact_fields(raw, PackedStringArray(["container_id", position_field, "accessible"])) or not ControlContractValidation.is_id(raw.get("container_id")) or not roots.has(raw["container_id"]) or body_roots.has(raw["container_id"]) or world_storage.has(raw["container_id"]) or typeof(raw.get("accessible")) != TYPE_BOOL:
			return _failure("World locations must be unique bounded non-body roots.")
		var position: Variant = raw[position_field] if spatial_version else [raw[position_field], 0, 0]
		if not InventorySpatialMath.is_position(position):
			return _failure("World positions must be bounded integer millimetres.")
		world_storage[raw["container_id"]] = raw.duplicate(true)
		world_storage[raw["container_id"]].erase("x_millimetres")
		world_storage[raw["container_id"]]["position_millimetres"] = InventorySpatialMath.normalized(position)
	var jobs: Dictionary = {}
	var actors: Dictionary = {}
	for raw in record["jobs"]:
		if typeof(raw) != TYPE_DICTIONARY or not ControlContractValidation.has_exact_fields(raw, PackedStringArray(["job", "principal_id", "request"])) or typeof(raw["job"]) != TYPE_DICTIONARY:
			return _failure("Each saved job requires exact wrapper fields.")
		var parsed_job: ServiceResult = BodyInventoryInteractionJob.from_record(raw["job"], _policy)
		if not parsed_job.is_success:
			return parsed_job
		var state: Dictionary = raw["job"]
		if jobs.has(state["job_id"]) or actors.has(state["actor_body_id"]) or not bodies.has(state["actor_body_id"]) or not bodies.has(state["target_body_id"]) or raw["principal_id"] != bodies[state["actor_body_id"]]["principal_id"] or int(state["last_tick"]) > tick or state["state"] in ["ready", "cancelled"]:
			return _failure("Saved jobs must be unique unfinished work bound to their actor.")
		var root_check: ServiceResult = parsed_owner.value.direct_container_observation(state["actor_body_id"], state["target_body_id"], state["target_container_id"])
		if not root_check.is_success:
			return root_check
		if int(state["actor_control_epoch"]) > int(bodies[state["actor_body_id"]]["control_epoch"]) or int(state["target_action_epoch"]) > int(bodies[state["target_body_id"]]["action_epoch"]) or int(state["actor_inventory_revision"]) > root_check.value["actor_inventory_revision"] or int(state["target_inventory_revision"]) > root_check.value["target_inventory_revision"]:
			return _failure("Saved job epochs/revisions cannot be ahead of canonical bodies.")
		if state["action"] == "search":
			if raw["request"] != null:
				return _failure("Search jobs have no transfer intent.")
		else:
			if typeof(raw["request"]) != TYPE_DICTIONARY or not SharedInventoryCoordinator._validate_request(raw["request"]).is_success:
				return _failure("Transfer jobs need a valid immutable intent.")
			for field in ["action", "actor_body_id", "target_body_id", "item_id", "slot_id"]:
				if raw["request"][field] != state[field]:
					return _failure("Saved transfer intent and job targets must agree.")
			var target_container: String = raw["request"]["source_container_id"] if state["action"] in ["take", "unequip"] else raw["request"]["destination_container_id"]
			if raw["request"]["request_id"] != state["job_id"] or target_container != state["target_container_id"]:
				return _failure("Saved transfer intent must match job identity and container.")
			if int(raw["request"]["expected_revision"]) > int(record["owner"]["state_revision"]):
				return _failure("Saved transfer revision cannot be ahead of its owner.")
		jobs[state["job_id"]] = {"job": parsed_job.value, "principal_id": raw["principal_id"], "request": raw["request"].duplicate(true) if raw["request"] != null else null}
		actors[state["actor_body_id"]] = true
	var parsed_grips: ServiceResult = PhysicalGripOwner.create("inventory.grips.prototype")
	if int(record["schema_version"]) == 4:
		if typeof(record["grips"]) != TYPE_DICTIONARY:
			return _failure("Saved grips must be a record.")
		parsed_grips = PhysicalGripOwner.from_record(record["grips"])
	if not parsed_grips.is_success:
		return parsed_grips
	if parsed_grips.value.to_record()["owner_id"] != "inventory.grips.prototype":
		return _failure("Saved grips belong to another owner.")
	for session in parsed_grips.value.to_record()["sessions"]:
		if not GRIP_TARGETS.has(session["target_id"]) or (session["action"] == "move_world_object" and not GRIP_TARGETS[session["target_id"]]["movable"]):
			return _failure("Saved grips must reference compatible registered targets.")
		for participant in session["participants"]:
			if not bodies.has(participant["body_id"]) or not _hands_unequipped(record["owner"], participant["body_id"], participant["hand_ids"]):
				return _failure("Saved grip hands must exist and be unequipped on canonical bodies.")
	return ServiceResult.success({"owner": parsed_owner.value, "bodies": bodies, "jobs": jobs, "world_storage": world_storage, "grips": parsed_grips.value})


static func _legacy_world_storage(owner: Dictionary) -> Array:
	for body in owner["bodies"]:
		if body["body_container_id"] == "world.tray-1":
			return []
	for container in owner["ledger"]["containers"]:
		if container["container_id"] == "world.tray-1" and container["owner_item_id"] == "":
			return [{"container_id": "world.tray-1", "x_millimetres": 0, "accessible": true}]
	return []


func local_grip_observation(context: AuthenticatedCommandContext) -> ServiceResult:
	var authorized: ServiceResult = authorize(context)
	if not authorized.is_success:
		return authorized
	var sessions: Array = []
	var owner_record: Dictionary = _owner.to_record()
	var grip_record: Dictionary = _grips.to_record()
	var hand_states: Array = []
	for body in owner_record["bodies"]:
		if body["body_id"] != authorized.value:
			continue
		var profile: Dictionary = _profiles[JSON.stringify([body["profile_id"], int(body["profile_revision"])])].to_record()
		for hand_id in profile["hand_slot_ids"]:
			var state: String = "reserved" if _grips.hand_is_reserved(authorized.value, hand_id) else "free"
			for binding in body["equipped"]:
				if binding["slot_id"] == hand_id:
					state = "occupied"
			hand_states.append({"hand_id": hand_id, "state": state})
	var targets: Array = []
	for id in GRIP_TARGETS:
		var session_id: String = ""
		var session_action: String = ""
		var session_paused: bool = false
		for session in grip_record["sessions"]:
			if session["target_id"] == id:
				session_id = session["session_id"]
				session_action = session["action"]
				session_paused = session["paused"]
		var actions: Array = ["grab", "pull_along"]
		if GRIP_TARGETS[id]["movable"]:
			actions.append("move_world_object")
		targets.append({"target_id": id, "reachable": InventorySpatialMath.distance_millimetres(_bodies[authorized.value]["position_millimetres"], GRIP_TARGETS[id]["position"]) <= WORLD_REACH_MILLIMETRES, "actions": actions, "session_id": session_id, "session_action": session_action, "session_paused": session_paused})
	for session in grip_record["sessions"]:
		for participant in session["participants"]:
			if participant["body_id"] == authorized.value:
				var assessed: ServiceResult = _grips.assess_session(session["session_id"], _grip_observation(session))
				sessions.append({"session_id": session["session_id"], "target_id": session["target_id"], "action": session["action"], "paused": session["paused"], "own_hand_ids": participant["hand_ids"].duplicate(), "participant_count": session["participants"].size(), "movement_available": assessed.is_success and assessed.value["allowed"]})
	return ServiceResult.success({"schema_version": 2, "grip_revision": grip_record["state_revision"], "sessions": sessions, "hands": hand_states, "targets": targets})


func _apply_grip(actor_id: String, request_id: String, operation: String, payload: Dictionary) -> ServiceResult:
	var fields := PackedStringArray(["session_id", "expected_revision"])
	if operation == "grip_join":
		fields.append_array(PackedStringArray(["target_id", "action", "hand_ids"]))
	if not ControlContractValidation.has_exact_fields(payload, fields) or not ControlContractValidation.is_id(payload.get("session_id")):
		return _failure("Grip commands require exact intent fields.")
	var request := {"request_id": request_id, "body_id": actor_id, "session_id": payload["session_id"], "expected_revision": payload["expected_revision"]}
	if operation == "grip_release":
		return _grips.release(request)
	var session: Dictionary = {}
	for existing in _grips.to_record()["sessions"]:
		if existing["session_id"] == payload["session_id"]:
			session = existing
	if operation == "grip_resume":
		if session.is_empty() or session["participants"].size() != 1:
			return _failure("Cooperative recovery requires each participant to release and explicitly rejoin.")
		return _grips.resume(request, _grip_observation(session))
	if not GRIP_TARGETS.has(payload["target_id"]) or payload["action"] not in ["grab", "pull_along", "move_world_object"] or not _hands_unequipped(_owner.to_record(), actor_id, payload["hand_ids"]):
		return _failure("A registered target and available profile hands are required.")
	if session.is_empty():
		session = {"session_id": payload["session_id"], "target_id": payload["target_id"], "action": payload["action"], "participants": []}
	elif session["target_id"] != payload["target_id"] or session["action"] != payload["action"]:
		return _failure("Join must match the existing target and action.")
	var found: bool = false
	for participant in session["participants"]:
		if participant["body_id"] == actor_id:
			participant["hand_ids"] = payload["hand_ids"].duplicate()
			found = true
	if not found:
		session["participants"].append({"body_id": actor_id, "hand_ids": payload["hand_ids"].duplicate()})
	return _grips.join(request, _grip_observation(session))


func _grip_observation(session: Dictionary) -> Dictionary:
	var target: Dictionary = GRIP_TARGETS[session["target_id"]]
	var participants: Array = []
	var owner_record: Dictionary = _owner.to_record()
	for participant in session["participants"]:
		var body_id: String = participant["body_id"]
		var reachable: bool = _bodies.has(body_id) and InventorySpatialMath.distance_millimetres(_bodies[body_id]["position_millimetres"], target["position"]) <= WORLD_REACH_MILLIMETRES
		participants.append({"body_id": body_id, "free_hand_ids": participant["hand_ids"].duplicate(), "capable": _hands_unequipped(owner_record, body_id, participant["hand_ids"]), "reachable": reachable, "contact": reachable, "force_budget_millinewtons": 200000})
	return {"schema_version": 1, "action": session["action"], "target_id": session["target_id"], "pushable": true, "grippable": true, "movable": target["movable"], "contact_force_limit_millinewtons": 500000, "required_force_millinewtons": target["required_force"], "participants": participants}


func _hands_unequipped(owner_record: Dictionary, body_id: String, hand_ids: Variant) -> bool:
	if not ControlContractValidation.decode_ids(hand_ids, 1, 8).is_success:
		return false
	for body in owner_record["bodies"]:
		if body["body_id"] != body_id:
			continue
		var profile: Dictionary = _profiles[JSON.stringify([body["profile_id"], int(body["profile_revision"])])].to_record()
		for hand_id in hand_ids:
			if not profile["hand_slot_ids"].has(hand_id):
				return false
			for binding in body["equipped"]:
				if binding["slot_id"] == hand_id:
					return false
		return true
	return false


func _grip_slot_reserved(body_id: String, slot_id: Variant) -> bool:
	return typeof(slot_id) == TYPE_STRING and _grips.hand_is_reserved(body_id, slot_id)


func _has_unreserved_hand(body_id: String) -> bool:
	for body in _owner.to_record()["bodies"]:
		if body["body_id"] == body_id:
			var profile: Dictionary = _profiles[JSON.stringify([body["profile_id"], int(body["profile_revision"])])].to_record()
			for hand_id in profile["hand_slot_ids"]:
				if not _grips.hand_is_reserved(body_id, hand_id):
					return true
	return false


func _release_lost_grip_contacts(tick: int) -> void:
	for session in _grips.to_record()["sessions"]:
		for participant in session["participants"]:
			var body_id: String = participant["body_id"]
			if not _body_can_act(body_id) or (not session["paused"] and InventorySpatialMath.distance_millimetres(_bodies[body_id]["position_millimetres"], GRIP_TARGETS[session["target_id"]]["position"]) > WORLD_REACH_MILLIMETRES):
				_grips.release({"request_id": "contact-loss-" + JSON.stringify([tick, session["session_id"], body_id]).sha256_text(), "session_id": session["session_id"], "body_id": body_id, "expected_revision": _grips.to_record()["state_revision"]})


func _context(state: Dictionary) -> Dictionary:
	var revisions: Dictionary = {}
	for body in _owner.to_record()["bodies"]:
		revisions[body["body_id"]] = int(body["state_revision"])
	return {"actor_control_epoch": int(_bodies[state["actor_body_id"]]["control_epoch"]), "target_action_epoch": int(_bodies[state["target_body_id"]]["action_epoch"]),
		"actor_inventory_revision": revisions[state["actor_body_id"]], "target_inventory_revision": revisions[state["target_body_id"]]}


func _observation(state: Dictionary, tick: int) -> Dictionary:
	var actor: Dictionary = _bodies[state["actor_body_id"]]
	var target: Dictionary = _bodies[state["target_body_id"]]
	return {"distance_millimetres": InventorySpatialMath.distance_millimetres(actor["position_millimetres"], target["position_millimetres"]), "actor_can_manipulate": _body_can_act(state["actor_body_id"]) and _has_unreserved_hand(state["actor_body_id"]), "target_available": true,
		"target_resisting": _body_can_act(state["target_body_id"]) and int(target["resisted_tick"]) == tick, "target_moved": false, "path_accessible": true}


func _body_can_act(body_id: String) -> bool:
	return is_instance_valid(_health) and _health.consciousness_allows_actions(body_id)


func _item(id: String) -> ServiceResult:
	for item in _owner.to_record()["ledger"]["items"]:
		if item["item_id"] == id:
			return ServiceResult.success(item)
	return _failure("The selected item does not exist.")


func _finish(id: String, result: ServiceResult) -> void:
	# Never retain item lists outside the scoped read path; they could become stale.
	var view_id: String = String(result.value.get("view_id", "")) if result.is_success and typeof(result.value) == TYPE_DICTIONARY else ""
	_outcomes.append({"job_id": id, "principal_id": _jobs[id]["principal_id"], "success": result.is_success, "error_code": String(result.error_code), "view_id": view_id})
	if _outcomes.size() > 16:
		_outcomes.pop_front()
	_jobs.erase(id)


static func _body(id: String, principal: String, x: int) -> Dictionary:
	return {"body_id": id, "principal_id": principal, "control_epoch": 0, "action_epoch": 0, "position_millimetres": [x, 0, 0], "resisted_tick": -1}


static func _failure(message: String) -> ServiceResult:
	return ServiceResult.failure(&"inventory_development_rejected", message)
