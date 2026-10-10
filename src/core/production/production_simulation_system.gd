extends SimulationSystem
class_name ProductionSimulationSystem

## Volatile local notification after an output commit; not a durable receipt.
signal batch_completed(recipe_id: String, tick_number: int)
signal extraction_cycle_completed(request_id: String, completed_cycles: int, tick_number: int)

## Sole owner of finite fixture deposits, bulk storage, vessel and reserved batches.
const SYSTEM_ID: StringName = &"production"
const MAX_MASS: int = 100000000
const VESSEL_CAPACITY: int = 2000000
const MAX_VESSEL_PRESSURE_KPA: float = 1000.0
const MAX_RECEIPTS: int = 64
const MAX_REVISION: int = 9007199254740000
const STATIONS: Array[String] = ["drill", "refinery", "chemical", "printer", "recycler", "dispenser", "construction"]
## Stable fixture sites, relative to the inventory display origin in millimetres.
const SOURCE_POSITIONS: Dictionary = {"deposit.iron": [-3000, 0, -1000], "deposit.ice": [-6000, 0, -1000], "deposit.regolith": [-9000, 0, -1000]}
var _catalog: Dictionary = {}
var _catalog_fingerprint: String = ""
var _state: Dictionary = {}
var _inventory: InventorySimulationSystem
var _blueprints := EquipmentBlueprintCatalog.new()
var _tools: ToolSimulationSystem


func _init() -> void:
	system_id = SYSTEM_ID
	tick_priority = 300


func configure(inventory: InventorySimulationSystem, tools: ToolSimulationSystem = null) -> ServiceResult:
	if not _state.is_empty() or inventory == null or MachineryWorkshop.KINDS.is_empty():
		return _failure("Configure one inventory capability provider.")
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/production/catalog.v1.json"))
	if typeof(raw) != TYPE_DICTIONARY:
		return _failure("A trusted production catalog is required.")
	var valid: ServiceResult = _validate_catalog(raw)
	if not valid.is_success:
		return valid
	_catalog = raw.duplicate(true)
	_catalog_fingerprint = JSON.stringify(_catalog, "", true, true).sha256_text()
	_inventory = inventory
	_tools = tools
	var blueprints: ServiceResult = _blueprints.configure(JSON.parse_string(FileAccess.get_file_as_string("res://data/production/equipment-blueprints.v1.json")), inventory, _catalog["materials"], tools.modular_inventory_definitions() if tools != null else [])
	if not blueprints.is_success:
		return blueprints
	_state = initial_record(0)
	return inventory.bind_payload_mass_provider(payload_mass)


func initial_record(tick: int) -> Dictionary:
	var powered: Dictionary = {}
	for station in STATIONS:
		powered[station] = true
	return {"schema_version": 6, "machinery": MachineryWorkshop.initial(), "loose_parts": {}, "structures": {}, "catalog_revision": 1, "catalog_fingerprint": _catalog_fingerprint, "timebase_hz": Engine.physics_ticks_per_second,
		"last_tick": tick, "state_revision": 0, "deposits": _initial_deposits(), "store": _empty_stock(),
		"vessel": _empty_stock(), "wall_mass_milligrams": 0, "energy_joules": 100000,
		"powered": powered, "job": {}, "receipts": [], "cargo": {}}


func payload_mass(item_id: String) -> int:
	return (int(MachineryWorkshop.KINDS[_state["machinery"]["parts"][item_id]["kind"]]) if _state.get("machinery", {}).get("parts", {}).has(item_id) else 0) + _mass(_state.get("loose_parts", {}).get(item_id, {})) + _mass(_state.get("cargo", {}).get(item_id, {})) + _mass(_state.get("structures", {}).get(item_id, {}).get("materials", {}))


static func payload_masses(state: Dictionary) -> Dictionary:
	var masses: Dictionary = cargo_masses(state.get("cargo", {}))
	for id in state.get("machinery", {}).get("parts", {}): masses[id] = int(masses.get(id, 0)) + int(MachineryWorkshop.KINDS[state["machinery"]["parts"][id]["kind"]])
	for id in state.get("loose_parts", {}): masses[id] = int(masses.get(id, 0)) + _mass(state["loose_parts"][id])
	for id in state.get("structures", {}):
		masses[id] = int(masses.get(id, 0)) + _mass(state["structures"][id]["materials"])
	return masses


static func cargo_masses(cargo: Dictionary) -> Dictionary:
	var masses: Dictionary = {}
	for item_id in cargo:
		masses[item_id] = _mass(cargo[item_id])
	return masses


## Validate payload/item associations and prospective carried/equipment capacities.
func validate_inventory_links(record: Dictionary, inventory_record: Dictionary) -> ServiceResult:
	if not MachineryWorkshop.validate(record.get("machinery", MachineryWorkshop.initial()), inventory_record.get("owner", {})): return _failure("Invalid machinery physical associations.")
	for machine in record.get("machinery", MachineryWorkshop.initial())["placements"]:
		var matched_location: bool = false
		for location in inventory_record.get("world_storage", []):
			if location["container_id"] == MachineryWorkshop.root_id(machine) and InventorySpatialMath.distance_millimetres(location["position_millimetres"], record["machinery"]["placements"][machine]["position"]) == 0: matched_location = true
		if not matched_location: return _failure("Deployed machinery requires its matching authoritative world location.")
	var cargo: Variant = record.get("cargo", {})
	if typeof(cargo) != TYPE_DICTIONARY or typeof(inventory_record.get("owner")) != TYPE_DICTIONARY:
		return _failure("Cargo requires a valid inventory owner record.")
	for id in cargo:
		if not _stock_valid(cargo[id], true):
			return _failure("Cargo component contents must be valid before cross-system validation.")
	var raw_structures: Variant = record.get("structures", {})
	if typeof(raw_structures) != TYPE_DICTIONARY or raw_structures.size() > 32:
		return _failure("A bounded structural map is required.")
	for id in raw_structures:
		if not ControlContractValidation.is_id(id) or not _blueprints.validate_structure(raw_structures[id], true).is_success:
			return _failure("Invalid equipment structure before inventory validation.")
	var loose_parts: Variant = record.get("loose_parts", {})
	if typeof(loose_parts) != TYPE_DICTIONARY or loose_parts.size() > 128: return _failure("Invalid physical part material map.")
	for id in loose_parts:
		if not ControlContractValidation.is_id(id) or not _stock_valid(loose_parts[id]): return _failure("Invalid loose part materials before inventory validation.")
	var validated_owner: ServiceResult = _inventory.validate_payload_masses(payload_masses(record), inventory_record["owner"])
	if not validated_owner.is_success:
		return validated_owner
	var carriers: Dictionary = {}
	var structures: Dictionary = record.get("structures", {})
	var matched: Dictionary = {}
	var matched_parts: Dictionary = {}
	for item in validated_owner.value.to_record()["ledger"]["items"]:
		var definition: ServiceResult = _inventory.factory_definition(item["definition_id"])
		if String(item["definition_id"]).begins_with("item.machine."):
			if not record.get("machinery", MachineryWorkshop.initial())["parts"].has(item["item_id"]): return _failure("Physical machinery requires conserved part provenance.")
		if item["definition_id"] == "item.resource-canister.prototype" and int(item["definition_revision"]) == 1:
			carriers[item["item_id"]] = true
		elif item["definition_id"] == "item.plate.prototype" and int(item["definition_revision"]) == 1:
			if not cargo.has(item["item_id"]) or int(cargo[item["item_id"]]["plate"]) != 1000000 or _mass(cargo[item["item_id"]]) != 1000000:
				return _failure("Each physical plate requires exactly its conserved one kilogram material payload.")
			carriers[item["item_id"]] = true
		elif item["definition_id"] == "item.tool-part.fabricated":
			if not loose_parts.has(item["item_id"]) or not _stock_valid(loose_parts[item["item_id"]]): return _failure("Physical parts require conserved material records.")
			matched_parts[item["item_id"]] = true
		elif definition.is_success and definition.value["tags"].has("equipment.fabricated"):
			var id: String = item["item_id"]
			if not structures.has(id):
				return _failure("Fabricated equipment requires its conserved structural record.")
			var structure: ServiceResult = _blueprints.validate_structure(structures[id], int(record["schema_version"]) >= 4)
			if not structure.is_success:
				return structure
			var blueprint: Dictionary = _blueprints.get_definition(structure.value["blueprint_id"]).value
			if item["definition_id"] != blueprint["definition_id"] or int(item["definition_revision"]) != blueprint["definition_revision"]:
				return _failure("Fabricated equipment must match its pinned inventory definition.")
			matched[id] = true
			if definition.value["tags"].has("resource.carrier"):
				carriers[id] = true
	if matched.size() != structures.size():
		return _failure("Each structural record must reference an actual fabricated item.")
	if matched_parts.size() != loose_parts.size(): return _failure("Each loose material record requires one physical part.")
	for id in cargo:
		if not carriers.has(id) or not _stock_valid(cargo[id], true):
			return _failure("Each payload must belong to an existing trusted physical carrier.")
	return ServiceResult.success()


