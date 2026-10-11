extends SimulationSystem
class_name ToolSimulationSystem

## Canonical condition/capability owner. Production still owns structural matter.
const SYSTEM_ID: StringName = &"tools"
var _catalog := ToolComponentCatalog.new()
var _bindings: Dictionary = {}
var _part_blueprints: Dictionary = {}
var _binding_fingerprint: String = ""
var _legacy_binding_fingerprint: String = ""
var _ledger: ToolAssemblyLedger
var _inventory: InventorySimulationSystem
var _last_tick: int = 0


func _init() -> void:
	system_id = SYSTEM_ID
	tick_priority = 250


func configure(inventory: InventorySimulationSystem) -> ServiceResult:
	if _inventory != null or inventory == null: return _failure("Configure one inventory owner.")
	var loaded: ServiceResult = _catalog.configure(JSON.parse_string(FileAccess.get_file_as_string("res://data/tools/catalog.v1.json")))
	if not loaded.is_success: return loaded
	var part_catalog: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/tools/part-blueprints.v1.json"))
	if typeof(part_catalog) != TYPE_DICTIONARY or not ToolComponentCatalog.exact(part_catalog, ["schema_version", "blueprints"]) or not ControlContractValidation.is_integer(part_catalog["schema_version"], 1, 1) or typeof(part_catalog["blueprints"]) != TYPE_DICTIONARY or part_catalog["blueprints"].size() > 32: return _failure("Invalid trusted part blueprints.")
	for id in part_catalog["blueprints"]:
		var blueprint: Variant = part_catalog["blueprints"][id]
		if not ControlContractValidation.is_id(id) or typeof(blueprint) != TYPE_DICTIONARY or not ToolComponentCatalog.exact(blueprint, ["definition_id", "material_id", "fabrication_energy_joules", "salvage_energy_joules"]) or not ControlContractValidation.is_id(blueprint["definition_id"]) or not ControlContractValidation.is_id(blueprint["material_id"]): return _failure("Invalid part blueprint identities.")
		for field in ["fabrication_energy_joules", "salvage_energy_joules"]:
			if not ControlContractValidation.is_integer(blueprint[field], 1, 100000): return _failure("Invalid part fabrication energy.")
		var part: ServiceResult = ToolPartState.create("blueprint-part", blueprint["definition_id"], blueprint["material_id"], _catalog)
		if not part.is_success: return part
	_part_blueprints = part_catalog["blueprints"].duplicate(true)
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/tools/inventory-bindings.v2.json"))
	if typeof(data) != TYPE_DICTIONARY or not ToolComponentCatalog.exact(data, ["schema_version", "bindings"]) or not ControlContractValidation.is_integer(data["schema_version"], 2, 2) or typeof(data["bindings"]) != TYPE_DICTIONARY or data["bindings"].size() > 64: return _failure("Invalid trusted inventory/tool bindings.")
	for id in data["bindings"]:
		var binding: Variant = data["bindings"][id]
		if not ControlContractValidation.is_id(id) or typeof(binding) != TYPE_DICTIONARY or not ToolComponentCatalog.exact(binding, ["profile_id", "parts"]) or not ControlContractValidation.is_id(binding["profile_id"]) or not _catalog.definition("tools", binding["profile_id"]).is_success or typeof(binding["parts"]) != TYPE_DICTIONARY or binding["parts"].size() > 16: return _failure("Invalid assembly binding.")
		if not inventory.factory_definition(id).is_success: return _failure("Binding requires a registered inventory definition.")
		var defaults: Dictionary = ToolAssemblyLedger.create_empty(_catalog).value.to_record()
		defaults["assemblies"][id] = {"definition_id": binding["profile_id"], "slots": {}}
		for slot in binding["parts"]:
			var spec: Variant = binding["parts"][slot]
			if not ControlContractValidation.is_id(slot) or typeof(spec) != TYPE_ARRAY or spec.size() != 2 or not ControlContractValidation.is_id(spec[0]) or not ControlContractValidation.is_id(spec[1]): return _failure("Invalid default component specification.")
			var part: ServiceResult = ToolPartState.create("default-" + slot, spec[0], spec[1], _catalog)
			if not part.is_success: return part
			defaults["parts"]["default-" + slot] = part.value.to_record()
			defaults["assemblies"][id]["slots"][slot] = "default-" + slot
		var assembled: ServiceResult = ToolAssemblyLedger.from_record(defaults, _catalog)
		if not assembled.is_success: return assembled
	var original: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/tools/inventory-bindings.v1.json"))["bindings"]
	for id in original:
		if data["bindings"].get(id) != original[id]: return _failure("Additive bindings must preserve all original tool profiles and components.")
	_legacy_binding_fingerprint = JSON.stringify(original, "", true, true).sha256_text()
	_bindings = data["bindings"].duplicate(true)
	_binding_fingerprint = JSON.stringify(_bindings, "", true, true).sha256_text()
	_inventory = inventory
	var seeded: ServiceResult = migrate_inventory(inventory.capture_snapshot().value["owner"], 0)
	if not seeded.is_success: return seeded
	_ledger = ToolAssemblyLedger.from_record(seeded.value["ledger"], _catalog).value
	return inventory.bind_tool_capability_provider(capability)


