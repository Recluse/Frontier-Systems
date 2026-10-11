extends SimulationSystem
class_name TerrainSimulationSystem

## Fixed-tick bridge. Matter stays in the domain owner; claims are permissions only.
const SYSTEM_ID: StringName = &"terrain"
const OWNER_ID: String = "terrain.fixture.dirt"
const CELLS: Dictionary = {"terrain.dirt.source": [0, 0, 1000], "terrain.dirt.fill": [500, 0, 1000]}
const FIXTURE_MASS: int = 2000000
const MAX_AMOUNT: int = 1000000
const MAX_PRINCIPALS: int = 16
const MAX_COMMANDS_PER_TICK: int = 16
const MAX_INTEGER: int = TerrainMaterialOwner.MAX_INTEGER
var _catalog := MaterialCatalog.new()
var _catalog_fingerprint: String = ""
var _inventory: InventorySimulationSystem
var _tools: ToolSimulationSystem
var _owner: TerrainMaterialOwner
var _positions: Dictionary = {}
var _principals: Dictionary = {}
var _requests: Array = []
var _claims: Dictionary = {}
var _last_tick: int = 0
var _command_tick: int = -1
var _commands: int = 0
var _rejected: int = 0
var _committed: int = 0
var _retried: int = 0


func _init() -> void:
	system_id = SYSTEM_ID
	tick_priority = 350


func configure(inventory: InventorySimulationSystem, tools: ToolSimulationSystem) -> ServiceResult:
	if _inventory != null or inventory == null or tools == null: return _failure("Configure one inventory and component capability authority.")
	var material: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/materials/dirt.v1.json"))
	var loaded: ServiceResult = _catalog.register_definition(material)
	if not loaded.is_success: return loaded
	_catalog_fingerprint = JSON.stringify(material, "", true, true).sha256_text()
	_inventory = inventory
	_tools = tools
	return restore_snapshot_record(initial_record(0, true), 0)


## New-world commissioning only. Legacy recovery explicitly commissions zero budget.
func initial_record(tick: int, new_world: bool = false) -> Dictionary:
	var seeds: Array = []
	for id in CELLS:
		var mass: int = FIXTURE_MASS if new_world and id == "terrain.dirt.source" else 0
		seeds.append({"state": {"schema_version": 1, "cell_id": id, "state_revision": 0, "material_id": "material.dirt", "material_revision": 1, "mass_milligrams": mass},
			"capacity_milligrams": FIXTURE_MASS if new_world else 0, "origin_id": id + ".generation", "generation_revision": 1})
	var commissioned: ServiceResult = TerrainMaterialOwner.create(OWNER_ID, _catalog, seeds)
	return {"schema_version": 1, "catalog_fingerprint": _catalog_fingerprint, "last_tick": tick, "owner": commissioned.value.to_record(),
		"positions": CELLS.duplicate(true), "principals": {}, "requests": [], "claims": {}}


func authorize(context: AuthenticatedCommandContext) -> ServiceResult:
	var world := get_parent().get_parent() as WorldRuntime if get_parent() != null else null
	if context == null or world == null or not context.is_valid_for(world.world_id, world.region_id) or not context.has_permission("terrain.operate"):
		return _failure("Terrain requires a server-authenticated world-scoped terrain grant.")
	return _inventory.authorize(context)