func _initial_deposits() -> Dictionary:
	var result: Dictionary = {}
	for id in _catalog["deposits"]:
		result[id] = int(_catalog["deposits"][id]["mass_milligrams"])
	return result


func _empty_stock() -> Dictionary:
	var result: Dictionary = {}
	for id in _catalog["materials"]:
		result[id] = 0
	return result


func authorize(context: AuthenticatedCommandContext, voluntary: bool = true) -> ServiceResult:
	if _inventory == null or _state.is_empty():
		return _failure("Production services are unavailable.")
	return _inventory.production_capability(context, voluntary)


func authorize_operation(context: AuthenticatedCommandContext, operation: String, payload: Dictionary) -> ServiceResult:
	if operation.begins_with("machine_"): return _inventory.production_capability(context, true, [])
	if operation in ["cancel_tool_extract"]: return _inventory.production_capability(context, true, [])
	if operation == "resume_tool_extract":
		if not _state["job"].has("extraction"): return _failure("No sustained extraction is reserved.")
		return _inventory.production_capability(context, true, SOURCE_POSITIONS[_state["job"]["deposit_id"]])
	if operation not in ["extract", "tool_extract", "start_tool_extract"]:
		return authorize(context)
	if _inventory == null or not SOURCE_POSITIONS.has(payload.get("deposit_id")):
		return _failure("Select a registered environmental extraction source.")
	return _inventory.production_capability(context, true, SOURCE_POSITIONS[payload["deposit_id"]])


func observation(context: AuthenticatedCommandContext) -> ServiceResult:
	var allowed: ServiceResult = _inventory.production_capability(context, false, []) if _inventory != null else _failure("Inventory is unavailable.")
	if not allowed.is_success:
		return allowed
	var observed: Dictionary = _state.duplicate(false)
	observed.erase("receipts")
	observed.erase("cargo")
	observed.erase("structures")
	observed.erase("loose_parts")
	observed.erase("machinery")
	observed = observed.duplicate(true)
	observed["tool_extraction"] = {}
	if observed["job"].has("extraction"):
		if observed["job"]["extraction"]["principal_id"] == String(context.principal_id): observed["tool_extraction"] = observed["job"]["extraction"].duplicate(true)
		observed["job"].erase("extraction")
	observed["cargo"] = {}
	var carriers: ServiceResult = _inventory.owned_resource_carriers(context)
	if not carriers.is_success:
		return carriers
	for id in carriers.value:
		observed["cargo"][id] = _state["cargo"].get(id, _empty_stock()).duplicate(true)
	observed["components"] = []
	var own: ServiceResult = _inventory.own_inventory_observation(context)
	observed["structures"] = {}
	observed["loose_parts"] = {}
	observed["blueprints"] = _blueprints.observation()
	for item in own.value["items"]:
		if item["definition_id"] == "item.plate.prototype":
			observed["components"].append(item["item_id"])
		if _state["loose_parts"].has(item["item_id"]): observed["loose_parts"][item["item_id"]] = _state["loose_parts"][item["item_id"]].duplicate(true)
		if _state["structures"].has(item["item_id"]):
			observed["structures"][item["item_id"]] = _state["structures"][item["item_id"]].duplicate(true)
	observed["machinery"] = machinery_observation(context)
	observed["recipes"] = _catalog["recipes"].keys()
	observed["dispensable"] = _catalog["dispensable"].duplicate()
	observed["can_operate"] = authorize(context).is_success
	observed["vessel_pressure_kpa"] = _vessel_pressure(_state["vessel"])
	observed["extractable_sources"] = []
	for id in SOURCE_POSITIONS:
		if _inventory.production_capability(context, true, SOURCE_POSITIONS[id]).is_success:
			observed["extractable_sources"].append(id)
	return ServiceResult.success(observed)