func migrate_inventory(owner: Dictionary, tick: int) -> ServiceResult:
	var validated: ServiceResult = _inventory.validate_payload_masses({}, owner)
	if not validated.is_success: return validated
	owner = validated.value.to_record()
	var seed: Dictionary = ToolAssemblyLedger.create_empty(_catalog).value.to_record()
	var synchronized: ServiceResult = _sync(seed, owner)
	return ServiceResult.success({"schema_version": 1, "bindings_fingerprint": _binding_fingerprint, "last_tick": tick, "ledger": synchronized.value.to_record()}) if synchronized.is_success else synchronized


func modular_inventory_definitions() -> Array:
	var ids: Array = []
	for id in _bindings:
		var definition: Dictionary = _inventory.factory_definition(id).value
		if int(definition["mass_milligrams"]) == 0 and definition["tags"].has("equipment.fabricated"): ids.append(id)
	return ids


func _sync(record: Dictionary, owner: Dictionary) -> ServiceResult:
	var candidate: Dictionary = record.duplicate(true)
	var tools: Dictionary = {}
	for item in owner["ledger"]["items"]:
		if not _bindings.has(item["definition_id"]): continue
		var id: String = item["item_id"]
		tools[id] = true
		var binding: Dictionary = _bindings[item["definition_id"]]
		if candidate["assemblies"].has(id):
			if candidate["assemblies"][id]["definition_id"] != binding["profile_id"]: return _failure("Item and assembly profile differ.")
			continue
		candidate["assemblies"][id] = {"definition_id": binding["profile_id"], "slots": {}}
		for slot in binding["parts"]:
			var spec: Array = binding["parts"][slot]
			var part_id: String = "tool-part-%s" % (id + ":" + slot).sha256_text().substr(0, 24)
			var created: ServiceResult = ToolPartState.create(part_id, spec[0], spec[1], _catalog)
			if not created.is_success: return created
			var part: Dictionary = created.value.to_record()
			part["integrity_ppm"] = int(item["condition_permille"]) * 1000
			candidate["parts"][part_id] = part
			candidate["assemblies"][id]["slots"][slot] = part_id
	for id in candidate["assemblies"].keys():
		if tools.has(id): continue
		for part_id in candidate["assemblies"][id]["slots"].values(): candidate["parts"].erase(part_id)
		candidate["assemblies"].erase(id)
	if candidate != record: candidate["state_revision"] += 1
	return ToolAssemblyLedger.from_record(candidate, _catalog)


