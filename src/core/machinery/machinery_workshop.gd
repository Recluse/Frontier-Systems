extends RefCounted
class_name MachineryWorkshop

## Composition and grid policy. Production owns this record and its conserved matter.
## Inventory owns physical parentage; removing a fitted part removes its capability.
static var KINDS: Dictionary = _load_catalog()
static var LEGACY_KINDS: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/machinery/catalog.v1.json"))["parts"]
static var _requirements: Dictionary = {}
const CAPACITY: int = 20000
const GENERATION_WATTS: int = 1000
const CABLE_WATTS: int = 2000
const MAX_CABLE_LENGTH: int = 5000


static func initial() -> Dictionary:
	return {"schema_version": 1, "catalog_fingerprint": JSON.stringify(KINDS, "", true).sha256_text(), "parts": {}, "mounts": {}, "placements": {}, "links": {}, "jobs": {}}


static func definition(kind: String) -> String:
	return "item.machine.%s" % kind


static func root_id(id: String) -> String:
	return "machine-root-%s" % id.sha256_text().substr(0, 24)


static func item(owner: Dictionary, id: String) -> Dictionary:
	for entry in owner["ledger"]["items"]:
		if entry["item_id"] == id: return entry
	return {}


static func container(owner: Dictionary, id: String) -> String:
	for entry in owner["ledger"]["containers"]:
		if entry["owner_item_id"] == id: return entry["container_id"]
	return ""


## Physical fitting includes broken mounts; functional callers keep the default filter.
static func modules(state: Dictionary, owner: Dictionary, id: String, include_broken: bool = false) -> Dictionary:
	var result: Dictionary = {}
	var storage: String = container(owner, id)
	if storage.is_empty(): return result
	for entry in owner["ledger"]["items"]:
		if entry["container_id"] != storage or state["mounts"].get(entry["item_id"]) != id or not state["parts"].has(entry["item_id"]) or (not include_broken and int(entry["condition_permille"]) == 0): continue
		var kind: String = state["parts"][entry["item_id"]]["kind"]
		if not result.has(kind): result[kind] = []
		result[kind].append(entry["item_id"])
	return result


static func carriers(state: Dictionary, owner: Dictionary, id: String) -> Array:
	var result: Array = []
	for socket in modules(state, owner, id).get("socket", []):
		var storage: String = container(owner, socket)
		for entry in owner["ledger"]["items"]:
			if entry["container_id"] == storage and entry["definition_id"] in ["item.resource-canister.prototype", "item.resource-canister.fabricated"]: result.append(entry["item_id"])
	result.sort()
	return result


static func deployed(state: Dictionary, owner: Dictionary, id: String) -> bool:
	var physical: Dictionary = item(owner, id)
	return state["placements"].has(id) and not physical.is_empty() and physical["container_id"] == root_id(id)


static func operational(state: Dictionary, owner: Dictionary, id: String, capability: String) -> bool:
	if not deployed(state, owner, id) or not state["placements"][id]["enabled"]: return false
	if int(item(owner, id)["condition_permille"]) == 0: return false
	var fitted: Dictionary = modules(state, owner, id)
	if not KINDS.has(capability): return false
	if not _requirements.has(capability):
		var requirement := MachineFunctionRequirement.new()
		requirement.function_id = "machine.%s" % capability
		requirement.required_component_capabilities = PackedStringArray(["power", "controller", capability])
		_requirements[capability] = requirement
	return _requirements[capability].evaluate(PackedStringArray(fitted.keys())).value["available"]


static func mass(state: Dictionary) -> int:
	var total: int = 0
	for part in state["parts"].values(): total += int(KINDS[part["kind"]])
	return total


