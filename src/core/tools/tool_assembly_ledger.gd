extends RefCounted
class_name ToolAssemblyLedger

## Detached transactional model. Parts have one mounting owner or remain loose.
const MAX_PARTS: int = 512
const MAX_ASSEMBLIES: int = 64
var _catalog: ToolComponentCatalog
var _record: Dictionary = {}


static func create_empty(catalog: ToolComponentCatalog) -> ServiceResult:
	if catalog == null or catalog.fingerprint.is_empty(): return ToolComponentCatalog.failure("Configure the trusted catalog first.")
	return from_record({"schema_version": 1, "catalog_fingerprint": catalog.fingerprint, "state_revision": 0, "parts": {}, "assemblies": {}}, catalog)


static func from_record(value: Variant, catalog: ToolComponentCatalog) -> ServiceResult:
	if catalog == null or typeof(value) != TYPE_DICTIONARY or not ToolComponentCatalog.exact(value, ["schema_version", "catalog_fingerprint", "state_revision", "parts", "assemblies"]) or not ControlContractValidation.is_integer(value["schema_version"], 1, 1) or value["catalog_fingerprint"] != catalog.fingerprint or not ControlContractValidation.is_integer(value["state_revision"], 0, 9007199254740000): return ToolComponentCatalog.failure("Invalid assembly ledger/catalog revision.")
	if typeof(value["parts"]) != TYPE_DICTIONARY or value["parts"].size() > MAX_PARTS or typeof(value["assemblies"]) != TYPE_DICTIONARY or value["assemblies"].size() > MAX_ASSEMBLIES: return ToolComponentCatalog.failure("Assembly/part registry exceeds its bounds.")
	var normalized: Dictionary = value.duplicate(true)
	normalized["schema_version"] = 1
	normalized["state_revision"] = int(value["state_revision"])
	for id in value["parts"]:
		var part: ServiceResult = ToolPartState.from_record(value["parts"][id], catalog)
		if not ControlContractValidation.is_id(id) or not part.is_success or part.value.to_record()["part_id"] != id: return ToolComponentCatalog.failure("Invalid registry part identity.")
		normalized["parts"][id] = part.value.to_record()
	var fitted: Dictionary = {}
	for id in value["assemblies"]:
		var assembly: Variant = value["assemblies"][id]
		if not ControlContractValidation.is_id(id) or typeof(assembly) != TYPE_DICTIONARY or not ToolComponentCatalog.exact(assembly, ["definition_id", "slots"]) or not ControlContractValidation.is_id(assembly["definition_id"]) or typeof(assembly["slots"]) != TYPE_DICTIONARY or assembly["slots"].size() > 16: return ToolComponentCatalog.failure("Invalid assembly identity or slot record.")
		var definition: ServiceResult = catalog.definition("tools", assembly["definition_id"])
		if not definition.is_success: return definition
		for slot in assembly["slots"]:
			var part_id: Variant = assembly["slots"][slot]
			if not definition.value["slots"].has(slot) or not ControlContractValidation.is_id(part_id) or not normalized["parts"].has(part_id) or fitted.has(part_id): return ToolComponentCatalog.failure("Parts must exist and mount at most once.")
			var part_definition: Dictionary = catalog.definition("components", normalized["parts"][part_id]["definition_id"]).value
			var compatible: bool = false
			for interface_id in definition.value["slots"][slot]["mount_interfaces"]:
				compatible = compatible or part_definition["mount_interfaces"].has(interface_id)
			if not compatible: return ToolComponentCatalog.failure("The part does not fit the physical mount.")
			fitted[part_id] = true
	var ledger := ToolAssemblyLedger.new()
	ledger._record = normalized
	ledger._catalog = catalog
	return ServiceResult.success(ledger)


func to_record() -> Dictionary:
	return _record.duplicate(true)


## Count each standalone part once, irrespective of mounting or detached location.
func material_stock() -> Dictionary:
	var stock: Dictionary = {}
	for value in _record["parts"].values():
		var amounts: Dictionary = ToolPartState.from_record(value, _catalog).value.material_stock()
		for material in amounts:
			stock[material] = int(stock.get(material, 0)) + int(amounts[material])
	return stock


func observation(id: String) -> ServiceResult:
	if not _record["assemblies"].has(id): return ToolComponentCatalog.failure("Unknown assembly.")
	var assembly: Dictionary = _record["assemblies"][id]
	var functions: Dictionary = {}
	var parts: Array = []
	var grants: Dictionary = {}
	for part_id in assembly["slots"].values():
		var part: ToolPartState = ToolPartState.from_record(_record["parts"][part_id], _catalog).value
		parts.append(part.to_record())
		if part.operational():
			var definition: Dictionary = _catalog.definition("components", part.to_record()["definition_id"]).value
			for function_id in definition["functions"]:
				if not grants.has(function_id): grants[function_id] = []
				grants[function_id].append(definition["functions"][function_id])
	# Bounded dependency closure; circular grants cannot create capabilities from nothing.
	for _pass in range(grants.size()):
		var changed: bool = false
		for function_id in grants:
			if functions.has(function_id): continue
			for requirements in grants[function_id]:
				var available: bool = true
				for requirement in requirements: available = available and functions.has(requirement)
				if available:
					functions[function_id] = true
					changed = true
		if not changed: break
	var actions: Dictionary = {}
	for action in _catalog.definition("tools", assembly["definition_id"]).value["actions"]:
		var missing: Array = []
		for requirement in _catalog.definition("tools", assembly["definition_id"]).value["actions"][action]:
			if not functions.has(requirement): missing.append(requirement)
		actions[action] = {"available": missing.is_empty(), "missing_functions": missing}
	return ServiceResult.success({"assembly_id": id, "functions": functions.keys(), "actions": actions, "parts": parts})


