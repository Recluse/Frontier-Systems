extends RefCounted
class_name SharedInventoryCoordinator

## Sole domain owner for one ledger, body bindings and retained transfer receipts.
## Physical authorization and timed-job consumption must wrap transact().
const MAX_BODIES: int = 32
const MAX_RECEIPTS: int = 128
const MAX_EXACT_INTEGER: int = 9007199254740990
const REQUEST_FIELDS: Array[String] = ["request_id", "action", "actor_body_id", "target_body_id", "item_id", "source_container_id", "destination_container_id", "slot_id", "expected_revision"]
var _record: Dictionary = {}
var _catalog: InventoryItemCatalog
var _profiles: Dictionary = {}
var _ledger: InventoryLedger


## Self operations use the same owner/receipt boundary as cross-body transfers.
func apply_self(request: Dictionary) -> ServiceResult:
	var fields := PackedStringArray(["request_id", "body_id", "operation", "item_id", "source_container_id", "destination_container_id", "slot_id", "expected_revision"])
	if not ControlContractValidation.has_exact_fields(request, fields) or not ControlContractValidation.is_id(request.get("request_id")) or not ControlContractValidation.is_id(request.get("body_id")) or request.get("operation") not in ["switch_hand", "select_hand", "equip", "unequip", "move"] or not ControlContractValidation.is_integer(request.get("expected_revision"), 0, MAX_EXACT_INTEGER):
		return _failure("A complete bounded self-inventory intent is required.")
	for field in ["item_id", "source_container_id", "destination_container_id", "slot_id"]:
		if typeof(request[field]) != TYPE_STRING or (request[field] != "" and not ControlContractValidation.is_id(request[field])):
			return _failure("Self-inventory identifiers must be bounded strings.")
	var required: Array = []
	match request["operation"]:
		"select_hand": required = ["slot_id"]
		"equip": required = ["item_id", "source_container_id", "slot_id"]
		"unequip": required = ["destination_container_id", "slot_id"]
		"move": required = ["item_id", "source_container_id", "destination_container_id"]
	for field in ["item_id", "source_container_id", "destination_container_id", "slot_id"]:
		if (request[field] != "") != required.has(field):
			return _failure("Self-inventory action identifiers do not match its operation.")
	var values: Array = ["self", _record["owner_id"], request["request_id"], request["body_id"], request["operation"], request["item_id"], request["source_container_id"], request["destination_container_id"], request["slot_id"], int(request["expected_revision"])]
	var fingerprint: String = JSON.stringify(values).sha256_text()
	for receipt in _record["receipts"]:
		if receipt["request_id"] == request["request_id"]:
			return ServiceResult.success(receipt.duplicate(true)) if receipt["fingerprint"] == fingerprint else _failure("This retained request ID already identifies different intent.")
	if int(request["expected_revision"]) != int(_record["state_revision"]) or int(_record["state_revision"]) >= MAX_EXACT_INTEGER:
		return _failure("The shared inventory revision is stale or exhausted.")
	var candidate: Dictionary = to_record()
	var body_index: int = -1
	for index in range(candidate["bodies"].size()):
		if candidate["bodies"][index]["body_id"] == request["body_id"]:
			body_index = index
	if body_index < 0:
		return _failure("The selected body is not registered with this owner.")
	var body: Dictionary = candidate["bodies"][body_index]
	for field in ["source_container_id", "destination_container_id"]:
		if request[field] != "":
			var root: ServiceResult = _ledger.root_for_container(request[field])
			if not root.is_success or root.value != body["body_container_id"]:
				return _failure("Self-inventory actions cannot reach another body's containers or world storage.")
	var combined: Dictionary = body.duplicate(true)
	combined["ledger"] = candidate["ledger"]
	combined["schema_version"] = candidate["ledger"]["schema_version"]
	var key: String = JSON.stringify([body["profile_id"], int(body["profile_revision"])])
	var state: BodyInventoryState = BodyInventoryState.from_record(combined, _profiles[key], _catalog).value
	var revision: int = int(body["state_revision"])
	var result: ServiceResult
	match request["operation"]:
		"switch_hand": result = state.switch_hand(revision)
		"select_hand": result = state.select_hand(request["slot_id"], revision)
		"equip": result = state.equip_item(request["item_id"], request["source_container_id"], request["slot_id"], revision)
		"unequip": result = state.unequip_item(request["slot_id"], request["destination_container_id"], revision)
		"move": result = state.move_item(request["item_id"], request["source_container_id"], request["destination_container_id"], revision)
	if not result.is_success:
		return result
	var updated: Dictionary = state.to_record()
	candidate["ledger"] = updated["ledger"]
	updated.erase("ledger")
	updated["schema_version"] = 1
	candidate["bodies"][body_index] = updated
	return _commit_candidate(candidate, request["request_id"], fingerprint)


