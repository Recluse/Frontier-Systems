extends RefCounted
class_name TerrainMaterialOwner

## Finite terrain and loose-transfer owner, called synchronously at a tick boundary.
## No world registration, inventory bridge, I/O, procedural regeneration or geometry.
const MAX_INTEGER: int = TerrainMaterialState.MAX_EXACT_INTEGER
const MAX_CELLS: int = 128
const MAX_ORIGINS: int = 128
const MAX_TRANSFERS: int = 256
const MAX_PARCELS: int = 16
const MAX_RECEIPTS: int = 64
var _catalog: MaterialCatalog
var _record: Dictionary = {}
var _commits: int = 0
var _retries: int = 0
var _rejections: int = 0


## Trusted commissioning only. Recovery must use from_record, never reseed cells.
## Each seed supplies state, capacity_milligrams, origin_id and generation_revision.
static func create(owner_id: String, catalog: MaterialCatalog, seeds: Array) -> ServiceResult:
	if not ControlContractValidation.is_id(owner_id) or catalog == null or seeds.is_empty() or seeds.size() > MAX_CELLS:
		return _failure("Commission a bounded owner with a trusted catalog and stable ID.")
	var record := {"schema_version": 1, "owner_id": owner_id, "last_sequence": 0,
		"origins": {}, "cells": {}, "transfers": {}, "receipts": []}
	for seed in seeds:
		if not _exact(seed, ["state", "capacity_milligrams", "origin_id", "generation_revision"]) or typeof(seed["state"]) != TYPE_DICTIONARY or not ControlContractValidation.is_id(seed["origin_id"]) or not ControlContractValidation.is_integer(seed["generation_revision"], 1, MAX_INTEGER):
			return _failure("Invalid commissioned seed or generation provenance.")
		var parsed: ServiceResult = TerrainMaterialState.from_record(seed["state"], catalog)
		if not parsed.is_success:
			return parsed
		var state: Dictionary = parsed.value.to_record()
		if state["state_revision"] != 0 or record["cells"].has(state["cell_id"]) or not ControlContractValidation.is_integer(seed["capacity_milligrams"], state["mass_milligrams"], MAX_INTEGER):
			return _failure("Seeds require unique revision-zero cells and finite capacity.")
		var origin_id: String = seed["origin_id"]
		if record["origins"].has(origin_id):
			return _failure("Each seed requires its own stable generation origin.")
		record["origins"][origin_id] = {"material_id": state["material_id"], "material_revision": state["material_revision"],
			"generation_revision": int(seed["generation_revision"]), "initial_mass_milligrams": state["mass_milligrams"]}
		var parcels: Dictionary = {}
		if state["mass_milligrams"] > 0:
			parcels[origin_id] = state["mass_milligrams"]
		record["cells"][state["cell_id"]] = {"state": state, "capacity_milligrams": int(seed["capacity_milligrams"]), "parcels": parcels}
	return from_record(record, catalog)


func to_record() -> Dictionary:
	return _record.duplicate(true)


## Pure detached preview. Commit accepts the intent again and recomputes this plan.
func plan(request: Dictionary) -> ServiceResult:
	return _prepare(request)


func commit(request: Dictionary) -> ServiceResult:
	var prepared: ServiceResult = _prepare(request)
	if not prepared.is_success:
		_rejections = mini(_rejections + 1, MAX_INTEGER)
		return prepared
	var result: Dictionary = prepared.value
	if result["retry"]:
		_retries = mini(_retries + 1, MAX_INTEGER)
	else:
		_record = result["after"]
		_commits = mini(_commits + 1, MAX_INTEGER)
	return ServiceResult.success(result["receipt"].duplicate(true))


func profiling_signals() -> Dictionary:
	return {"commits": _commits, "retries": _retries, "rejections": _rejections,
		"cells": _record.get("cells", {}).size(), "transfers": _record.get("transfers", {}).size(),
		"retained_receipts": _record.get("receipts", []).size(), "last_sequence": _record.get("last_sequence", 0)}