## Called by fixed-tick command ingress; commits one whole candidate on success.
func apply_local(context: AuthenticatedCommandContext, request_id: String, operation: String, payload: Dictionary, tick: int) -> ServiceResult:
	var allowed: ServiceResult = authorize_operation(context, operation, payload)
	if not allowed.is_success:
		return allowed
	if operation == "tool_extract" and not _inventory.active_tool(context, "tool.extractor").is_success:
		return _failure("Hold a working resource extractor in your active hand.")
	if not ControlContractValidation.is_id(request_id) or tick != int(_state["last_tick"]) + 1 or Engine.physics_ticks_per_second != int(_state["timebase_hz"]):
		return _failure("A fresh fixed tick and stable request identity are required.")
	var fingerprint: String = JSON.stringify([String(context.principal_id), operation, payload], "", true).sha256_text()
	for receipt in _state["receipts"]:
		if receipt["request_id"] == request_id:
			return ServiceResult.success(receipt.duplicate(true)) if receipt["fingerprint"] == fingerprint else _failure("Retained request ID identifies different intent.")
	if not payload.has("expected_revision") or not ControlContractValidation.is_integer(payload["expected_revision"], int(_state["state_revision"]), int(_state["state_revision"])) or int(_state["state_revision"]) >= MAX_REVISION:
		return _failure("The production revision is stale or exhausted.")
	var candidate: Dictionary = _state.duplicate(true)
	var prepared_inventory: Dictionary = {}
	var prepared_graph: Dictionary = {}
	var prepared_tools: ToolAssemblyLedger
	var planned_work: bool = operation.begins_with("machine_") or operation in ["start_tool_extract", "resume_tool_extract", "cancel_tool_extract"]
	if operation.begins_with("machine_"):
		var machinery_plan: ServiceResult = MachineryConstruction.plan(self, candidate, _inventory, context, request_id, operation, payload)
		if not machinery_plan.is_success: return machinery_plan
		if not MachineryWorkshop.validate(candidate["machinery"]): return _failure("Invalid machinery candidate.")
		prepared_graph = machinery_plan.value
	elif planned_work:
		var work: ServiceResult = _prepare_tool_extraction(candidate, context, request_id, operation, payload)
		if not work.is_success: return work
	if operation == "cancel" and candidate["job"].has("extraction"): return _failure("Use the owned sustained-extraction cancellation action.")
	if operation in ["fabricate_tool_part", "recycle_tool_part", "detach_tool_part", "fit_tool_part"]:
		var parts: ServiceResult = _prepare_tool_parts(candidate, context, request_id, operation, payload)
		if not parts.is_success: return parts
		prepared_inventory = parts.value["owner"]
		prepared_tools = parts.value["ledger"]
	if operation == "repair_tool_component":
		if _tools == null or not _fields(payload, ["expected_revision", "expected_tool_revision", "part_id", "amount_ppm"]) or not ControlContractValidation.is_id(payload.get("part_id")) or not ControlContractValidation.is_integer(payload.get("amount_ppm"), 1, 1000000) or not ControlContractValidation.is_integer(payload.get("expected_tool_revision"), 0, MAX_REVISION): return _failure("Repair requires exact component identity, revisions and bounded integrity.")
		var repair: ServiceResult = _tools.prepare_repair(context, payload["part_id"], int(payload["amount_ppm"]), int(payload["expected_tool_revision"]))
		if not repair.is_success: return repair
		if not candidate["powered"]["construction"] or int(candidate["energy_joules"]) < int(repair.value["energy_joules"]): return _failure("Maintenance requires workstation power and sufficient energy.")
		candidate["energy_joules"] -= int(repair.value["energy_joules"])
		prepared_tools = repair.value["ledger"]
	if operation in ["fabricate_equipment", "salvage_equipment"]:
		var factory: ServiceResult = _prepare_fabrication(candidate, context, request_id, operation, payload)
		if not factory.is_success:
			return factory
		prepared_inventory = factory.value
	if operation in ["materialize_plate", "recycle_component"]:
		var create: bool = operation == "materialize_plate"
		if not _fields(payload, ["expected_revision"] if create else ["expected_revision", "item_id"]):
			return _failure("Physical components require an exact factory or recycler intent.")
		if not create and not ControlContractValidation.is_id(payload["item_id"]):
			return _failure("The recyclable physical item ID must be a bounded string.")
		var item_id: String = "plate-%s" % request_id.sha256_text().substr(0, 24) if create else String(payload.get("item_id", ""))
		if create:
			if int(candidate["store"]["plate"]) < 1000000 or candidate["cargo"].size() >= 32:
				return _failure("Printing output or physical component capacity is unavailable.")
			candidate["store"]["plate"] -= 1000000
			candidate["cargo"][item_id] = _empty_stock()
			candidate["cargo"][item_id]["plate"] = 1000000
		else:
			if not candidate["powered"]["recycler"] or int(candidate["energy_joules"]) < 500 or not candidate["cargo"].has(item_id) or int(candidate["cargo"][item_id]["plate"]) != 1000000 or _mass(candidate["store"]) + _reserved_mass(candidate) + 1000000 > MAX_MASS:
				return _failure("The physical component, recycler energy or receiving capacity is unavailable.")
			candidate["cargo"].erase(item_id)
			candidate["store"]["iron"] += 1000000
			candidate["energy_joules"] -= 500
		var prepared: ServiceResult = _inventory.prepare_plate_change(context, "factory-%s" % request_id.sha256_text().substr(0, 32), item_id, create, payload_masses(candidate))
		if not prepared.is_success:
			return prepared
		prepared_inventory = prepared.value
	if operation in ["load_cargo", "unload_cargo", "extract", "tool_extract"]:
		var carriers: ServiceResult = _inventory.owned_resource_carriers(context)
		if not carriers.is_success or not carriers.value.has(payload.get("carrier_id")):
			return _failure("Only a carrier in your own inventory may be filled or emptied.")
	var applied: ServiceResult = ServiceResult.success() if planned_work or not prepared_inventory.is_empty() or prepared_tools != null else _plan(candidate, "extract" if operation == "tool_extract" else operation, payload)
	if not applied.is_success:
		return applied
	if operation == "tool_extract" and _tools != null:
		var active: ServiceResult = _inventory.active_tool(context, "tool.extractor")
		var usage: ServiceResult = _tools.prepare_usage(active.value)
		if not usage.is_success: return usage
		prepared_tools = usage.value
	if not prepared_inventory.is_empty() and _tools != null and prepared_tools == null:
		var sync: ServiceResult = _tools.prepare_inventory(prepared_inventory, candidate["structures"], candidate["loose_parts"])
		if not sync.is_success: return sync
		prepared_tools = sync.value
	candidate["state_revision"] = int(candidate["state_revision"]) + 1
	var receipt: Dictionary = {"request_id": request_id, "fingerprint": fingerprint, "state_revision": candidate["state_revision"], "tick_number": tick}
	candidate["receipts"].append(receipt)
	if candidate["receipts"].size() > MAX_RECEIPTS:
		candidate["receipts"].pop_front()
	var capacity: ServiceResult = _inventory.validate_payload_masses(payload_masses(candidate), prepared_inventory if prepared_graph.is_empty() else prepared_graph["owner"])
	if not capacity.is_success:
		return capacity
	var previous: Dictionary = _state
	_state = candidate
	if not prepared_graph.is_empty():
		var graph_commit: ServiceResult = _inventory.commit_factory_graph(prepared_graph)
		if not graph_commit.is_success:
			_state = previous
			return graph_commit
	if not prepared_inventory.is_empty():
		var committed: ServiceResult = _inventory.commit_prepared_owner(prepared_inventory)
		if not committed.is_success:
			_state = previous
			return committed
	# Derived caches only; all capacities were validated above without an await.
	if prepared_tools != null: _tools.commit_prepared(prepared_tools)
	_inventory.refresh_payload_loads()
	return ServiceResult.success(receipt.duplicate(true))


func _prepare_tool_parts(candidate: Dictionary, context: AuthenticatedCommandContext, request_id: String, operation: String, payload: Dictionary) -> ServiceResult:
	var fields: Array = ["expected_revision", "expected_tool_revision"]
	match operation:
		"fabricate_tool_part": fields.append("blueprint_id")
		"recycle_tool_part": fields.append("part_id")
		"detach_tool_part": fields.append_array(["item_id", "slot_id"])
		"fit_tool_part": fields.append_array(["item_id", "slot_id", "part_id"])
	if _tools == null or not _fields(payload, fields) or not ControlContractValidation.is_integer(payload.get("expected_tool_revision"), 0, MAX_REVISION): return _failure("Part operations require exact identities and current tool revision.")
	for field in fields:
		if field not in ["expected_revision", "expected_tool_revision"] and not ControlContractValidation.is_id(payload[field]): return _failure("Invalid tool/part intent identity.")
	var planned: ServiceResult = _tools.prepare_part_change(context, operation, payload, request_id)
	if not planned.is_success: return planned
	var plan: Dictionary = planned.value
	if not candidate["powered"][plan["station"]] or int(candidate["energy_joules"]) < int(plan["energy_joules"]): return _failure("Part work requires station power and finite energy.")
	for material in plan["debit"]:
		if not candidate["store"].has(material) or int(candidate["store"][material]) < int(plan["debit"][material]): return _failure("Part fabrication materials are missing.")
	if _mass(candidate["store"]) + _reserved_mass(candidate) + _mass(plan["credit"]) > MAX_MASS: return _failure("Recycled part exceeds receiving capacity.")
	for material in plan["debit"]: candidate["store"][material] -= int(plan["debit"][material])
	_add(candidate["store"], plan["credit"])
	candidate["energy_joules"] -= int(plan["energy_joules"])
	if not plan["tool_id"].is_empty():
		if not candidate["structures"].has(plan["tool_id"]): return _failure("Modified tools require conserved structure.")
		candidate["structures"][plan["tool_id"]]["materials"] = _tools.assembly_stock(plan["ledger"], plan["tool_id"])
	for change in plan["changes"]:
		if change["create"]: candidate["loose_parts"][change["item_id"]] = _tools.part_stock(plan["ledger"], change["item_id"])
		else: candidate["loose_parts"].erase(change["item_id"])
	if candidate["loose_parts"].size() > 128: return _failure("The physical part registry is full.")
	var owner: Dictionary = _inventory.capture_snapshot().value["owner"]
	for index in range(plan["changes"].size()):
		var change: Dictionary = plan["changes"][index]
		var prepared: ServiceResult = _inventory.prepare_equipment_change(context, "part-%s-%d" % [request_id.sha256_text().substr(0, 24), index], change["item_id"], change["create"], payload_masses(candidate), "item.tool-part.fabricated", owner)
		if not prepared.is_success: return prepared
		owner = prepared.value
	var record: Dictionary = _tools.capture_snapshot().value
	record["ledger"] = plan["ledger"].to_record()
	var links: ServiceResult = _tools.validate_inventory_links(record, owner, candidate["structures"], candidate["loose_parts"])
	return ServiceResult.success({"owner": owner, "ledger": plan["ledger"]}) if links.is_success else links