## Replacement detaches the old part intact; never deletes it to make the new one fit.
func plan_fit(assembly_id: String, slot_id: String, part_id: String, expected_revision: int) -> ServiceResult:
	if not _record["assemblies"].has(assembly_id) or not _record["parts"].has(part_id): return ToolComponentCatalog.failure("Unknown assembly or part.")
	for assembly in _record["assemblies"].values():
		if assembly["slots"].values().has(part_id): return ToolComponentCatalog.failure("Detach a fitted part before moving it.")
	var candidate: Dictionary = to_record()
	candidate["assemblies"][assembly_id]["slots"][slot_id] = part_id
	return _plan(candidate, expected_revision)


## Manufacture/ownership and material debit must be settled by the containing system.
func plan_register_part(part: ToolPartState, expected_revision: int) -> ServiceResult:
	if part == null or _record["parts"].size() >= MAX_PARTS: return ToolComponentCatalog.failure("The part registry is unavailable or full.")
	var record: Dictionary = part.to_record()
	if _record["parts"].has(record["part_id"]): return ToolComponentCatalog.failure("That part already exists.")
	var candidate: Dictionary = to_record()
	candidate["parts"][record["part_id"]] = record
	return _plan(candidate, expected_revision)


func plan_register_assembly(id: String, definition_id: String, expected_revision: int) -> ServiceResult:
	if not ControlContractValidation.is_id(id) or _record["assemblies"].has(id) or _record["assemblies"].size() >= MAX_ASSEMBLIES: return ToolComponentCatalog.failure("Assembly identity already exists or exceeds bounds.")
	var candidate: Dictionary = to_record()
	candidate["assemblies"][id] = {"definition_id": definition_id, "slots": {}}
	return _plan(candidate, expected_revision)


func plan_detach(assembly_id: String, slot_id: String, expected_revision: int) -> ServiceResult:
	if not _record["assemblies"].has(assembly_id) or not _record["assemblies"][assembly_id]["slots"].has(slot_id): return ToolComponentCatalog.failure("No fitted part exists in this slot.")
	var candidate: Dictionary = to_record()
	candidate["assemblies"][assembly_id]["slots"].erase(slot_id)
	return _plan(candidate, expected_revision)


func plan_work(assembly_id: String, action_id: String, cycles: int, expected_revision: int) -> ServiceResult:
	var observed: ServiceResult = observation(assembly_id)
	if not observed.is_success or not observed.value["actions"].has(action_id) or not observed.value["actions"][action_id]["available"]: return ToolComponentCatalog.failure("The fitted assembly cannot perform that action.")
	# Wear is monotonic; checking both endpoints prevents crossing a disabled threshold.
	if cycles < 1 or cycles > 10000: return ToolComponentCatalog.failure("Work cycle count exceeds its bound.")
	var candidate: Dictionary = to_record()
	for part_id in candidate["assemblies"][assembly_id]["slots"].values():
		var part: ToolPartState = ToolPartState.from_record(candidate["parts"][part_id], _catalog).value
		var worn: ServiceResult = part.plan_usage(cycles)
		if not worn.is_success: return worn
		candidate["parts"][part_id] = worn.value
	var plan: ServiceResult = _plan(candidate, expected_revision)
	if not plan.is_success: return plan
	var next: ToolAssemblyLedger = from_record(plan.value["next_record"], _catalog).value
	if not next.observation(assembly_id).value["actions"][action_id]["available"]: return ToolComponentCatalog.failure("Use a smaller work batch before a required part fails.")
	return plan


func plan_repair(part_id: String, amount_ppm: int, expected_revision: int) -> ServiceResult:
	if not _record["parts"].has(part_id): return ToolComponentCatalog.failure("Unknown standalone part.")
	var part: ToolPartState = ToolPartState.from_record(_record["parts"][part_id], _catalog).value
	var repaired: ServiceResult = part.plan_repair(amount_ppm)
	if not repaired.is_success: return repaired
	var candidate: Dictionary = to_record()
	candidate["parts"][part_id] = repaired.value["part"]
	return _plan(candidate, expected_revision, repaired.value["energy_joules"])


func plan_damage(part_id: String, amount_ppm: int, expected_revision: int) -> ServiceResult:
	if not _record["parts"].has(part_id): return ToolComponentCatalog.failure("Unknown component.")
	var part: ToolPartState = ToolPartState.from_record(_record["parts"][part_id], _catalog).value
	var damaged: ServiceResult = part.plan_damage(amount_ppm)
	if not damaged.is_success: return damaged
	var candidate: Dictionary = to_record()
	candidate["parts"][part_id] = damaged.value
	return _plan(candidate, expected_revision)


## Trusted owning system only; callers must settle inventory, matter and energy first.
func adopt_prepared(record: Dictionary) -> ServiceResult:
	if not ControlContractValidation.is_integer(record.get("state_revision"), int(_record["state_revision"]) + 1, int(_record["state_revision"]) + 1): return ToolComponentCatalog.failure("Prepared ledger revision is stale.")
	var valid: ServiceResult = from_record(record, _catalog)
	if valid.is_success: _record = valid.value.to_record()
	return valid


func _plan(candidate: Dictionary, expected_revision: int, energy: int = 0) -> ServiceResult:
	if expected_revision != int(_record["state_revision"]) or expected_revision >= 9007199254740000: return ToolComponentCatalog.failure("Assembly revision is stale or exhausted.")
	candidate["state_revision"] += 1
	var valid: ServiceResult = from_record(candidate, _catalog)
	return ServiceResult.success({"expected_revision": expected_revision, "next_record": valid.value.to_record(), "energy_joules": energy}) if valid.is_success else valid