func _prepare(request: Dictionary) -> ServiceResult:
	var decoded: ServiceResult = _decode_request(request)
	if not decoded.is_success or _record.is_empty():
		return decoded if not decoded.is_success else _failure("Owner has not been commissioned.")
	var command: Dictionary = decoded.value
	var sequence: int = command["sequence"]
	var last: int = _record["last_sequence"]
	if sequence <= last:
		for receipt in _record["receipts"]:
			if int(receipt["command"]["sequence"]) == sequence:
				if receipt["command"] != command:
					return _failure("Retained sequence identifies different intent.")
				return ServiceResult.success({"retry": true, "receipt": receipt.duplicate(true), "after": to_record()})
		return _failure("Expired sequences reject; they never become new operations.")
	if last >= MAX_INTEGER or sequence != last + 1 or not _record["cells"].has(command["cell_id"]):
		return _failure("New commands require the next owner sequence and an existing cell.")
	var cell: Dictionary = _record["cells"][command["cell_id"]]
	var state: Dictionary = cell["state"]
	if command["expected_cell_revision"] != state["state_revision"]:
		return _failure("Cell revision is stale.")
	var amount: int = command["amount_milligrams"]
	var parsed: ServiceResult = TerrainMaterialState.from_record(state, _catalog)
	if not parsed.is_success:
		return parsed
	var terrain: TerrainMaterialState = parsed.value
	var material_plan: ServiceResult
	var transfer_id: String = command["transfer_id"]
	var moved: Dictionary
	var candidate: Dictionary = to_record()
	var next_cell: Dictionary = candidate["cells"][command["cell_id"]]
	if command["operation"] == "excavate":
		transfer_id = "terrain-transfer-%d" % sequence
		if candidate["transfers"].size() >= MAX_TRANSFERS or candidate["transfers"].has(transfer_id):
			return _failure("Loose transfer capacity is exhausted.")
		material_plan = terrain.plan_excavation(amount)
		if not material_plan.is_success:
			return material_plan
		var split: Dictionary = _split(cell["parcels"], amount)
		moved = split["moved"]
		next_cell["parcels"] = split["remaining"]
		candidate["transfers"][transfer_id] = {"material_id": state["material_id"],
			"material_revision": state["material_revision"], "mass_milligrams": amount, "parcels": moved.duplicate(true)}
	else:
		if not candidate["transfers"].has(transfer_id):
			return _failure("Fill must consume an existing owner-held transfer.")
		var transfer: Dictionary = candidate["transfers"][transfer_id]
		if amount > int(transfer["mass_milligrams"]) or amount > int(cell["capacity_milligrams"]) - int(state["mass_milligrams"]):
			return _failure("Fill overdraws loose matter or exceeds commissioned cell capacity.")
		material_plan = terrain.plan_fill(transfer["material_id"], int(transfer["material_revision"]), amount)
		if not material_plan.is_success:
			return material_plan
		var split: Dictionary = _split(transfer["parcels"], amount)
		moved = split["moved"]
		next_cell["parcels"] = _merge(cell["parcels"], moved)
		if next_cell["parcels"].size() > MAX_PARCELS:
			return _failure("Fill exceeds the cell's provenance budget.")
		transfer["mass_milligrams"] = int(transfer["mass_milligrams"]) - amount
		transfer["parcels"] = split["remaining"]
		if transfer["mass_milligrams"] == 0:
			candidate["transfers"].erase(transfer_id)
	next_cell["state"] = material_plan.value["after"].duplicate(true)
	candidate["last_sequence"] = sequence
	var receipt := {"command": command, "transfer_id": transfer_id,
		"terrain_plan": material_plan.value, "parcels": moved}
	candidate["receipts"].append(receipt.duplicate(true))
	if candidate["receipts"].size() > MAX_RECEIPTS:
		candidate["receipts"].pop_front()
	return ServiceResult.success({"retry": false, "receipt": receipt.duplicate(true), "after": candidate})