## Registered world storage and physical access are verified by the runtime owner.
func apply_world(request: Dictionary) -> ServiceResult:
	var fields := PackedStringArray(["request_id", "body_id", "operation", "item_id", "world_container_id", "destination_container_id", "slot_id", "expected_revision"])
	if not ControlContractValidation.has_exact_fields(request, fields) or request.get("operation") not in ["pickup", "drop"] or not ControlContractValidation.is_integer(request.get("expected_revision"), 0, MAX_EXACT_INTEGER):
		return _failure("A complete registered world-item intent is required.")
	for field in ["request_id", "body_id", "item_id", "world_container_id"]:
		if not ControlContractValidation.is_id(request[field]):
			return _failure("World interaction identifiers must be stable IDs.")
	for field in ["destination_container_id", "slot_id"]:
		if typeof(request[field]) != TYPE_STRING or (request[field] != "" and not ControlContractValidation.is_id(request[field])):
			return _failure("Optional world interaction identifiers must be bounded strings.")
	if (request["operation"] == "pickup" and request["destination_container_id"] == "") or (request["operation"] == "drop" and (request["destination_container_id"] != "" or request["slot_id"] != "")):
		return _failure("Pickup requires an owned destination; drop has no destination or slot override.")
	var fingerprint: String = JSON.stringify(["world", _record["owner_id"], request["request_id"], request["body_id"], request["operation"], request["item_id"], request["world_container_id"], request["destination_container_id"], request["slot_id"], int(request["expected_revision"])]).sha256_text()
	for receipt in _record["receipts"]:
		if receipt["request_id"] == request["request_id"]:
			return ServiceResult.success(receipt.duplicate(true)) if receipt["fingerprint"] == fingerprint else _failure("This retained ID identifies different intent.")
	if int(request["expected_revision"]) != int(_record["state_revision"]) or int(_record["state_revision"]) >= MAX_EXACT_INTEGER:
		return _failure("The shared inventory revision is stale or exhausted.")
	var world_root: ServiceResult = _ledger.root_for_container(request["world_container_id"])
	if not world_root.is_success or world_root.value != request["world_container_id"]:
		return _failure("World storage must be a physical root container.")
	var candidate: Dictionary = to_record()
	var body_index: int = -1
	for index in range(candidate["bodies"].size()):
		var body: Dictionary = candidate["bodies"][index]
		if body["body_container_id"] == request["world_container_id"]:
			return _failure("Another body's inventory cannot be treated as world storage.")
		if body["body_id"] == request["body_id"]:
			body_index = index
	if body_index < 0:
		return _failure("The acting body is not registered.")
	var actor: Dictionary = candidate["bodies"][body_index]
	if int(actor["state_revision"]) >= MAX_EXACT_INTEGER:
		return _failure("The body's inventory revision is exhausted.")
	var observed: ServiceResult = _ledger.item_observation(request["item_id"])
	if not observed.is_success:
		return observed
	var source: String = observed.value["item"]["container_id"]
	var destination: String = request["world_container_id"]
	if request["operation"] == "pickup":
		if source != request["world_container_id"]:
			return _failure("Pickup requires a direct item in the selected world container.")
		destination = request["destination_container_id"]
		var root: ServiceResult = _ledger.root_for_container(destination)
		if not root.is_success or root.value != actor["body_container_id"] or (request["slot_id"] != "" and destination != actor["body_container_id"]):
			return _failure("Pickup destination must be owned; fitted pickup must use the body root.")
		for binding in actor["equipped"]:
			if request["slot_id"] != "" and binding["slot_id"] == request["slot_id"]:
				return _failure("The receiving equipment slot is occupied.")
	else:
		var root: ServiceResult = _ledger.root_for_container(source)
		if not root.is_success or root.value != actor["body_container_id"]:
			return _failure("Only the body's owned items can be dropped.")
	var ledger: InventoryLedger = InventoryLedger.from_record(candidate["ledger"], _catalog).value
	var moved: ServiceResult = ledger.move_item(request["item_id"], source, destination, int(candidate["ledger"]["state_revision"]))
	if not moved.is_success:
		return moved
	var remaining: Array = []
	for binding in actor["equipped"]:
		if binding["item_id"] != request["item_id"]:
			remaining.append(binding)
	if request["operation"] == "pickup" and request["slot_id"] != "":
		remaining.append({"slot_id": request["slot_id"], "item_id": request["item_id"]})
	actor["equipped"] = remaining
	actor["state_revision"] = int(actor["state_revision"]) + 1
	candidate["ledger"] = ledger.to_record()
	return _commit_candidate(candidate, request["request_id"], fingerprint)