func validate_inventory_links(record: Dictionary, owner: Dictionary, structures: Dictionary, loose_parts: Dictionary = {}) -> ServiceResult:
	var decoded: ServiceResult = validate_snapshot_record(record, int(record.get("last_tick", -1)))
	if not decoded.is_success: return decoded
	var ledger: ToolAssemblyLedger = ToolAssemblyLedger.from_record(record["ledger"], _catalog).value
	var ledger_record: Dictionary = ledger.to_record()
	var synchronized: ServiceResult = _sync(ledger_record, owner)
	if not synchronized.is_success or synchronized.value.to_record() != ledger_record: return _failure("Every registered tool must have exactly one saved component assembly.")
	var mounted: Dictionary = {}
	for item in owner["ledger"]["items"]:
		if not _bindings.has(item["definition_id"]): continue
		var stock: Dictionary = {}
		for part_id in ledger_record["assemblies"][item["item_id"]]["slots"].values():
			mounted[part_id] = true
			var quantities: Dictionary = ToolPartState.from_record(ledger_record["parts"][part_id], _catalog).value.material_stock()
			for material in quantities: stock[material] = int(stock.get(material, 0)) + int(quantities[material])
		if structures.has(item["item_id"]):
			if stock != structures[item["item_id"]]["materials"]: return _failure("Tool components must partition the conserved equipment bill of materials.")
		else:
			var mass: int = 0
			for amount in stock.values(): mass += int(amount)
			if mass != int(_inventory.factory_definition(item["definition_id"]).value["mass_milligrams"]): return _failure("Starter tool component mass must match its existing shell mass.")
	var loose: Dictionary = {}
	for item in owner["ledger"]["items"]:
		if item["definition_id"] != "item.tool-part.fabricated": continue
		var id: String = item["item_id"]
		if mounted.has(id) or not ledger_record["parts"].has(id) or not loose_parts.has(id): return _failure("Loose parts require unique physical identities and matter.")
		var stock: Dictionary = ToolPartState.from_record(ledger_record["parts"][id], _catalog).value.material_stock()
		if stock != loose_parts[id]: return _failure("Part material descriptor and payload differ.")
		loose[id] = true
	if loose.size() != loose_parts.size() or mounted.size() + loose.size() != ledger_record["parts"].size(): return _failure("Every part must be mounted or have one physical inventory item.")
	return ServiceResult.success()


func prepare_inventory(owner: Dictionary, structures: Dictionary, loose_parts: Dictionary = {}) -> ServiceResult:
	var synced: ServiceResult = _sync(_ledger.to_record(), owner)
	if not synced.is_success: return synced
	var record: Dictionary = capture_snapshot().value
	record["ledger"] = synced.value.to_record()
	var valid: ServiceResult = validate_inventory_links(record, owner, structures, loose_parts)
	return synced if valid.is_success else valid


func capability(item_id: String, tag: String) -> ServiceResult:
	if not _ledger.has_assembly(item_id): return ServiceResult.success(false)
	var actions: Dictionary = {"tool.extractor": "action.extract", "tool.crowbar": "action.pry", "tool.shovel": "action.excavate"}
	var observed: ServiceResult = _ledger.observation(item_id)
	if not actions.has(tag): return _failure("No component-backed handler is registered for this tool function.")
	return ServiceResult.success(observed.is_success and observed.value["actions"].get(actions[tag], {}).get("available", false))


func prepare_usage(item_id: String) -> ServiceResult:
	var plan: ServiceResult = _ledger.plan_work(item_id, "action.extract", 1, _ledger.revision())
	return ToolAssemblyLedger.from_record(plan.value["next_record"], _catalog) if plan.is_success else plan