## Validates conservation, pinned identities, limits and the entire retained tail.
## Rewind and replay the tail against canonical state to reject contradictory receipts.
static func from_record(record: Dictionary, catalog: MaterialCatalog) -> ServiceResult:
	var validated: ServiceResult = _validate_core(record, catalog)
	if not validated.is_success:
		return validated
	var normalized: Dictionary = validated.value
	var receipts: Array = []
	for raw in normalized["receipts"]:
		var decoded: ServiceResult = _decode_receipt(raw, catalog, normalized["origins"])
		if not decoded.is_success:
			return decoded
		receipts.append(decoded.value)
	normalized["receipts"] = receipts
	var last: int = normalized["last_sequence"]
	if receipts.size() != mini(last, MAX_RECEIPTS):
		return _failure("The complete bounded receipt tail must be retained.")
	var rewind: Dictionary = normalized.duplicate(true)
	for index in range(receipts.size() - 1, -1, -1):
		var raw: Variant = receipts[index]
		if not _exact(raw, ["command", "transfer_id", "terrain_plan", "parcels"]) or typeof(raw["command"]) != TYPE_DICTIONARY or typeof(raw["terrain_plan"]) != TYPE_DICTIONARY or typeof(raw["parcels"]) != TYPE_DICTIONARY or not ControlContractValidation.is_id(raw["transfer_id"]):
			return _failure("Invalid retained receipt shape.")
		var decoded: ServiceResult = _decode_request(raw["command"])
		if not decoded.is_success:
			return decoded
		var command: Dictionary = decoded.value
		var sequence: int = last - receipts.size() + index + 1
		if command["sequence"] != sequence or not rewind["cells"].has(command["cell_id"]):
			return _failure("Receipts must be a contiguous ordered sequence for existing cells.")
		var cell: Dictionary = rewind["cells"][command["cell_id"]]
		var plan: Dictionary = raw["terrain_plan"]
		if typeof(plan.get("before")) != TYPE_DICTIONARY or typeof(plan.get("after")) != TYPE_DICTIONARY or cell["state"] != plan["after"]:
			return _failure("Receipt after state contradicts canonical terrain.")
		var prior: ServiceResult = TerrainMaterialState.from_record(plan["before"], catalog)
		if not prior.is_success or plan["before"]["cell_id"] != command["cell_id"] or int(plan["before"]["state_revision"]) != command["expected_cell_revision"]:
			return _failure("Receipt before state contradicts intent.")
		var replanned: ServiceResult
		if command["operation"] == "excavate":
			replanned = prior.value.plan_excavation(command["amount_milligrams"])
		else:
			replanned = prior.value.plan_fill(cell["state"]["material_id"], int(cell["state"]["material_revision"]), command["amount_milligrams"])
		if not replanned.is_success or replanned.value != plan:
			return _failure("Receipt must contain the exact trusted pure terrain plan.")
		var parcel_check: ServiceResult = _validate_parcels(raw["parcels"], command["amount_milligrams"], plan["material_id"], int(plan["material_revision"]), normalized["origins"])
		if not parcel_check.is_success:
			return parcel_check
		var moved: Dictionary = parcel_check.value
		var transfer_id: String = raw["transfer_id"]
		if command["operation"] == "excavate":
			if transfer_id != "terrain-transfer-%d" % sequence or not rewind["transfers"].has(transfer_id):
				return _failure("Excavation receipt requires its unique generated transfer.")
			var transfer: Dictionary = rewind["transfers"][transfer_id]
			if transfer != {"material_id": plan["material_id"], "material_revision": plan["material_revision"],
				"mass_milligrams": command["amount_milligrams"], "parcels": moved}:
				return _failure("Excavation receipt contradicts loose transfer matter.")
			rewind["transfers"].erase(transfer_id)
			cell["parcels"] = _merge(cell["parcels"], moved)
		else:
			if transfer_id != command["transfer_id"]:
				return _failure("Fill receipt must identify the consumed transfer.")
			var subtracted: ServiceResult = _subtract(cell["parcels"], moved)
			if not subtracted.is_success:
				return subtracted
			cell["parcels"] = subtracted.value
			if not rewind["transfers"].has(transfer_id):
				rewind["transfers"][transfer_id] = {"material_id": plan["material_id"], "material_revision": plan["material_revision"], "mass_milligrams": 0, "parcels": {}}
			var transfer: Dictionary = rewind["transfers"][transfer_id]
			if transfer["material_id"] != plan["material_id"] or transfer["material_revision"] != plan["material_revision"] or int(transfer["mass_milligrams"]) > MAX_INTEGER - int(command["amount_milligrams"]):
				return _failure("Restored fill transfer has inconsistent identity or quantity.")
			transfer["mass_milligrams"] = int(transfer["mass_milligrams"]) + int(command["amount_milligrams"])
			transfer["parcels"] = _merge(transfer["parcels"], moved)
		cell["state"] = prior.value.to_record()
		rewind["last_sequence"] = sequence - 1
		rewind["receipts"].pop_back()
		var core: ServiceResult = _validate_core(rewind, catalog)
		if not core.is_success:
			return core
		rewind = core.value
	var replay := TerrainMaterialOwner.new()
	replay._catalog = catalog
	replay._record = rewind
	for raw in receipts:
		var committed: ServiceResult = replay.commit(raw["command"])
		if not committed.is_success or committed.value != raw:
			return _failure("Saved receipt tail does not replay exactly.")
	if replay.to_record() != normalized:
		return _failure("Saved state differs from its replayed canonical tail.")
	var owner := TerrainMaterialOwner.new()
	owner._catalog = catalog
	owner._record = normalized
	return ServiceResult.success(owner)