func apply_intent(context: AuthenticatedCommandContext, command_id: String, number: int, operation: String, payload: Dictionary, tick: int) -> ServiceResult:
	var allowed: ServiceResult = authorize(context)
	if not allowed.is_success: return _reject(allowed)
	if tick != _last_tick + 1: return _reject(_failure("Apply terrain commands on the next fixed tick."))
	if _command_tick != tick:
		_command_tick = tick
		_commands = 0
	if _commands >= MAX_COMMANDS_PER_TICK: return _reject(_failure("Terrain tick ingress budget exhausted."))
	_commands += 1
	if not ControlContractValidation.is_id(String(context.principal_id)) or not ControlContractValidation.is_integer(number, 1, MAX_INTEGER) or command_id != "terrain-client-%d" % number or not _valid_payload(operation, payload):
		return _reject(_failure("Use an exact bounded terrain intent and stable principal request ordinal."))
	# Wire JSON carries floats. Normalize validated integers before retaining the
	# intent so it matches the domain receipt and restart decoder exactly.
	payload = payload.duplicate(true)
	for field in ["expected_cell_revision", "expected_inventory_revision", "expected_tool_revision", "amount_milligrams"]: payload[field] = int(payload[field])
	var principal: String = String(context.principal_id)
	var intent: Dictionary = {"operation": operation, "payload": payload.duplicate(true)}
	for mapping in _requests:
		if mapping["principal_id"] == principal and mapping["request_number"] == number:
			if mapping["intent"] != intent: return _reject(_failure("Retained ordinal identifies different intent."))
			var retry: ServiceResult = _owner.commit(_owner_intent(mapping["owner_sequence"], intent))
			if retry.is_success: _retried = mini(_retried + 1, MAX_INTEGER)
			return retry
	if number != int(_principals.get(principal, 0)) + 1 or (not _principals.has(principal) and _principals.size() >= MAX_PRINCIPALS):
		return _reject(_failure("Expired/skipped ordinals or full principal budget reject permanently."))
	if operation == "fill" and _claims.get(payload["transfer_id"], "") != principal: return _reject(_failure("Only the transfer claimant can consume terrain escrow."))
	var own: ServiceResult = _inventory.own_inventory_observation(context, true)
	var tool_record: Dictionary = _tools.capture_snapshot().value
	if payload["expected_inventory_revision"] != own.value["inventory_revision"] or payload["expected_tool_revision"] != tool_record["ledger"]["state_revision"]:
		return _reject(_failure("Inventory or component revision is stale."))
	var capable: ServiceResult = work_capability(context, payload["cell_id"])
	if not capable.is_success: return _reject(capable)
	
	var sequence: int = _owner.to_record()["last_sequence"] + 1
	var committed: ServiceResult = _owner.commit(_owner_intent(sequence, intent))
	if not committed.is_success: return _reject(committed)
	# No fallible action follows commit: owner, ordinal, mapping and claims settle together.
	_principals[principal] = number
	_requests.append({"principal_id": principal, "request_number": number, "owner_sequence": sequence, "intent": intent})
	if _requests.size() > TerrainMaterialOwner.MAX_RECEIPTS: _requests.pop_front()
	if operation == "excavate": _claims[committed.value["transfer_id"]] = principal
	elif not _owner.to_record()["transfers"].has(payload["transfer_id"]): _claims.erase(payload["transfer_id"])
	_committed = mini(_committed + 1, MAX_INTEGER)
	return committed


func observation(context: AuthenticatedCommandContext) -> ServiceResult:
	var allowed: ServiceResult = authorize(context)
	if not allowed.is_success: return allowed
	var record: Dictionary = _owner.to_record()
	var cells: Dictionary = {}
	for id in record["cells"]:
		var capable: ServiceResult = work_capability(context, id)
		cells[id] = {"state": record["cells"][id]["state"].duplicate(true), "position_millimetres": _positions[id].duplicate(), "capacity_milligrams": record["cells"][id]["capacity_milligrams"], "work_ready": capable.is_success, "work_message": capable.message}
	var transfers: Dictionary = {}
	for id in _claims:
		if _claims[id] == String(context.principal_id): transfers[id] = record["transfers"][id].duplicate(true)
	return ServiceResult.success({"schema_version": 1, "owner_id": OWNER_ID, "cells": cells, "transfers": transfers,
		"next_request_number": mini(int(_principals.get(String(context.principal_id), 0)) + 1, MAX_INTEGER), "request_sequence_exhausted": int(_principals.get(String(context.principal_id), 0)) >= MAX_INTEGER})


## Advisory read-only feedback uses the same canonical work gate as fresh commands.
func work_capability(context: AuthenticatedCommandContext, cell_id: String) -> ServiceResult:
	var allowed: ServiceResult = authorize(context)
	if not allowed.is_success: return allowed
	if not _positions.has(cell_id): return _failure("Unknown terrain cell.")
	var capable: ServiceResult = _inventory.production_capability(context, true, _positions[cell_id])
	if not capable.is_success: return capable
	var held: ServiceResult = _inventory.active_tool(context, "tool.shovel")
	var operational: ServiceResult = _tools.capability(held.value, "tool.shovel") if held.is_success else held
	if not held.is_success or not operational.is_success or operational.value != true: return _failure("Hold an operational component-backed shovel in the active unreserved hand.")
	var hands: ServiceResult = _inventory.local_grip_observation(context)
	if not hands.is_success: return hands
	for hand in hands.value["hands"]:
		if hand["state"] == "free": return ServiceResult.success()
	return _failure("Terrain work requires a free unreserved supporting hand.")


func simulate_tick(tick: int, _fixed_delta: float) -> void:
	_last_tick = tick