## Pure component transaction; production settles stock/energy and physical item changes.
func prepare_part_change(context: AuthenticatedCommandContext, operation: String, payload: Dictionary, request_id: String) -> ServiceResult:
	if int(payload["expected_tool_revision"]) != _ledger.revision() or _ledger.revision() >= 9007199254740000: return _failure("Tool revision is stale or exhausted.")
	var own: ServiceResult = _inventory.own_inventory_observation(context)
	if not own.is_success: return own
	var owned: Dictionary = {}
	for item in own.value["items"]: owned[item["item_id"]] = item["definition_id"]
	var candidate: Dictionary = _ledger.to_record()
	var changes: Array = []
	var energy: int = 100
	var tool_id: String = ""
	var station: String = "construction"
	var debit: Dictionary = {}
	var credit: Dictionary = {}
	if operation == "fabricate_tool_part":
		if not _part_blueprints.has(payload["blueprint_id"]): return _failure("Select a registered part blueprint.")
		var blueprint: Dictionary = _part_blueprints[payload["blueprint_id"]]
		var id: String = "tool-part-%s" % request_id.sha256_text().substr(0, 24)
		if candidate["parts"].has(id): return _failure("Part identity already exists.")
		var part: ToolPartState = ToolPartState.create(id, blueprint["definition_id"], blueprint["material_id"], _catalog).value
		candidate["parts"][id] = part.to_record()
		changes.append({"item_id": id, "create": true})
		debit = part.material_stock()
		energy = blueprint["fabrication_energy_joules"]
		station = "printer"
	elif operation == "recycle_tool_part":
		var id: String = payload["part_id"]
		if owned.get(id) != "item.tool-part.fabricated" or not candidate["parts"].has(id): return _failure("Select an owned loose physical part.")
		credit = ToolPartState.from_record(candidate["parts"][id], _catalog).value.material_stock()
		var found_blueprint: bool = false
		for blueprint in _part_blueprints.values():
			if blueprint["definition_id"] == candidate["parts"][id]["definition_id"] and blueprint["material_id"] == candidate["parts"][id]["material_id"]:
				energy = int(blueprint["salvage_energy_joules"])
				found_blueprint = true
				break
		if not found_blueprint: return _failure("This part has no registered recycling specification.")
		candidate["parts"].erase(id)
		changes.append({"item_id": id, "create": false})
		station = "recycler"
	else:
		tool_id = payload["item_id"]
		if not modular_inventory_definitions().has(owned.get(tool_id)) or not candidate["assemblies"].has(tool_id): return _failure("Modify owned manufactured equipment; starter shells retain separate provenance.")
		var slot: String = payload["slot_id"]
		var assembly: Dictionary = candidate["assemblies"][tool_id]
		if not _catalog.definition("tools", assembly["definition_id"]).value["slots"].has(slot): return _failure("Select a registered mount.")
		var previous: String = assembly["slots"].get(slot, "")
		if operation == "detach_tool_part":
			if previous.is_empty(): return _failure("This mount is already empty.")
			assembly["slots"].erase(slot)
		else:
			var incoming: String = payload["part_id"]
			if owned.get(incoming) != "item.tool-part.fabricated" or not candidate["parts"].has(incoming): return _failure("Fit a loose physical part from your own inventory.")
			assembly["slots"][slot] = incoming
			changes.append({"item_id": incoming, "create": false})
		if not previous.is_empty(): changes.append({"item_id": previous, "create": true})
	candidate["state_revision"] += 1
	var prepared: ServiceResult = ToolAssemblyLedger.from_record(candidate, _catalog)
	if not prepared.is_success: return prepared
	return ServiceResult.success({"ledger": prepared.value, "changes": changes, "tool_id": tool_id, "station": station, "energy_joules": energy, "debit": debit, "credit": credit})


func part_stock(ledger: ToolAssemblyLedger, part_id: String) -> Dictionary:
	return ToolPartState.from_record(ledger.to_record()["parts"][part_id], _catalog).value.material_stock()


func assembly_stock(ledger: ToolAssemblyLedger, id: String) -> Dictionary:
	var record: Dictionary = ledger.to_record()
	var stock: Dictionary = {}
	for part_id in record["assemblies"][id]["slots"].values():
		var amounts: Dictionary = ToolPartState.from_record(record["parts"][part_id], _catalog).value.material_stock()
		for material in amounts: stock[material] = int(stock.get(material, 0)) + int(amounts[material])
	return stock


func prepare_repair(context: AuthenticatedCommandContext, part_id: String, amount: int, expected_revision: int) -> ServiceResult:
	var own: ServiceResult = _inventory.own_inventory_observation(context)
	if not own.is_success: return own
	var owned: bool = false
	var ledger_record: Dictionary = _ledger.to_record()
	for item in own.value["items"]:
		if item["item_id"] == part_id and item["definition_id"] == "item.tool-part.fabricated": owned = true
		if ledger_record["assemblies"].has(item["item_id"]) and ledger_record["assemblies"][item["item_id"]]["slots"].values().has(part_id): owned = true
	if not owned: return _failure("Only a component in your own tool can be maintained.")
	var plan: ServiceResult = _ledger.plan_repair(part_id, amount, expected_revision)
	if not plan.is_success: return plan
	return ServiceResult.success({"ledger": ToolAssemblyLedger.from_record(plan.value["next_record"], _catalog).value, "energy_joules": plan.value["energy_joules"]})


## Receives only previously validated domain objects from synchronous owner transactions.
func commit_prepared(ledger: ToolAssemblyLedger) -> void:
	_ledger = ledger