static func _validate_core(record: Dictionary, catalog: MaterialCatalog) -> ServiceResult:
	if catalog == null or not _exact(record, ["schema_version", "owner_id", "last_sequence", "origins", "cells", "transfers", "receipts"]) or not ControlContractValidation.is_integer(record["schema_version"], 1, 1) or not ControlContractValidation.is_id(record["owner_id"]) or not ControlContractValidation.is_integer(record["last_sequence"], 0, MAX_INTEGER):
		return _failure("Invalid versioned terrain owner.")
	for field in ["origins", "cells", "transfers"]:
		if typeof(record[field]) != TYPE_DICTIONARY:
			return _failure("Terrain owner collections must be bounded maps.")
	if record["cells"].is_empty() or record["cells"].size() > MAX_CELLS or record["origins"].is_empty() or record["origins"].size() > MAX_ORIGINS or record["transfers"].size() > MAX_TRANSFERS or typeof(record["receipts"]) != TYPE_ARRAY or record["receipts"].size() > MAX_RECEIPTS:
		return _failure("Terrain owner collection limits exceeded.")
	var result: Dictionary = record.duplicate(true)
	result["schema_version"] = 1
	result["last_sequence"] = int(record["last_sequence"])
	var totals: Dictionary = {}
	var initial_mass: int = 0
	for id in result["origins"]:
		var origin: Variant = result["origins"][id]
		if not ControlContractValidation.is_id(id) or not _exact(origin, ["material_id", "material_revision", "generation_revision", "initial_mass_milligrams"]) or not ControlContractValidation.is_id(origin["material_id"]):
			return _failure("Invalid stable generation provenance.")
		for field in ["material_revision", "generation_revision", "initial_mass_milligrams"]:
			if not ControlContractValidation.is_integer(origin[field], 0 if field == "initial_mass_milligrams" else 1, MAX_INTEGER):
				return _failure("Generation quantities and revisions must be exact integers.")
			origin[field] = int(origin[field])
		var definition: ServiceResult = catalog.get_definition(origin["material_id"], origin["material_revision"])
		if not definition.is_success or not definition.value.uses.has("terrain.fill") or origin["initial_mass_milligrams"] > MAX_INTEGER - initial_mass:
			return _failure("Origins require trusted terrain materials and bounded total matter.")
		initial_mass += int(origin["initial_mass_milligrams"])
		totals[id] = 0
	var total_revisions: int = 0
	for id in result["cells"]:
		var cell: Variant = result["cells"][id]
		if not ControlContractValidation.is_id(id) or not _exact(cell, ["state", "capacity_milligrams", "parcels"]) or typeof(cell["state"]) != TYPE_DICTIONARY:
			return _failure("Invalid owned terrain cell.")
		var parsed: ServiceResult = TerrainMaterialState.from_record(cell["state"], catalog)
		if not parsed.is_success:
			return parsed
		var state: Dictionary = parsed.value.to_record()
		if state["cell_id"] != id or not ControlContractValidation.is_integer(cell["capacity_milligrams"], state["mass_milligrams"], MAX_INTEGER) or state["state_revision"] > result["last_sequence"]:
			return _failure("Cell identity, capacity or revision contradicts owner.")
		if int(state["state_revision"]) > MAX_INTEGER - total_revisions:
			return _failure("Cell revision totals overflow.")
		total_revisions += int(state["state_revision"])
		cell["state"] = state
		cell["capacity_milligrams"] = int(cell["capacity_milligrams"])
		var parcels: ServiceResult = _validate_parcels(cell["parcels"], state["mass_milligrams"], state["material_id"], state["material_revision"], result["origins"])
		if not parcels.is_success:
			return parcels
		cell["parcels"] = parcels.value
		if not _accumulate(totals, cell["parcels"]):
			return _failure("Origin totals overflow.")
	if total_revisions != result["last_sequence"]:
		return _failure("Successful owner sequences must exactly count cell revisions.")
	for id in result["transfers"]:
		var transfer: Variant = result["transfers"][id]
		if not ControlContractValidation.is_id(id) or not _exact(transfer, ["material_id", "material_revision", "mass_milligrams", "parcels"]) or not ControlContractValidation.is_id(transfer["material_id"]) or not ControlContractValidation.is_integer(transfer["material_revision"], 1, MAX_INTEGER) or not ControlContractValidation.is_integer(transfer["mass_milligrams"], 1, MAX_INTEGER):
			return _failure("Invalid finite loose transfer.")
		var sequence_text: String = String(id).trim_prefix("terrain-transfer-")
		if not sequence_text.is_valid_int() or int(sequence_text) < 1 or int(sequence_text) > result["last_sequence"] or id != "terrain-transfer-%d" % int(sequence_text):
			return _failure("Loose transfers must have owner-generated committed sequence IDs.")
		transfer["material_revision"] = int(transfer["material_revision"])
		transfer["mass_milligrams"] = int(transfer["mass_milligrams"])
		var parcels: ServiceResult = _validate_parcels(transfer["parcels"], transfer["mass_milligrams"], transfer["material_id"], transfer["material_revision"], result["origins"])
		if not parcels.is_success:
			return parcels
		transfer["parcels"] = parcels.value
		if not _accumulate(totals, transfer["parcels"]):
			return _failure("Origin totals overflow.")
	for id in totals:
		if totals[id] != result["origins"][id]["initial_mass_milligrams"]:
			return _failure("Cells and loose transfers must exactly partition every generation origin.")
	return ServiceResult.success(result)