static func validate(value: Variant, owner: Dictionary = {}) -> bool:
	if typeof(value) != TYPE_DICTIONARY or not ControlContractValidation.has_exact_fields(value, PackedStringArray(["schema_version", "catalog_fingerprint", "parts", "mounts", "placements", "links", "jobs"])) or not ControlContractValidation.is_integer(value["schema_version"], 1, 1): return false
	var legacy: bool = value["catalog_fingerprint"] == JSON.stringify(LEGACY_KINDS, "", true).sha256_text()
	if not legacy and value["catalog_fingerprint"] != JSON.stringify(KINDS, "", true).sha256_text(): return false
	for field in ["parts", "mounts", "placements", "links", "jobs"]:
		if typeof(value[field]) != TYPE_DICTIONARY or value[field].size() > (128 if field in ["parts", "mounts"] else (24 if field == "links" else 20)): return false
	for id in value["parts"]:
		var part: Variant = value["parts"][id]
		if legacy and typeof(part) == TYPE_DICTIONARY and not LEGACY_KINDS.has(part.get("kind")): return false
		if not ControlContractValidation.is_id(id) or typeof(part) != TYPE_DICTIONARY or not ControlContractValidation.has_exact_fields(part, PackedStringArray(["kind"])) or not KINDS.has(part.get("kind")): return false
		if not owner.is_empty():
			var physical: Dictionary = item(owner, id)
			if physical.is_empty() or physical["definition_id"] != definition(part["kind"]): return false
	for id in value["mounts"]:
		var host: Variant = value["mounts"][id]
		if not value["parts"].has(id) or not value["parts"].has(host) or value["parts"][host]["kind"] != "frame" or value["parts"][id]["kind"] in ["frame", "cable"]: return false
	for id in value["placements"]:
		var placement: Variant = value["placements"][id]
		if not value["parts"].has(id) or value["parts"][id]["kind"] != "frame" or typeof(placement) != TYPE_DICTIONARY or not ControlContractValidation.has_exact_fields(placement, PackedStringArray(["position", "mode", "enabled", "energy", "generation_remainder"])) or not InventorySpatialMath.is_position(placement["position"]) or placement["mode"] not in ["freeform", "surface"] or typeof(placement["enabled"]) != TYPE_BOOL or not ControlContractValidation.is_integer(placement["energy"], 0, CAPACITY) or not ControlContractValidation.is_integer(placement["generation_remainder"], 0, 89): return false
	for id in value["links"]:
		var link: Variant = value["links"][id]
		if not value["parts"].has(id) or value["parts"][id]["kind"] != "cable" or typeof(link) != TYPE_DICTIONARY or not ControlContractValidation.has_exact_fields(link, PackedStringArray(["a", "b"])) or link["a"] == link["b"] or not value["placements"].has(link["a"]) or not value["placements"].has(link["b"]): return false
		if InventorySpatialMath.distance_millimetres(value["placements"][link["a"]]["position"], value["placements"][link["b"]]["position"]) > MAX_CABLE_LENGTH: return false
	for id in value["jobs"]:
		var job: Variant = value["jobs"][id]
		if not value["placements"].has(id) or typeof(job) != TYPE_DICTIONARY or not ControlContractValidation.has_exact_fields(job, PackedStringArray(["recipe", "progress", "energy_spent", "paused"])) or not ControlContractValidation.is_id(job["recipe"]) or not ControlContractValidation.is_integer(job["progress"], 0, 36000) or not ControlContractValidation.is_integer(job["energy_spent"], 0, 100000) or typeof(job["paused"]) != TYPE_BOOL: return false
	return true


## Short deterministic BFS: only generators and routers relay power to another load.
## Cable energy budgets are shared across all consumers for this simulation tick.
static func draw(state: Dictionary, owner: Dictionary, target: String, joules: int, budgets: Dictionary, commit: bool = true) -> bool:
	if joules <= 0: return true
	var queue: Array = [{"id": target, "path": []}]
	var visited: Dictionary = {target: true}
	var links: Array = state["links"].keys()
	links.sort()
	while not queue.is_empty():
		var step: Dictionary = queue.pop_front()
		var id: String = step["id"]
		if operational(state, owner, id, "solar") and int(state["placements"][id]["energy"]) >= joules:
			var available: bool = true
			for cable in step["path"]:
				if int(budgets.get(cable, 0)) < joules: available = false
			if available:
				if commit:
					state["placements"][id]["energy"] -= joules
					for cable in step["path"]: budgets[cable] -= joules
				return true
		if id != target and not operational(state, owner, id, "router") and not operational(state, owner, id, "solar"): continue
		if not deployed(state, owner, id) or not state["placements"][id]["enabled"] or not modules(state, owner, id).has("power"): continue
		for cable in links:
			var wire: Dictionary = item(owner, cable)
			if wire.is_empty() or wire["container_id"] != container(owner, state["links"][cable]["a"]) or int(wire["condition_permille"]) == 0: continue
			var link: Dictionary = state["links"][cable]
			var next: String = link["b"] if link["a"] == id else (link["a"] if link["b"] == id else "")
			if next.is_empty() or visited.has(next) or not deployed(state, owner, next) or not modules(state, owner, next).has("power"): continue
			visited[next] = true
			var path: Array = step["path"].duplicate()
			path.append(cable)
			queue.append({"id": next, "path": path})
	return false


static func _load_catalog() -> Dictionary:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/machinery/catalog.v2.json"))
	if typeof(raw) != TYPE_DICTIONARY or not ControlContractValidation.has_exact_fields(raw, PackedStringArray(["schema_version", "parts"])) or raw["schema_version"] != 2 or typeof(raw["parts"]) != TYPE_DICTIONARY or not ControlContractValidation.has_exact_fields(raw["parts"], PackedStringArray(["frame", "socket", "power", "controller", "printhead", "refinery", "extractor", "solar", "router", "expander", "cable", "autolathe"])): return {}
	var original: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/machinery/catalog.v1.json"))["parts"]
	for kind in original:
		if raw["parts"].get(kind) != original[kind]: return {}
	for amount in raw["parts"].values():
		if not ControlContractValidation.is_integer(amount, 1, 2000000): return {}
	return raw["parts"].duplicate(true)