func _prepare_tool_extraction(candidate: Dictionary, context: AuthenticatedCommandContext, request_id: String, operation: String, payload: Dictionary) -> ServiceResult:
	if operation != "start_tool_extract":
		if not _fields(payload, ["expected_revision"]) or not candidate["job"].has("extraction") or candidate["job"]["extraction"]["principal_id"] != String(context.principal_id): return _failure("Only the initiating crew member can resume or cancel this work.")
		if operation == "cancel_tool_extract":
			candidate["deposits"][candidate["job"]["deposit_id"]] += _mass(candidate["job"]["inputs"])
			candidate["job"] = {}
		else:
			if candidate["job"]["extraction"]["status"] != "paused" or _tool_extraction_reason(candidate["job"]["extraction"], context) != "": return _failure("Restore the bound tool, carrier, reach, power and capabilities before resuming.")
			candidate["job"]["extraction"]["status"] = "running"
			candidate["job"]["extraction"]["pause_reason"] = ""
		return ServiceResult.success()
	if _tools == null or not _fields(payload, ["expected_revision", "deposit_id", "carrier_id", "cycles"]) or not SOURCE_POSITIONS.has(payload.get("deposit_id")) or not ControlContractValidation.is_id(payload.get("carrier_id")) or not ControlContractValidation.is_integer(payload.get("cycles"), 1, ToolExtractionWork.MAX_CYCLES) or not candidate["job"].is_empty() or int(candidate["state_revision"]) > MAX_REVISION - 100: return _failure("Reserve 1–10 extraction cycles with exact source/carrier identities while production is idle.")
	var active: ServiceResult = _inventory.active_tool(context, "tool.extractor")
	if not active.is_success: return active
	var binding: Dictionary = {"request_id": request_id, "principal_id": String(context.principal_id), "tool_id": active.value, "carrier_id": payload["carrier_id"], "deposit_id": payload["deposit_id"], "remaining_cycles": int(payload["cycles"]), "completed_cycles": 0, "status": "running", "pause_reason": ""}
	if _tool_extraction_reason(binding, context) != "": return _failure("The bound tool, carrier, power and energy must be available.")
	var mass: int = int(payload["cycles"]) * ToolExtractionWork.CYCLE_MASS
	if int(candidate["deposits"][payload["deposit_id"]]) < mass: return _failure("The source cannot satisfy this reservation.")
	var material: String = _catalog["deposits"][payload["deposit_id"]]["material"]
	candidate["deposits"][payload["deposit_id"]] -= mass
	candidate["job"] = {"recipe_id": "", "deposit_id": payload["deposit_id"], "station": "drill", "inputs": {material: mass}, "outputs": {material: mass}, "remaining_ticks": ToolExtractionWork.CYCLE_TICKS, "extraction": binding}
	return ServiceResult.success()


func _tool_extraction_reason(binding: Dictionary, context: AuthenticatedCommandContext) -> String:
	if not _inventory.production_capability(context, true, SOURCE_POSITIONS[binding["deposit_id"]]).is_success: return "capability"
	var active: ServiceResult = _inventory.active_tool(context, "tool.extractor")
	if not active.is_success or active.value != binding["tool_id"]: return "capability"
	var carriers: ServiceResult = _inventory.owned_resource_carriers(context)
	if not carriers.is_success or not carriers.value.has(binding["carrier_id"]): return "carrier"
	if not _state["powered"]["drill"]: return "power"
	if int(_state["energy_joules"]) < 250: return "energy"
	return ""


func _simulate_tool_extraction(tick: int) -> void:
	if int(_state["state_revision"]) >= MAX_REVISION: return
	var binding: Dictionary = _state["job"]["extraction"]
	if binding["status"] != "running": return
	var world := get_parent().get_parent() as WorldRuntime
	var context: AuthenticatedCommandContext = ToolExtractionWork.context(binding, world.world_id, world.region_id)
	var reason: String = _tool_extraction_reason(binding, context)
	if reason != "":
		_pause_tool_extraction(reason)
		return
	if _state["job"]["remaining_ticks"] > 1:
		_state["job"]["remaining_ticks"] -= 1
		return
	var candidate: Dictionary = _state.duplicate(true)
	# Temporarily expose exactly one reserved cycle to the shared atomic extraction planner.
	candidate["deposits"][binding["deposit_id"]] += ToolExtractionWork.CYCLE_MASS
	var applied: ServiceResult = _plan(candidate, "extract", {"expected_revision": candidate["state_revision"], "deposit_id": binding["deposit_id"], "carrier_id": binding["carrier_id"], "amount_milligrams": ToolExtractionWork.CYCLE_MASS})
	var usage: ServiceResult = _tools.prepare_usage(binding["tool_id"])
	if not applied.is_success or not _inventory.validate_payload_masses(payload_masses(candidate)).is_success:
		_pause_tool_extraction("capacity")
		return
	if not usage.is_success:
		_pause_tool_extraction("capability")
		return
	var material: String = _catalog["deposits"][binding["deposit_id"]]["material"]
	var completed: int = int(binding["completed_cycles"]) + 1
	if int(binding["remaining_cycles"]) == 1:
		candidate["job"] = {}
	else:
		candidate["job"]["extraction"]["remaining_cycles"] -= 1
		candidate["job"]["extraction"]["completed_cycles"] = completed
		candidate["job"]["inputs"][material] -= ToolExtractionWork.CYCLE_MASS
		candidate["job"]["outputs"][material] -= ToolExtractionWork.CYCLE_MASS
		candidate["job"]["remaining_ticks"] = ToolExtractionWork.CYCLE_TICKS
	candidate["state_revision"] += 1
	_state = candidate
	_tools.commit_prepared(usage.value)
	_inventory.refresh_payload_loads()
	extraction_cycle_completed.emit(binding["request_id"], completed, tick)


func _pause_tool_extraction(reason: String) -> void:
	_state["job"]["extraction"]["status"] = "paused"
	_state["job"]["extraction"]["pause_reason"] = reason
	_state["state_revision"] += 1


## Atomic bounded equipment assembly/disassembly; contents are returned intact.
func _prepare_fabrication(candidate: Dictionary, context: AuthenticatedCommandContext, request_id: String, operation: String, payload: Dictionary) -> ServiceResult:
	var create: bool = operation == "fabricate_equipment"
	if not _fields(payload, ["expected_revision", "blueprint_id"] if create else ["expected_revision", "item_id"]):
		return _failure("Equipment assembly requires an exact blueprint or item intent.")
	var item_id: String
	var blueprint_id: String
	if create:
		if not ControlContractValidation.is_id(payload["blueprint_id"]) or candidate["structures"].size() >= 32:
			return _failure("Select a registered blueprint; the equipment registry is bounded.")
		item_id = "equipment-%s" % request_id.sha256_text().substr(0, 24)
		blueprint_id = payload["blueprint_id"]
	else:
		if not ControlContractValidation.is_id(payload["item_id"]) or not candidate["structures"].has(payload["item_id"]):
			return _failure("Select an existing fabricated item.")
		item_id = payload["item_id"]
		blueprint_id = candidate["structures"][item_id]["blueprint_id"]
	var result: ServiceResult = _blueprints.get_definition(blueprint_id)
	if not result.is_success:
		return result
	var blueprint: Dictionary = result.value
	var energy: int = blueprint["fabrication_energy_joules"] if create else blueprint["salvage_energy_joules"]
	if not candidate["powered"]["printer" if create else "recycler"] or int(candidate["energy_joules"]) < energy:
		return _failure("Assembly or salvage requires powered equipment and finite energy.")
	if create:
		for material in blueprint["materials"]:
			if int(candidate["store"][material]) < int(blueprint["materials"][material]):
				return _failure("Blueprint materials are missing from workstation storage.")
		for material in blueprint["materials"]:
			candidate["store"][material] -= int(blueprint["materials"][material])
		candidate["structures"][item_id] = {"blueprint_id": blueprint_id, "fingerprint": blueprint["fingerprint"], "materials": blueprint["materials"].duplicate(true)}
	else:
		var contents: Dictionary = candidate["cargo"].get(item_id, {})
		if _mass(candidate["store"]) + _reserved_mass(candidate) + _mass(candidate["structures"][item_id]["materials"]) + _mass(contents) > MAX_MASS:
			return _failure("Salvage and contents exceed receiving storage capacity.")
		_add(candidate["store"], candidate["structures"][item_id]["materials"])
		_add(candidate["store"], contents)
		candidate["cargo"].erase(item_id)
		candidate["structures"].erase(item_id)
	candidate["energy_joules"] -= energy
	return _inventory.prepare_equipment_change(context, "factory-%s" % request_id.sha256_text().substr(0, 32), item_id, create, payload_masses(candidate), blueprint["definition_id"])