## Refresh derived load caches after a prevalidated external payload commit.
func refresh_payload_loads() -> ServiceResult:
	var validated: ServiceResult = from_record(to_record(), _profiles, _catalog)
	if validated.is_success:
		_ledger = validated.value._ledger
	return validated


func to_record() -> Dictionary:
	return _record.duplicate(true)


## Runtime resolves authenticated actor/reach. Owner restricts closure to own storage.
func set_container_open(body_id: String, request_id: String, container_id: String, is_open: bool, expected_revision: int) -> ServiceResult:
	if not ControlContractValidation.is_id(request_id): return _failure("Valid closure request ID required.")
	var fingerprint: String = JSON.stringify(["closure", _record["owner_id"], body_id, request_id, container_id, is_open, expected_revision]).sha256_text()
	for receipt in _record["receipts"]:
		if receipt["request_id"] == request_id:
			return ServiceResult.success(receipt.duplicate(true)) if receipt["fingerprint"] == fingerprint else _failure("Retained request ID conflicts.")
	if expected_revision != int(_record["state_revision"]) or expected_revision >= MAX_EXACT_INTEGER: return _failure("Closure revision stale or exhausted.")
	var root: ServiceResult = _ledger.root_for_container(container_id)
	var owned: bool = false
	for body in _record["bodies"]:
		if body["body_id"] == body_id and root.is_success and root.value == body["body_container_id"]: owned = true
	if not owned: return _failure("Closure requires storage owned by the acting body.")
	var closed: ServiceResult = _ledger.closure_candidate(container_id, is_open)
	if not closed.is_success: return closed
	var candidate: Dictionary = to_record()
	candidate["schema_version"] = 2
	candidate["ledger"] = closed.value
	return _commit_candidate(candidate, request_id, fingerprint)


func contents_access(container_id: String) -> ServiceResult:
	return _ledger.contents_access(container_id)


## Internal projection for the scoped-view owner, never a public search endpoint.
func direct_container_observation(actor_body_id: String, target_body_id: String, container_id: String) -> ServiceResult:
	var access: ServiceResult = _ledger.contents_access(container_id)
	if not access.is_success: return access
	var bodies: Dictionary = {}
	for body in _record["bodies"]:
		bodies[body["body_id"]] = body
	if actor_body_id == target_body_id or not bodies.has(actor_body_id) or not bodies.has(target_body_id):
		return _failure("A search requires distinct registered actor and target bodies.")
	var root: ServiceResult = _ledger.root_for_container(container_id)
	if not root.is_success or root.value != bodies[target_body_id]["body_container_id"]:
		return _failure("The container must physically belong to the selected target.")
	var items: Array = []
	for item in _record["ledger"]["items"]:
		if item["container_id"] != container_id:
			continue
		var definition: Dictionary = _catalog.get_definition(item["definition_id"], int(item["definition_revision"])).value
		items.append({"item_id": item["item_id"], "definition_id": item["definition_id"],
			"definition_revision": int(item["definition_revision"]), "condition_permille": int(item["condition_permille"]),
			"has_storage": definition["storage"] != null})
	return ServiceResult.success({"owner_id": _record["owner_id"], "state_revision": int(_record["state_revision"]),
		"actor_inventory_revision": int(bodies[actor_body_id]["state_revision"]),
		"target_inventory_revision": int(bodies[target_body_id]["state_revision"]), "items": items})