func profiling_counters() -> Dictionary:
	var signals: Dictionary = _owner.profiling_signals()
	signals["runtime_commits"] = _committed
	signals["runtime_retries"] = _retried
	signals["runtime_rejections"] = _rejected
	signals["principals"] = _principals.size()
	return signals


func capture_snapshot() -> ServiceResult:
	return ServiceResult.success({"schema_version": 1, "catalog_fingerprint": _catalog_fingerprint, "last_tick": _last_tick, "owner": _owner.to_record(),
		"positions": _positions.duplicate(true), "principals": _principals.duplicate(true), "requests": _requests.duplicate(true), "claims": _claims.duplicate(true)})


func validate_snapshot_record(record: Dictionary, tick: int) -> ServiceResult:
	if not ToolComponentCatalog.exact(record, ["schema_version", "catalog_fingerprint", "last_tick", "owner", "positions", "principals", "requests", "claims"]) or not ControlContractValidation.is_integer(record["schema_version"], 1, 1) or not ControlContractValidation.is_integer(record["last_tick"], tick, tick) or record["catalog_fingerprint"] != _catalog_fingerprint:
		return _failure("Invalid terrain system envelope, catalog or tick.")
	for field in ["owner", "positions", "principals", "claims"]:
		if typeof(record[field]) != TYPE_DICTIONARY: return _failure("Terrain collections require objects.")
	var decoded: ServiceResult = TerrainMaterialOwner.from_record(record["owner"], _catalog)
	if not decoded.is_success: return decoded
	var owner: Dictionary = decoded.value.to_record()
	if owner["owner_id"] != OWNER_ID or record["positions"] != CELLS or owner["cells"].size() != CELLS.size(): return _failure("Stable fixture positions and owner must agree.")
	var budget: int = 0
	for id in CELLS:
		if not owner["cells"].has(id) or not owner["origins"].has(id + ".generation"): return _failure("Fixture identity missing.")
		var origin: Dictionary = owner["origins"][id + ".generation"]
		var cell: Dictionary = owner["cells"][id]
		if origin["generation_revision"] != 1 or origin["material_id"] != "material.dirt" or origin["material_revision"] != 1 or cell["state"]["material_id"] != "material.dirt" or cell["state"]["material_revision"] != 1: return _failure("Fixture material/generation differs.")
		var initial: int = origin["initial_mass_milligrams"]
		if initial != 0 and (id != "terrain.dirt.source" or initial != FIXTURE_MASS): return _failure("Uncommissioned terrain source budget.")
		budget += initial
	if owner["origins"].size() != CELLS.size(): return _failure("Unexpected terrain origin.")
	for cell in owner["cells"].values():
		if cell["capacity_milligrams"] != (FIXTURE_MASS if budget == FIXTURE_MASS else 0): return _failure("Fixture capacity differs from commissioned budget.")
	if record["principals"].size() > MAX_PRINCIPALS: return _failure("Principal budget exceeded.")
	var total: int = 0
	for principal in record["principals"]:
		var count: Variant = record["principals"][principal]
		if not ControlContractValidation.is_id(principal) or not ControlContractValidation.is_integer(count, 1, owner["last_sequence"]) or int(count) > MAX_INTEGER - total: return _failure("Invalid request high-water mark.")
		total += int(count)
	if total != owner["last_sequence"]: return _failure("Principal request counts must partition successful owner sequences.")
	if typeof(record["requests"]) != TYPE_ARRAY or record["requests"].size() != owner["receipts"].size(): return _failure("Retained allocation tail must match owner receipts.")
	var seen: Dictionary = {}
	for index in range(record["requests"].size()):
		var mapping: Variant = record["requests"][index]
		if typeof(mapping) != TYPE_DICTIONARY or not ToolComponentCatalog.exact(mapping, ["principal_id", "request_number", "owner_sequence", "intent"]) or not ControlContractValidation.is_id(mapping["principal_id"]) or not record["principals"].has(mapping["principal_id"]) or typeof(mapping["intent"]) != TYPE_DICTIONARY or not ToolComponentCatalog.exact(mapping["intent"], ["operation", "payload"]) or typeof(mapping["intent"]["payload"]) != TYPE_DICTIONARY or not _valid_payload(mapping["intent"]["operation"], mapping["intent"]["payload"]): return _failure("Invalid retained allocation.")
		var principal: String = mapping["principal_id"]
		if not ControlContractValidation.is_integer(mapping["request_number"], 1, record["principals"][principal]) or (seen.has(principal) and mapping["request_number"] != seen[principal] + 1): return _failure("Principal retained ordinals must be contiguous.")
		seen[principal] = int(mapping["request_number"])
		var command: Dictionary = owner["receipts"][index]["command"]
		if not ControlContractValidation.is_integer(mapping["owner_sequence"], command["sequence"], command["sequence"]) or command != _owner_intent(int(mapping["owner_sequence"]), mapping["intent"]): return _failure("Allocation and domain receipt disagree.")
	for principal in seen:
		if seen[principal] != record["principals"][principal]: return _failure("Latest retained ordinal must match high-water mark.")
	if record["claims"].size() != owner["transfers"].size(): return _failure("Each live escrow transfer requires one claimant.")
	for id in record["claims"]:
		if not owner["transfers"].has(id) or not ControlContractValidation.is_id(record["claims"][id]) or not record["principals"].has(record["claims"][id]): return _failure("Unknown transfer claimant.")
	# Rewind claimant permissions through the complete retained domain tail.
	var claims: Dictionary = record["claims"].duplicate(true)
	for index in range(record["requests"].size() - 1, -1, -1):
		var mapping: Dictionary = record["requests"][index]
		var receipt: Dictionary = owner["receipts"][index]
		var id: String = receipt["transfer_id"]
		if claims.has(id) and claims[id] != mapping["principal_id"]: return _failure("Receipt consumed foreign transfer escrow.")
		if receipt["command"]["operation"] == "excavate":
			if not claims.has(id): return _failure("Excavation claimant missing.")
			claims.erase(id)
		else: claims[id] = mapping["principal_id"]
	return ServiceResult.success({"owner": decoded.value, "record": record.duplicate(true)})