func _plan(candidate: Dictionary, operation: String, payload: Dictionary) -> ServiceResult:
	if operation == "extract":
		if not _fields(payload, ["expected_revision", "deposit_id", "carrier_id", "amount_milligrams"]) or not _catalog["deposits"].has(payload["deposit_id"]) or not ControlContractValidation.is_id(payload["carrier_id"]) or not ControlContractValidation.is_integer(payload["amount_milligrams"], 1, 1000000):
			return _failure("Extraction requires a source, owned carrier and positive mass up to 1 kg.")
		var id: String = payload["carrier_id"]
		if not candidate["cargo"].has(id):
			if candidate["cargo"].size() >= 32:
				return _failure("The portable carrier registry is full.")
			candidate["cargo"][id] = _empty_stock()
		var amount: int = int(payload["amount_milligrams"])
		var energy: int = maxi(1, int(ceil(float(amount) / 4000.0)))
		if int(candidate["deposits"][payload["deposit_id"]]) < amount or int(candidate["energy_joules"]) < energy or not candidate["powered"]["drill"]:
			return _failure("Source mass, extractor power or finite energy is unavailable.")
		var material: String = _catalog["deposits"][payload["deposit_id"]]["material"]
		candidate["cargo"][id][material] += amount
		if not _cargo_valid(candidate["cargo"][id]):
			return _failure("The receiving canister is full, incompatible or overpressure.")
		candidate["deposits"][payload["deposit_id"]] -= amount
		candidate["energy_joules"] -= energy
		return ServiceResult.success()
	if operation in ["load_cargo", "unload_cargo"]:
		if not _fields(payload, ["expected_revision", "carrier_id", "material", "amount_milligrams"]) or not ControlContractValidation.is_id(payload["carrier_id"]) or not _catalog["materials"].has(payload["material"]) or not ControlContractValidation.is_integer(payload["amount_milligrams"], 1, VESSEL_CAPACITY):
			return _failure("Portable transfer requires an exact carrier/material intent and bounded mass.")
		var id: String = payload["carrier_id"]
		if not candidate["cargo"].has(id):
			if candidate["cargo"].size() >= 32:
				return _failure("The portable carrier registry is full.")
			candidate["cargo"][id] = _empty_stock()
		var source: Dictionary = candidate["store"] if operation == "load_cargo" else candidate["cargo"][id]
		var destination: Dictionary = candidate["cargo"][id] if operation == "load_cargo" else candidate["store"]
		var amount: int = int(payload["amount_milligrams"])
		var capacity: int = VESSEL_CAPACITY if operation == "load_cargo" else MAX_MASS - _reserved_mass(candidate)
		if int(source[payload["material"]]) < amount or _mass(destination) + amount > capacity:
			return _failure("Portable transfer exceeds existing stock or receiving capacity.")
		source[payload["material"]] -= amount
		destination[payload["material"]] += amount
		if not _cargo_valid(candidate["cargo"][id]):
			return _failure("The carrier permits one material at a time and must satisfy gas pressure limits.")
		return ServiceResult.success()
	if operation == "power":
		if not _fields(payload, ["expected_revision", "station", "enabled"]) or not STATIONS.has(payload["station"]) or typeof(payload["enabled"]) != TYPE_BOOL:
			return _failure("Select a registered station and boolean power state.")
		candidate["powered"][payload["station"]] = payload["enabled"]
		return ServiceResult.success()
	if operation == "cancel":
		if not _fields(payload, ["expected_revision"]) or candidate["job"].is_empty():
			return _failure("No batch is available to cancel.")
		var job: Dictionary = candidate["job"]
		if job["deposit_id"] != "":
			candidate["deposits"][job["deposit_id"]] += _mass(job["inputs"])
		else:
			_add(candidate["store"], job["inputs"])
		candidate["job"] = {}
		return ServiceResult.success() # Spent energy is not refunded.
	if operation in ["dispense", "return"]:
		if not _fields(payload, ["expected_revision", "material", "amount_milligrams"]) or not _catalog["dispensable"].has(payload["material"]) or not ControlContractValidation.is_integer(payload["amount_milligrams"], 1, VESSEL_CAPACITY) or not candidate["powered"]["dispenser"]:
			return _failure("Powered dispensing requires a registered chemical and positive bounded mass.")
		var source: Dictionary = candidate["store"] if operation == "dispense" else candidate["vessel"]
		var destination: Dictionary = candidate["vessel"] if operation == "dispense" else candidate["store"]
		var amount: int = int(payload["amount_milligrams"])
		var capacity: int = VESSEL_CAPACITY if operation == "dispense" else MAX_MASS - _reserved_mass(candidate)
		if int(source[payload["material"]]) < amount or _mass(destination) + amount > capacity:
			return _failure("Insufficient chemical or receiving capacity.")
		source[payload["material"]] -= amount
		destination[payload["material"]] += amount
		if _vessel_pressure(candidate["vessel"]) > MAX_VESSEL_PRESSURE_KPA:
			return _failure("Transfer exceeds the sealed vessel pressure limit; use a smaller amount or remove gas/liquid.")
		return ServiceResult.success()
	if operation in ["build", "deconstruct"]:
		if not _fields(payload, ["expected_revision"]) or not candidate["powered"]["construction"]:
			return _failure("Construction requires the powered fixture tool.")
		if operation == "build":
			if int(candidate["store"]["plate"]) < 1000000:
				return _failure("One kilogram of printed plate is required for a wall segment.")
			candidate["store"]["plate"] -= 1000000
			candidate["wall_mass_milligrams"] += 1000000
		else:
			if int(candidate["wall_mass_milligrams"]) < 1000000 or _mass(candidate["store"]) + _reserved_mass(candidate) + 1000000 > MAX_MASS:
				return _failure("No wall segment or insufficient receiving capacity.")
			candidate["wall_mass_milligrams"] -= 1000000
			candidate["store"]["plate"] += 1000000
		return ServiceResult.success()
	if not candidate["job"].is_empty():
		return _failure("Finish or cancel the active workstation batch first.")
	if int(candidate["state_revision"]) > MAX_REVISION - 36001:
		return _failure("Insufficient revision capacity to complete a batch.")
	var inputs: Dictionary
	var outputs: Dictionary
	var station: String
	var duration: int
	var energy: int
	var deposit_id: String = ""
	var recipe_id: String = ""
	if operation == "mine":
		if not _fields(payload, ["expected_revision", "deposit_id"]) or not _catalog["deposits"].has(payload["deposit_id"]):
			return _failure("Mining requires a registered finite deposit.")
		deposit_id = payload["deposit_id"]
		if int(candidate["deposits"][deposit_id]) < 1000000:
			return _failure("This deposit is exhausted.")
		inputs = {_catalog["deposits"][deposit_id]["material"]: 1000000}
		outputs = inputs.duplicate(true)
		station = "drill"
		duration = 60
		energy = 250
	elif operation == "process":
		if not _fields(payload, ["expected_revision", "recipe_id"]) or not _catalog["recipes"].has(payload["recipe_id"]):
			return _failure("Processing requires a trusted recipe ID.")
		recipe_id = payload["recipe_id"]
		var recipe: Dictionary = _catalog["recipes"][recipe_id]
		inputs = recipe["inputs"].duplicate(true)
		outputs = recipe["outputs"].duplicate(true)
		station = recipe["station"]
		duration = int(recipe["duration_ticks"])
		energy = int(recipe["energy_joules"])
		for material in inputs:
			if int(candidate["store"][material]) < int(inputs[material]):
				return _failure("Recipe ingredients are missing.")
	else:
		return _failure("Unknown production operation.")
	if not candidate["powered"][station] or int(candidate["energy_joules"]) < energy or _mass(candidate["store"]) + (0 if deposit_id == "" else _mass(outputs)) > MAX_MASS:
		return _failure("Station power, finite energy or output storage is unavailable.")
	if deposit_id != "":
		candidate["deposits"][deposit_id] -= 1000000
	else:
		for material in inputs:
			candidate["store"][material] -= int(inputs[material])
	candidate["energy_joules"] -= energy
	candidate["job"] = {"recipe_id": recipe_id, "deposit_id": deposit_id, "station": station,
		"inputs": inputs, "outputs": outputs, "remaining_ticks": duration}
	return ServiceResult.success()