## Trusted completion bridge. The job owner supplies the exact saved transfer intent.
func complete_job(job: BodyInventoryInteractionJob, tick: int, context: Dictionary, observation: Dictionary, request: Dictionary) -> ServiceResult:
	var checked: ServiceResult = _validate_request(request)
	if job == null or not checked.is_success:
		return _failure("A trusted job and valid transfer intent are required.")
	var state: Dictionary = job.to_record()
	for field in ["action", "actor_body_id", "target_body_id", "item_id", "slot_id"]:
		if state[field] != request[field]:
			return _failure("The completion intent must match the timed job targets.")
	var selected_container: String = request["source_container_id"] if request["action"] in ["take", "unequip"] else request["destination_container_id"]
	if state["job_id"] != request["request_id"] or state["target_container_id"] != selected_container:
		return _failure("The completion intent must identify this job and selected target container.")
	# A retained identical completion returns its receipt without applying effects again.
	for receipt in _record["receipts"]:
		if receipt["request_id"] == request["request_id"]:
			return transact(request)
	var ready: ServiceResult = job.completion_candidate(tick, context, observation)
	if not ready.is_success:
		return ready
	var revisions: Dictionary = {}
	for body in _record["bodies"]:
		revisions[body["body_id"]] = int(body["state_revision"])
	if not revisions.has(request["actor_body_id"]) or not revisions.has(request["target_body_id"]) or revisions[request["actor_body_id"]] != int(state["actor_inventory_revision"]) or revisions[request["target_body_id"]] != int(state["target_inventory_revision"]):
		return _failure("Participating inventories changed before job completion.")
	return transact(request)


func transact(request: Dictionary) -> ServiceResult:
	var checked: ServiceResult = _validate_request(request)
	if not checked.is_success:
		return checked
	var fingerprint: String = _fingerprint(request, _record["owner_id"])
	for receipt in _record["receipts"]:
		if receipt["request_id"] == request["request_id"]:
			if receipt["fingerprint"] != fingerprint:
				return _failure("A retained request ID cannot be reused with different intent.")
			return ServiceResult.success(receipt.duplicate(true))
	if int(request["expected_revision"]) != int(_record["state_revision"]) or int(_record["state_revision"]) >= MAX_EXACT_INTEGER:
		return _failure("The shared inventory revision is stale or exhausted.")
	var candidate: Dictionary = to_record()
	var bodies: Dictionary = {}
	for body in candidate["bodies"]:
		bodies[body["body_id"]] = body
	if not bodies.has(request["actor_body_id"]) or not bodies.has(request["target_body_id"]):
		return _failure("Both bodies must be registered in this shared owner.")
	var actor: Dictionary = bodies[request["actor_body_id"]]
	var target: Dictionary = bodies[request["target_body_id"]]
	var outgoing: bool = request["action"] in ["take", "unequip"]
	var source_body: Dictionary = target if outgoing else actor
	var destination_body: Dictionary = actor if outgoing else target
	var source_root: ServiceResult = _ledger.root_for_container(request["source_container_id"])
	var destination_root: ServiceResult = _ledger.root_for_container(request["destination_container_id"])
	if not source_root.is_success or not destination_root.is_success or source_root.value != source_body["body_container_id"] or destination_root.value != destination_body["body_container_id"]:
		return _failure("Source and destination must belong to the bodies selected by the action.")
	var item_id: String = request["item_id"]
	var source_binding: Dictionary = {}
	for binding in source_body["equipped"]:
		if binding["item_id"] == item_id:
			source_binding = binding
	if request["action"] == "take" and not source_binding.is_empty():
		return _failure("Taking equipped items requires the unequip action.")
	if request["action"] == "unequip" and (source_binding.is_empty() or source_binding["slot_id"] != request["slot_id"]):
		return _failure("Unequip must identify the item's current target slot.")
	if request["action"] == "equip":
		if request["destination_container_id"] != target["body_container_id"]:
			return _failure("Equipment must be placed directly in the target body root.")
		for binding in target["equipped"]:
			if binding["slot_id"] == request["slot_id"]:
				return _failure("The target equipment slot is occupied.")
	var ledger: InventoryLedger = InventoryLedger.from_record(candidate["ledger"], _catalog).value
	var moved: ServiceResult = ledger.move_item(item_id, request["source_container_id"], request["destination_container_id"], int(candidate["ledger"]["state_revision"]))
	if not moved.is_success:
		return moved
	var remaining: Array = []
	for binding in source_body["equipped"]:
		if binding["item_id"] != item_id:
			remaining.append(binding)
	source_body["equipped"] = remaining
	if request["action"] == "equip":
		target["equipped"].append({"slot_id": request["slot_id"], "item_id": item_id})
	for body in [actor, target]:
		if int(body["state_revision"]) >= MAX_EXACT_INTEGER:
			return _failure("A participating body's revision is exhausted.")
		body["state_revision"] = int(body["state_revision"]) + 1
	candidate["ledger"] = ledger.to_record()
	return _commit_candidate(candidate, request["request_id"], fingerprint)