## Checkpoint claimant identities must remain attached to registered logical bodies.
func validate_inventory_links(record: Dictionary, inventory_record: Dictionary) -> ServiceResult:
	var known: Dictionary = {}
	for body in inventory_record["bodies"]:
		if typeof(body) != TYPE_DICTIONARY or not ControlContractValidation.is_id(body.get("principal_id")): return _failure("Inventory principals must have stable identities.")
		known[body["principal_id"]] = true
	for principal in record["principals"]:
		if not known.has(principal): return _failure("Terrain claimant has no registered inventory body.")
	return ServiceResult.success()

func restore_snapshot_record(record: Dictionary, tick: int) -> ServiceResult:
	var decoded: ServiceResult = validate_snapshot_record(record, tick)
	if not decoded.is_success: return decoded
	_owner = decoded.value["owner"]
	_positions = record["positions"].duplicate(true)
	_principals = record["principals"].duplicate(true)
	_requests = record["requests"].duplicate(true)
	_claims = record["claims"].duplicate(true)
	_last_tick = tick
	_command_tick = -1
	_commands = 0
	_rejected = 0
	_committed = 0
	_retried = 0
	return ServiceResult.success()


func _valid_payload(operation: Variant, payload: Dictionary) -> bool:
	return operation in ["excavate", "fill"] and ToolComponentCatalog.exact(payload, ["cell_id", "expected_cell_revision", "amount_milligrams", "transfer_id", "expected_inventory_revision", "expected_tool_revision"]) and CELLS.has(payload["cell_id"]) and ControlContractValidation.is_integer(payload["expected_cell_revision"], 0, MAX_INTEGER) and ControlContractValidation.is_integer(payload["expected_inventory_revision"], 0, MAX_INTEGER) and ControlContractValidation.is_integer(payload["expected_tool_revision"], 0, MAX_INTEGER) and ControlContractValidation.is_integer(payload["amount_milligrams"], 1, MAX_AMOUNT) and (payload["transfer_id"] == "" if operation == "excavate" else ControlContractValidation.is_id(payload["transfer_id"]))


func _owner_intent(sequence: int, intent: Dictionary) -> Dictionary:
	var payload: Dictionary = intent["payload"]
	return {"sequence": sequence, "request_id": "terrain-request-%d" % sequence, "cell_id": payload["cell_id"], "expected_cell_revision": payload["expected_cell_revision"], "operation": intent["operation"], "amount_milligrams": payload["amount_milligrams"], "transfer_id": payload["transfer_id"]}


func _reject(result: ServiceResult) -> ServiceResult:
	_rejected = mini(_rejected + 1, MAX_INTEGER)
	return result


static func _failure(message: String) -> ServiceResult:
	return ServiceResult.failure(&"terrain_runtime_rejected", message)