static func _decode_receipt(raw: Variant, catalog: MaterialCatalog, origins: Dictionary) -> ServiceResult:
	if not _exact(raw, ["command", "transfer_id", "terrain_plan", "parcels"]) or typeof(raw["command"]) != TYPE_DICTIONARY or not ControlContractValidation.is_id(raw["transfer_id"]):
		return _failure("Invalid retained receipt shape.")
	var decoded: ServiceResult = _decode_request(raw["command"])
	if not decoded.is_success:
		return decoded
	var plan: Variant = raw["terrain_plan"]
	if not _exact(plan, ["schema_version", "operation", "expected_cell_revision", "before", "after", "inventory_direction", "material_id", "material_revision", "amount_milligrams"]) or typeof(plan["before"]) != TYPE_DICTIONARY or typeof(plan["after"]) != TYPE_DICTIONARY or not ControlContractValidation.is_id(plan["material_id"]) or not ["excavate", "fill"].has(plan["operation"]) or not ["consume", "produce"].has(plan["inventory_direction"]):
		return _failure("Invalid saved pure terrain plan shape.")
	var normalized: Dictionary = plan.duplicate(true)
	for field in ["schema_version", "expected_cell_revision", "material_revision", "amount_milligrams"]:
		if not ControlContractValidation.is_integer(plan[field], 0 if field == "expected_cell_revision" else 1, 1 if field == "schema_version" else MAX_INTEGER):
			return _failure("Saved terrain plans require exact integer quantities and revisions.")
		normalized[field] = int(plan[field])
	for field in ["before", "after"]:
		var parsed: ServiceResult = TerrainMaterialState.from_record(plan[field], catalog)
		if not parsed.is_success:
			return parsed
		normalized[field] = parsed.value.to_record()
	var parcels: ServiceResult = _validate_parcels(raw["parcels"], decoded.value["amount_milligrams"], normalized["material_id"], normalized["material_revision"], origins)
	if not parcels.is_success:
		return parcels
	return ServiceResult.success({"command": decoded.value, "transfer_id": raw["transfer_id"],
		"terrain_plan": normalized, "parcels": parcels.value})