func _commit_candidate(candidate: Dictionary, request_id: String, fingerprint: String) -> ServiceResult:
	candidate["state_revision"] = int(candidate["state_revision"]) + 1
	var receipt := {"request_id": request_id, "fingerprint": fingerprint, "state_revision": candidate["state_revision"]}
	candidate["receipts"].append(receipt)
	if candidate["receipts"].size() > MAX_RECEIPTS:
		candidate["receipts"].pop_front()
	var validated: ServiceResult = from_record(candidate, _profiles, _catalog)
	if not validated.is_success:
		return validated
	var next: SharedInventoryCoordinator = validated.value
	_record = next._record
	_ledger = next._ledger
	return ServiceResult.success(receipt.duplicate(true))


static func from_record(record: Dictionary, profiles: Dictionary, catalog: InventoryItemCatalog) -> ServiceResult:
	if catalog == null or not ControlContractValidation.has_exact_fields(record, PackedStringArray(["schema_version", "owner_id", "state_revision", "ledger", "bodies", "receipts"])) or not ControlContractValidation.is_integer(record.get("schema_version"), 1, 2) or not ControlContractValidation.is_id(record.get("owner_id")) or not ControlContractValidation.is_integer(record.get("state_revision"), 0, MAX_EXACT_INTEGER):
		return _failure("A complete versioned shared inventory owner is required.")
	if typeof(record["ledger"]) != TYPE_DICTIONARY or typeof(record["bodies"]) != TYPE_ARRAY or record["bodies"].size() > MAX_BODIES or typeof(record["receipts"]) != TYPE_ARRAY or record["receipts"].size() > MAX_RECEIPTS:
		return _failure("Shared ledger, bodies and receipts must be bounded records.")
	var parsed: ServiceResult = InventoryLedger.from_record(record["ledger"], catalog)
	if not parsed.is_success:
		return parsed
	if int(record["schema_version"]) != int(record["ledger"].get("schema_version", 0)): return _failure("Owner and ledger versions must agree.")
	var seen_bodies: Dictionary = {}
	var seen_roots: Dictionary = {}
	var used_profiles: Dictionary = {}
	for raw in record["bodies"]:
		if typeof(raw) != TYPE_DICTIONARY:
			return _failure("Each body must be a metadata record.")
		var body: Dictionary = raw
		var fields := PackedStringArray(["schema_version", "body_id", "state_revision", "profile_id", "profile_revision", "body_container_id", "active_hand_slot_id", "equipped"])
		if not ControlContractValidation.has_exact_fields(body, fields) or not ControlContractValidation.is_id(body.get("body_id")) or not ControlContractValidation.is_id(body.get("body_container_id")) or seen_bodies.has(body["body_id"]) or seen_roots.has(body["body_container_id"]):
			return _failure("Body IDs and owned root IDs must be unique.")
		if not ControlContractValidation.is_id(body.get("profile_id")) or not ControlContractValidation.is_integer(body.get("profile_revision"), 1, MAX_EXACT_INTEGER):
			return _failure("Body profile references must be valid.")
		var key: String = JSON.stringify([body["profile_id"], int(body["profile_revision"])])
		if not profiles.has(key) or not profiles[key] is InventoryEquipmentProfile:
			return _failure("A body references an untrusted profile revision.")
		var combined: Dictionary = body.duplicate(true)
		combined["ledger"] = record["ledger"]
		combined["schema_version"] = record["ledger"]["schema_version"]
		var body_check: ServiceResult = BodyInventoryState.from_record(combined, profiles[key], catalog)
		if not body_check.is_success:
			return body_check
		seen_bodies[body["body_id"]] = true
		seen_roots[body["body_container_id"]] = true
		used_profiles[key] = InventoryEquipmentProfile.from_record(profiles[key].to_record()).value
	var ids: Dictionary = {}
	var last_receipt_revision: int = 0
	var pattern := RegEx.new()
	pattern.compile("^[0-9a-f]{64}$")
	for raw in record["receipts"]:
		if typeof(raw) != TYPE_DICTIONARY:
			return _failure("Each receipt must be a record.")
		var receipt: Dictionary = raw
		if not ControlContractValidation.has_exact_fields(receipt, PackedStringArray(["request_id", "fingerprint", "state_revision"])) or not ControlContractValidation.is_id(receipt.get("request_id")) or ids.has(receipt["request_id"]) or typeof(receipt.get("fingerprint")) != TYPE_STRING or pattern.search(receipt["fingerprint"]) == null or not ControlContractValidation.is_integer(receipt.get("state_revision"), last_receipt_revision + 1, int(record["state_revision"])):
			return _failure("Receipts must have unique IDs, fingerprints and increasing valid revisions.")
		ids[receipt["request_id"]] = true
		last_receipt_revision = int(receipt["state_revision"])
	var owner := SharedInventoryCoordinator.new()
	owner._record = record.duplicate(true)
	owner._catalog = catalog
	owner._profiles = used_profiles
	owner._ledger = parsed.value
	return ServiceResult.success(owner)