func simulate_tick(tick: int, _delta: float) -> void:
	if _state.is_empty() or tick != int(_state["last_tick"]) + 1 or Engine.physics_ticks_per_second != int(_state["timebase_hz"]):
		return
	_state["last_tick"] = tick
	_simulate_machinery()
	if _state["job"].has("extraction"):
		_simulate_tool_extraction(tick)
		return
	if _state["job"].is_empty() or not _state["powered"][_state["job"]["station"]]:
		return
	if int(_state["state_revision"]) >= MAX_REVISION:
		return
	_state["job"]["remaining_ticks"] -= 1
	if int(_state["job"]["remaining_ticks"]) == 0:
		# Countdown is progress, not a competing material/configuration transaction.
		# Keep the command revision stable so remote pause/cancel can be applied.
		_state["state_revision"] += 1
		var completed_recipe: String = _state["job"]["recipe_id"]
		_add(_state["store"], _state["job"]["outputs"])
		_state["job"] = {}
		batch_completed.emit(completed_recipe, tick)


func capture_snapshot() -> ServiceResult:
	return ServiceResult.success(_state.duplicate(true)) if not _state.is_empty() else _failure("Production is unconfigured.")


## Work recipes share the trusted refinery/chemistry recipes and finite deposits.
func machine_recipe(id: String) -> Dictionary:
	if _catalog["recipes"].has(id):
		var recipe: Dictionary = _catalog["recipes"][id].duplicate(true)
		recipe["capability"] = "printhead" if recipe["station"] == "printer" else "refinery"
		recipe["deposit"] = ""
		return recipe
	if id.begins_with("extract."):
		var deposit: String = "deposit.%s" % id.trim_prefix("extract.")
		if _catalog["deposits"].has(deposit):
			var material: String = _catalog["deposits"][deposit]["material"]
			return {"inputs": {}, "outputs": {material: 1000000}, "duration_ticks": 60, "energy_joules": 1000, "capability": "extractor", "deposit": deposit}
	return {}


func machine_blueprint(id: String) -> ServiceResult:
	return _blueprints.get_definition(id)


func machinery_observation(context: AuthenticatedCommandContext) -> Dictionary:
	var observed: Dictionary = _state["machinery"].duplicate(true)
	var own: ServiceResult = _inventory.own_inventory_observation(context)
	var owner: Dictionary = _inventory.capture_snapshot().value["owner"]
	for id in observed["placements"].keys():
		if not MachineryWorkshop.deployed(observed, owner, id): observed["placements"].erase(id)
	for id in observed["links"].keys():
		if not observed["placements"].has(observed["links"][id]["a"]) or not observed["placements"].has(observed["links"][id]["b"]): observed["links"].erase(id)
	for id in observed["jobs"].keys():
		if not observed["placements"].has(id): observed["jobs"].erase(id)
	var visible: Dictionary = {}
	for physical in own.value["items"]: visible[physical["item_id"]] = true
	for machine in observed["placements"]:
		visible[machine] = true
		for ids in MachineryWorkshop.modules(observed, owner, machine).values():
			for id in ids: visible[id] = true
	for id in observed["links"]: visible[id] = true
	for physical in owner["ledger"]["items"]:
		for machine in observed["placements"]:
			if physical["container_id"] == MachineryWorkshop.container(owner, machine): visible[physical["item_id"]] = true
	for id in observed["parts"].keys():
		if not visible.has(id): observed["parts"].erase(id)
	for id in observed["mounts"].keys():
		if not visible.has(id) or not visible.has(observed["mounts"][id]): observed["mounts"].erase(id)
	observed["inventory_items"] = []
	observed["cargo"] = {}
	var containers: Dictionary = {}
	for id in visible:
		var storage: String = MachineryWorkshop.container(owner, id)
		if not storage.is_empty(): containers[storage] = true
	for physical in owner["ledger"]["items"]:
		if visible.has(physical["item_id"]) or containers.has(physical["container_id"]):
			observed["inventory_items"].append(physical.duplicate(true))
			if _state["cargo"].has(physical["item_id"]): observed["cargo"][physical["item_id"]] = _state["cargo"][physical["item_id"]].duplicate(true)
	return observed


func _simulate_machinery() -> void:
	var workshop: Dictionary = _state["machinery"]
	if workshop["placements"].is_empty() or int(_state["state_revision"]) >= MAX_REVISION: return
	var owner: Dictionary = _inventory.capture_snapshot().value["owner"]
	var hz: int = int(_state["timebase_hz"])
	var budgets: Dictionary = {}
	for cable in workshop["links"]: budgets[cable] = MachineryWorkshop.CABLE_WATTS / hz
	var ids: Array = workshop["placements"].keys()
	ids.sort()
	for id in ids:
		if MachineryWorkshop.operational(workshop, owner, id, "solar"):
			var placement: Dictionary = workshop["placements"][id]
			placement["generation_remainder"] += MachineryWorkshop.GENERATION_WATTS
			placement["energy"] = mini(MachineryWorkshop.CAPACITY, int(placement["energy"]) + int(placement["generation_remainder"]) / hz)
			placement["generation_remainder"] = int(placement["generation_remainder"]) % hz
	for id in ids:
		if MachineryWorkshop.operational(workshop, owner, id, "solar") or not MachineryWorkshop.deployed(workshop, owner, id): continue
		var placement: Dictionary = workshop["placements"][id]
		if not placement["enabled"] or not MachineryWorkshop.modules(workshop, owner, id).has("controller"): continue
		var charge: int = mini(MachineryWorkshop.GENERATION_WATTS / hz, MachineryWorkshop.CAPACITY - int(placement["energy"]))
		if MachineryWorkshop.draw(workshop, owner, id, charge, budgets): placement["energy"] += charge
	var jobs: Array = workshop["jobs"].keys()
	jobs.sort()
	for id in jobs:
		var job: Dictionary = workshop["jobs"][id]
		if job["paused"]: continue
		var recipe: Dictionary = machine_recipe(job["recipe"])
		if not MachineryWorkshop.operational(workshop, owner, id, recipe["capability"]): continue
		if not recipe["deposit"].is_empty() and int(_state["deposits"][recipe["deposit"]]) < 1000000: continue
		var transfer: ServiceResult = MachineryConstruction.transfer_plan(_state, owner, id, recipe["inputs"], recipe["outputs"])
		if not transfer.is_success: continue
		var target_energy: int = (int(job["progress"]) + 1) * int(recipe["energy_joules"]) / int(recipe["duration_ticks"])
		var energy: int = target_energy - int(job["energy_spent"])
		if int(workshop["placements"][id]["energy"]) < energy: continue
		var prospective: Dictionary = _state.duplicate(true)
		prospective["cargo"] = transfer.value
		var valid: bool = true
		for stock in transfer.value.values():
			if not _cargo_valid(stock): valid = false
		if not valid or not _inventory.validate_payload_masses(payload_masses(prospective)).is_success: continue
		workshop["placements"][id]["energy"] -= energy
		job["energy_spent"] = target_energy
		job["progress"] += 1
		if int(job["progress"]) == int(recipe["duration_ticks"]):
			_state["cargo"] = transfer.value
			if not recipe["deposit"].is_empty(): _state["deposits"][recipe["deposit"]] -= 1000000
			workshop["jobs"].erase(id)
			_state["state_revision"] += 1
			_inventory.refresh_payload_loads()
			batch_completed.emit(job["recipe"], int(_state["last_tick"]))


func validate_snapshot_record(record: Dictionary, tick: int) -> ServiceResult:
	return _decode(record, tick)


func restore_snapshot_record(record: Dictionary, tick: int) -> ServiceResult:
	var decoded: ServiceResult = _decode(record, tick)
	if decoded.is_success:
		_state = decoded.value
		for job in _state["machinery"]["jobs"].values(): job["paused"] = true
		if _state["job"].has("extraction"):
			_state["job"]["extraction"]["status"] = "paused"
			_state["job"]["extraction"]["pause_reason"] = "restart"
		_inventory.refresh_payload_loads()
	return decoded