static func _decode_request(request: Dictionary) -> ServiceResult:
	if not _exact(request, ["sequence", "request_id", "cell_id", "expected_cell_revision", "operation", "amount_milligrams", "transfer_id"]) or not ControlContractValidation.is_id(request["cell_id"]) or not ControlContractValidation.is_integer(request["sequence"], 1, MAX_INTEGER) or not ControlContractValidation.is_integer(request["expected_cell_revision"], 0, MAX_INTEGER) or not ControlContractValidation.is_integer(request["amount_milligrams"], 1, MAX_INTEGER) or not ["excavate", "fill"].has(request["operation"]):
		return _failure("An exact bounded terrain intent is required.")
	var sequence: int = int(request["sequence"])
	if request["request_id"] != "terrain-request-%d" % sequence or (request["operation"] == "excavate" and request["transfer_id"] != "") or (request["operation"] == "fill" and not ControlContractValidation.is_id(request["transfer_id"])):
		return _failure("Request IDs derive from owner sequence; excavation allocates its own transfer.")
	var normalized: Dictionary = request.duplicate(true)
	for field in ["sequence", "expected_cell_revision", "amount_milligrams"]:
		normalized[field] = int(normalized[field])
	return ServiceResult.success(normalized)


static func _validate_parcels(raw: Variant, mass: int, material_id: String, material_revision: int, origins: Dictionary) -> ServiceResult:
	if typeof(raw) != TYPE_DICTIONARY or raw.size() > MAX_PARCELS:
		return _failure("Provenance parcels exceed their bounded map contract.")
	var total: int = 0
	var normalized: Dictionary = {}
	for id in raw:
		if not origins.has(id) or not ControlContractValidation.is_integer(raw[id], 1, MAX_INTEGER):
			return _failure("Every parcel needs a known origin and positive integer mass.")
		var origin: Dictionary = origins[id]
		if origin["material_id"] != material_id or origin["material_revision"] != material_revision or int(raw[id]) > MAX_INTEGER - total:
			return _failure("Parcel material identity or total mass is inconsistent.")
		normalized[id] = int(raw[id])
		total += int(raw[id])
	if total != mass:
		return _failure("Parcels must exactly partition their container mass.")
	return ServiceResult.success(normalized)


## Deterministic origin-ID order, independent of map insertion order.
static func _split(parcels: Dictionary, amount: int) -> Dictionary:
	var moved: Dictionary = {}
	var remaining: Dictionary = parcels.duplicate(true)
	var ids: Array = parcels.keys()
	ids.sort()
	for id in ids:
		var take: int = mini(amount, int(parcels[id]))
		if take > 0:
			moved[id] = take
			remaining[id] = int(parcels[id]) - take
			if remaining[id] == 0:
				remaining.erase(id)
			amount -= take
	return {"moved": moved, "remaining": remaining}


static func _merge(first: Dictionary, second: Dictionary) -> Dictionary:
	var result: Dictionary = first.duplicate(true)
	for id in second:
		result[id] = int(result.get(id, 0)) + int(second[id])
	return result


static func _subtract(first: Dictionary, second: Dictionary) -> ServiceResult:
	var result: Dictionary = first.duplicate(true)
	for id in second:
		if int(result.get(id, 0)) < int(second[id]):
			return _failure("Receipt removes provenance absent from its cell.")
		result[id] = int(result[id]) - int(second[id])
		if result[id] == 0:
			result.erase(id)
	return ServiceResult.success(result)


static func _accumulate(totals: Dictionary, parcels: Dictionary) -> bool:
	for id in parcels:
		if int(parcels[id]) > MAX_INTEGER - int(totals[id]):
			return false
		totals[id] = int(totals[id]) + int(parcels[id])
	return true


static func _exact(raw: Variant, fields: Array) -> bool:
	return typeof(raw) == TYPE_DICTIONARY and ControlContractValidation.has_exact_fields(raw, PackedStringArray(fields))


static func _failure(message: String) -> ServiceResult:
	return ServiceResult.failure(&"invalid_terrain_owner", message)