static func _validate_request(request: Dictionary) -> ServiceResult:
	if not ControlContractValidation.has_exact_fields(request, PackedStringArray(REQUEST_FIELDS)) or request.get("action") not in ["take", "insert", "equip", "unequip"]:
		return _failure("An exact registered transfer request is required.")
	for field in ["request_id", "actor_body_id", "target_body_id", "item_id", "source_container_id", "destination_container_id"]:
		if not ControlContractValidation.is_id(request[field]):
			return _failure("Transfer identifiers must be stable IDs.")
	if request["actor_body_id"] == request["target_body_id"] or not ControlContractValidation.is_integer(request["expected_revision"], 0, MAX_EXACT_INTEGER) or typeof(request["slot_id"]) != TYPE_STRING:
		return _failure("Distinct bodies, an exact revision and a slot string are required.")
	if (request["action"] in ["equip", "unequip"] and not ControlContractValidation.is_id(request["slot_id"])) or (request["action"] in ["take", "insert"] and request["slot_id"] != ""):
		return _failure("Only equipment actions require a slot ID.")
	return ServiceResult.success()


static func _fingerprint(request: Dictionary, owner_id: String) -> String:
	var values: Array = [owner_id]
	for field in REQUEST_FIELDS:
		values.append(int(request[field]) if field == "expected_revision" else request[field])
	return JSON.stringify(values).sha256_text()


static func _failure(message: String) -> ServiceResult:
	return ServiceResult.failure(&"shared_inventory_conflict", message)