func _decode(record: Dictionary, tick: int) -> ServiceResult:
	var fields: Array = ["schema_version", "catalog_revision", "catalog_fingerprint", "timebase_hz", "last_tick", "state_revision", "deposits", "store", "vessel", "wall_mass_milligrams", "energy_joules", "powered", "job", "receipts"]
	if ControlContractValidation.is_integer(record.get("schema_version"), 2, 6):
		fields.append("cargo")
	if ControlContractValidation.is_integer(record.get("schema_version"), 3, 6):
		fields.append("structures")
	if ControlContractValidation.is_integer(record.get("schema_version"), 4, 6): fields.append("loose_parts")
	if ControlContractValidation.is_integer(record.get("schema_version"), 6, 6): fields.append("machinery")
	if _catalog.is_empty() or not _fields(record, fields):
		return _failure("An exact configured production snapshot is required.")
	if record["catalog_fingerprint"] != _catalog_fingerprint:
		return _failure("The saved catalog differs; an explicit production migration is required.")
	if not ControlContractValidation.is_integer(record["schema_version"], 1, 6) or not ControlContractValidation.is_integer(record["catalog_revision"], 1, 1):
		return _failure("Unsupported production/catalog version.")
	if not ControlContractValidation.is_integer(record["last_tick"], tick, tick) or not ControlContractValidation.is_integer(record["timebase_hz"], Engine.physics_ticks_per_second, Engine.physics_ticks_per_second) or not [60, 72, 90].has(Engine.physics_ticks_per_second):
		return _failure("Production tick and supported timebase must match the world.")
	for field in ["state_revision", "wall_mass_milligrams", "energy_joules"]:
		var limit: int = MAX_REVISION if field == "state_revision" else (100000 if field == "energy_joules" else MAX_MASS)
		if not ControlContractValidation.is_integer(record[field], 0, limit):
			return _failure("Production quantities exceed bounds.")
	if int(record["wall_mass_milligrams"]) % 1000000 != 0:
		return _failure("Constructed walls must contain whole blueprint segments.")
	if typeof(record.get("loose_parts", {})) != TYPE_DICTIONARY: return _failure("Loose parts require an object.")
	var normalized: Dictionary = record.duplicate(true)
	normalized["loose_parts"] = record.get("loose_parts", {}).duplicate(true)
	for field in ["schema_version", "catalog_revision", "timebase_hz", "last_tick", "state_revision", "wall_mass_milligrams", "energy_joules"]:
		normalized[field] = int(record[field])
	normalized["schema_version"] = 6
	normalized["machinery"] = record.get("machinery", MachineryWorkshop.initial()).duplicate(true)
	if not MachineryWorkshop.validate(normalized["machinery"]): return _failure("Malformed machinery record.")
	for job in normalized["machinery"]["jobs"].values():
		var spec: Dictionary = machine_recipe(job["recipe"])
		if spec.is_empty() or int(job["progress"]) >= int(spec["duration_ticks"]) or int(job["energy_spent"]) != int(job["progress"]) * int(spec["energy_joules"]) / int(spec["duration_ticks"]): return _failure("Invalid machine recipe progress or energy.")
	var structures: Variant = record.get("structures", {})
	if typeof(structures) != TYPE_DICTIONARY or structures.size() > 32:
		return _failure("Structural equipment records must be bounded.")
	normalized["structures"] = {}
	var structural_mass: int = MachineryWorkshop.mass(normalized["machinery"])
	if typeof(record.get("loose_parts", {})) != TYPE_DICTIONARY or normalized["loose_parts"].size() > 128: return _failure("Loose parts must be a bounded material map.")
	for id in normalized["loose_parts"]:
		if not ControlContractValidation.is_id(id) or not _stock_valid(normalized["loose_parts"][id]): return _failure("Invalid loose part materials.")
		for material in normalized["loose_parts"][id]: normalized["loose_parts"][id][material] = int(normalized["loose_parts"][id][material])
		structural_mass += _mass(normalized["loose_parts"][id])
	for id in structures:
		if not ControlContractValidation.is_id(id):
			return _failure("Equipment identity is invalid.")
		var structure: ServiceResult = _blueprints.validate_structure(structures[id], int(record["schema_version"]) >= 4)
		if not structure.is_success:
			return structure
		if not structure.value["materials"].is_empty() and not _stock_valid(structure.value["materials"]): return _failure("Structure contains unknown or excessive materials.")
		normalized["structures"][id] = structure.value
		structural_mass += _mass(structure.value["materials"])
	var saved_cargo: Variant = record.get("cargo", {})
	if typeof(saved_cargo) != TYPE_DICTIONARY or saved_cargo.size() > 32:
		return _failure("Cargo component records must be bounded.")
	normalized["cargo"] = saved_cargo.duplicate(true)
	var carried_mass: int = 0
	for id in normalized["cargo"]:
		if not ControlContractValidation.is_id(id) or not _stock_valid(normalized["cargo"][id], true) or not _cargo_valid(normalized["cargo"][id]):
			return _failure("Invalid portable payload identity, contents or pressure.")
		for material in normalized["cargo"][id]:
			normalized["cargo"][id][material] = int(normalized["cargo"][id][material])
		carried_mass += _mass(normalized["cargo"][id])
	for field in ["store", "vessel"]:
		if not _stock_valid(record[field], true):
			return _failure("Storage must contain exact known bounded material quantities.")
		for material in record[field]:
			normalized[field][material] = int(record[field][material])
	for material in _catalog["materials"]:
		if not _catalog["dispensable"].has(material) and int(normalized["vessel"][material]) != 0:
			return _failure("The chemical vessel cannot contain non-dispensable solids.")
	if typeof(record["deposits"]) != TYPE_DICTIONARY or not _fields(record["deposits"], _catalog["deposits"].keys()) or typeof(record["powered"]) != TYPE_DICTIONARY or not _fields(record["powered"], STATIONS):
		return _failure("Deposits and stations must match their trusted registry.")
	for id in record["deposits"]:
		if not ControlContractValidation.is_integer(record["deposits"][id], 0, int(_catalog["deposits"][id]["mass_milligrams"])):
			return _failure("Deposit mass is invalid.")
		normalized["deposits"][id] = int(record["deposits"][id])
	for id in STATIONS:
		if typeof(record["powered"][id]) != TYPE_BOOL:
			return _failure("Station power must be boolean.")
	if typeof(record["job"]) != TYPE_DICTIONARY:
		return _failure("The reserved batch must be an object.")
	if not record["job"].is_empty():
		var job: Dictionary = record["job"]
		var job_fields: Array = ["recipe_id", "deposit_id", "station", "inputs", "outputs", "remaining_ticks"]
		if job.has("extraction"):
			job_fields.append("extraction")
			if int(record["schema_version"]) < 5 or not ToolExtractionWork.valid(job["extraction"]) or job["extraction"]["deposit_id"] != job["deposit_id"]: return _failure("Invalid sustained extraction binding.")
		if not _fields(job, job_fields) or not _stock_valid(job["inputs"]) or not _stock_valid(job["outputs"]):
			return _failure("A bounded reserved batch is required.")
		var expected: Dictionary
		if typeof(job["deposit_id"]) == TYPE_STRING and _catalog["deposits"].has(job["deposit_id"]) and job["recipe_id"] == "":
			var material: String = _catalog["deposits"][job["deposit_id"]]["material"]
			var mass: int = int(job["extraction"]["remaining_cycles"]) * ToolExtractionWork.CYCLE_MASS if job.has("extraction") else 1000000
			expected = {"station": "drill", "inputs": {material: mass}, "outputs": {material: mass}, "duration_ticks": 60}
		elif job["deposit_id"] == "" and typeof(job["recipe_id"]) == TYPE_STRING and _catalog["recipes"].has(job["recipe_id"]):
			expected = _catalog["recipes"][job["recipe_id"]]
		else:
			return _failure("Unknown batch recipe or deposit.")
		if job["station"] != expected["station"] or not _same_stock(job["inputs"], expected["inputs"]) or not _same_stock(job["outputs"], expected["outputs"]) or not ControlContractValidation.is_integer(job["remaining_ticks"], 1, int(expected["duration_ticks"])):
			return _failure("Reserved batch must match its pinned recipe.")
		normalized["job"]["remaining_ticks"] = int(job["remaining_ticks"])
		for field in ["inputs", "outputs"]:
			for material in normalized["job"][field]:
				normalized["job"][field][material] = int(job[field][material])
	if _mass(normalized["store"]) + _reserved_mass(normalized) > MAX_MASS or _mass(normalized["vessel"]) > VESSEL_CAPACITY or _vessel_pressure(normalized["vessel"]) > MAX_VESSEL_PRESSURE_KPA:
		return _failure("Reserved output or vessel exceeds capacity.")
	var total: int = _mass(normalized["deposits"]) + _mass(normalized["store"]) + _mass(normalized["vessel"]) + int(normalized["wall_mass_milligrams"]) + _reserved_mass(normalized) + carried_mass + structural_mass
	if total != _mass(_initial_deposits()):
		return _failure("Closed fixture material mass must be conserved, including reserved batches.")
	if typeof(record["receipts"]) != TYPE_ARRAY or record["receipts"].size() > MAX_RECEIPTS:
		return _failure("Receipt history exceeds its bound.")
	var ids: Dictionary = {}
	var previous_revision: int = 0
	var previous_tick: int = 0
	for receipt in normalized["receipts"]:
		if typeof(receipt) != TYPE_DICTIONARY or not _fields(receipt, ["request_id", "fingerprint", "state_revision", "tick_number"]) or not ControlContractValidation.is_id(receipt.get("request_id")) or ids.has(receipt["request_id"]) or typeof(receipt.get("fingerprint")) != TYPE_STRING or receipt["fingerprint"].length() != 64 or not receipt["fingerprint"].is_valid_hex_number(false):
			return _failure("Receipts require unique bounded identities and fingerprints.")
		if not ControlContractValidation.is_integer(receipt["state_revision"], previous_revision + 1, int(normalized["state_revision"])) or not ControlContractValidation.is_integer(receipt["tick_number"], maxi(1, previous_tick), tick):
			return _failure("Receipt revisions/ticks must be ordered within the snapshot.")
		previous_revision = int(receipt["state_revision"])
		previous_tick = int(receipt["tick_number"])
		receipt["state_revision"] = previous_revision
		receipt["tick_number"] = previous_tick
		ids[receipt["request_id"]] = true
	if int(normalized["state_revision"]) == 0:
		var initial: Dictionary = initial_record(tick)
		if normalized != initial:
			return _failure("Revision-zero production must retain its initial finite fixture state.")
	elif normalized["receipts"].is_empty():
		return _failure("Changed production must retain at least one initiating command receipt.")
	return ServiceResult.success(normalized)