func observation(context: AuthenticatedCommandContext) -> ServiceResult:
	var own: ServiceResult = _inventory.own_inventory_observation(context)
	if not own.is_success: return own
	var assemblies: Array = []
	var loose: Array = []
	var ledger_record: Dictionary = _ledger.to_record()
	for item in own.value["items"]:
		if item["definition_id"] == "item.tool-part.fabricated":
			loose.append(_part_view(ledger_record["parts"][item["item_id"]]))
		if not _ledger.has_assembly(item["item_id"]): continue
		var observed: Dictionary = _ledger.observation(item["item_id"]).value
		observed["slots"] = {}
		var assembly: Dictionary = ledger_record["assemblies"][item["item_id"]]
		for slot in _catalog.definition("tools", assembly["definition_id"]).value["slots"]:
			observed["slots"][slot] = assembly["slots"].get(slot, "")
		for index in range(observed["parts"].size()): observed["parts"][index] = _part_view(observed["parts"][index])
		assemblies.append(observed)
	var maintenance: Dictionary = {}
	for assembly in assemblies:
		for part in assembly["parts"]:
			maintenance[part["part_id"]] = _maintenance_quote(ledger_record["parts"][part["part_id"]])
	for part in loose:
		maintenance[part["part_id"]] = _maintenance_quote(ledger_record["parts"][part["part_id"]])
	var blueprints: Dictionary = {}
	for id in _part_blueprints:
		var blueprint: Dictionary = _part_blueprints[id].duplicate(true)
		var part: ToolPartState = ToolPartState.create("view-part", blueprint["definition_id"], blueprint["material_id"], _catalog).value
		blueprint["materials"] = part.material_stock()
		blueprint["name"] = _catalog.definition("components", blueprint["definition_id"]).value["name"] + " · " + _catalog.definition("materials", blueprint["material_id"]).value["name"]
		blueprints[id] = blueprint
	return ServiceResult.success({"schema_version": 3, "state_revision": _ledger.revision(), "assemblies": assemblies, "loose_parts": loose, "part_blueprints": blueprints, "maintenance": maintenance})


## Detached quote from the same bounded part planner used by paid repair.
## No adoption, payment, capability prediction or persistent-state mutation.
func _maintenance_quote(record: Dictionary) -> Dictionary:
	var part: ToolPartState = ToolPartState.from_record(record, _catalog).value
	var plan: ServiceResult = part.plan_repair(1000000)
	return {
		"amount_ppm": 1000000,
		"restored_ppm": 1000000 - int(record["integrity_ppm"]),
		"energy_joules": int(plan.value["energy_joules"]) if plan.is_success else 0,
		"materials": {}
	}


func _part_view(part: Dictionary) -> Dictionary:
	var view: Dictionary = part.duplicate(true)
	view["name"] = _catalog.definition("components", part["definition_id"]).value["name"]
	view["material_name"] = _catalog.definition("materials", part["material_id"]).value["name"]
	return view


func simulate_tick(tick: int, _delta: float) -> void:
	_last_tick = tick # Routine wear is applied by completed work commands, never here.


func capture_snapshot() -> ServiceResult:
	return ServiceResult.success({"schema_version": 1, "bindings_fingerprint": _binding_fingerprint, "last_tick": _last_tick, "ledger": _ledger.to_record()})


func validate_snapshot_record(record: Dictionary, tick: int) -> ServiceResult:
	if not ToolComponentCatalog.exact(record, ["schema_version", "bindings_fingerprint", "last_tick", "ledger"]) or not ControlContractValidation.is_integer(record.get("schema_version"), 1, 1) or record.get("bindings_fingerprint") not in [_binding_fingerprint, _legacy_binding_fingerprint] or not ControlContractValidation.is_integer(record.get("last_tick"), tick, tick): return _failure("Tool snapshot layout, catalog or tick differs.")
	if typeof(record.get("ledger")) != TYPE_DICTIONARY: return _failure("Tool snapshot requires a ledger object.")
	var ledger: ServiceResult = ToolAssemblyLedger.from_record(record["ledger"], _catalog)
	return ServiceResult.success({"schema_version": 1, "bindings_fingerprint": _binding_fingerprint, "last_tick": tick, "ledger": ledger.value.to_record()}) if ledger.is_success else ledger


func restore_snapshot_record(record: Dictionary, tick: int) -> ServiceResult:
	var valid: ServiceResult = validate_snapshot_record(record, tick)
	if valid.is_success:
		_ledger = ToolAssemblyLedger.from_record(valid.value["ledger"], _catalog).value
		_last_tick = tick
	return valid


func profiling_counters() -> Dictionary:
	var record: Dictionary = _ledger.to_record()
	return {"assemblies": record["assemblies"].size(), "parts": record["parts"].size()}


static func _failure(message: String) -> ServiceResult:
	return ServiceResult.failure(&"tool_runtime_rejected", message)