func _validate_catalog(record: Dictionary) -> ServiceResult:
	if not _fields(record, ["schema_version", "materials", "dispensable", "deposits", "recipes"]) or not ControlContractValidation.is_integer(record.get("schema_version"), 1, 1) or not ControlContractValidation.decode_ids(record["materials"], 1, 32).is_success or not ControlContractValidation.decode_ids(record["dispensable"], 1, 16).is_success or typeof(record["deposits"]) != TYPE_DICTIONARY or typeof(record["recipes"]) != TYPE_DICTIONARY or record["deposits"].size() > 16 or record["recipes"].size() > 32:
		return _failure("A bounded trusted production catalog is required.")
	_catalog = record
	for id in record["dispensable"]:
		if not record["materials"].has(id):
			return _failure("Dispensable chemicals must be registered materials.")
	for id in ["water", "nutrient-solution", "hydrogen", "oxygen", "plate"]:
		if not record["materials"].has(id):
			return _failure("The fixture vessel and construction blueprint require their registered materials.")
	var total: int = 0
	for id in record["deposits"]:
		var deposit: Variant = record["deposits"][id]
		if not ControlContractValidation.is_id(id) or typeof(deposit) != TYPE_DICTIONARY or not _fields(deposit, ["material", "mass_milligrams"]) or not record["materials"].has(deposit["material"]) or not ControlContractValidation.is_integer(deposit["mass_milligrams"], 1000000, MAX_MASS):
			return _failure("Deposits must declare a known material and finite mass.")
		total += int(deposit["mass_milligrams"])
	if total > MAX_MASS:
		return _failure("The closed fixture exceeds its material budget.")
	for id in record["recipes"]:
		var recipe: Variant = record["recipes"][id]
		if not ControlContractValidation.is_id(id) or typeof(recipe) != TYPE_DICTIONARY or not _fields(recipe, ["station", "inputs", "outputs", "duration_ticks", "energy_joules"]) or not STATIONS.has(recipe["station"]) or not _stock_valid(recipe["inputs"]) or not _stock_valid(recipe["outputs"]) or _mass(recipe["inputs"]) != _mass(recipe["outputs"]) or not ControlContractValidation.is_integer(recipe["duration_ticks"], 1, 36000) or not ControlContractValidation.is_integer(recipe["energy_joules"], 1, 100000):
			return _failure("Recipes require known materials, conserved mass, finite energy and duration.")
	return ServiceResult.success()


func _stock_valid(value: Variant, complete: bool = false) -> bool:
	if typeof(value) != TYPE_DICTIONARY or value.size() > 32 or (complete and not _fields(value, _catalog["materials"])) or (not complete and value.is_empty()):
		return false
	for material in value:
		if not _catalog["materials"].has(material) or not ControlContractValidation.is_integer(value[material], 0 if complete else 1, MAX_MASS):
			return false
	return _mass(value) <= MAX_MASS


func _cargo_valid(stock: Dictionary) -> bool:
	var kinds: int = 0
	for quantity in stock.values():
		if int(quantity) > 0:
			kinds += 1
	return kinds <= 1 and _mass(stock) <= VESSEL_CAPACITY and _vessel_pressure(stock) <= MAX_VESSEL_PRESSURE_KPA


static func _mass(stock: Dictionary) -> int:
	var total: int = 0
	for value in stock.values():
		total += int(value)
	return total


static func _same_stock(actual: Dictionary, expected: Dictionary) -> bool:
	if not _fields(actual, expected.keys()):
		return false
	for material in expected:
		if int(actual[material]) != int(expected[material]):
			return false
	return true


## Isothermal ideal gas in a sealed 2 L vessel, with liquid displacement.
## Chemistry and bulk storage are separate from the atmospheric network.
static func _vessel_pressure(stock: Dictionary) -> float:
	var gas_moles: float = float(stock["hydrogen"]) / 2016.0 + float(stock["oxygen"]) / 31998.0
	if gas_moles == 0.0:
		return 0.0
	var headspace_m3: float = 0.002 - float(int(stock["water"]) + int(stock["nutrient-solution"])) / 1000000000.0
	return INF if headspace_m3 <= 0.0 else gas_moles * 8.314462618 * 293.15 / headspace_m3 / 1000.0


static func _add(destination: Dictionary, amounts: Dictionary) -> void:
	for material in amounts:
		destination[material] += int(amounts[material])


static func _reserved_mass(state: Dictionary) -> int:
	return 0 if state["job"].is_empty() else _mass(state["job"]["outputs"])


static func _fields(record: Dictionary, fields: Array) -> bool:
	return ControlContractValidation.has_exact_fields(record, PackedStringArray(fields))


static func _failure(message: String) -> ServiceResult:
	return ServiceResult.failure(&"production_rejected", message)


func profiling_counters() -> Dictionary:
	if _state.is_empty():
		return {}
	return {"deployed_machines": _state["machinery"]["placements"].size(), "machine_parts": _state["machinery"]["parts"].size(), "grid_cables": _state["machinery"]["links"].size(), "machine_batches": _state["machinery"]["jobs"].size(), "active_batches": 0 if _state["job"].is_empty() else 1, "fabricated_equipment": _state["structures"].size(), "physical_tool_parts": _state["loose_parts"].size(), "stored_milligrams": _mass(_state["store"]), "vessel_milligrams": _mass(_state["vessel"]), "energy_joules": _state["energy_joules"], "receipts": _state["receipts"].size()}
