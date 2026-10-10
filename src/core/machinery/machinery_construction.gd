extends RefCounted
class_name MachineryConstruction

## Trusted factory boundary. Callers provide intent, never inventory graphs or bills.
static func plan(production: ProductionSimulationSystem, state: Dictionary, inventory: InventorySimulationSystem, context: AuthenticatedCommandContext, request: String, operation: String, payload: Dictionary) -> ServiceResult:
	var snapshot: Dictionary = inventory.capture_snapshot().value
	var owner: Dictionary = snapshot["owner"].duplicate(true)
	var workshop: Dictionary = state["machinery"]
	var own: ServiceResult = inventory.own_inventory_observation(context)
	if not own.is_success: return own
	var body_root: String = own.value["body_container_id"]
	var own_ids: Array = []
	for physical in own.value["items"]: own_ids.append(physical["item_id"])
	var allowed: Array = ["expected_revision"]
	match operation:
		"machine_craft": allowed.append("kind")
		"machine_recycle": allowed.append("item_id")
		"machine_fit", "machine_unfit", "machine_insert", "machine_remove": allowed.append_array(["machine_id", "item_id", "socket_id"])
		"machine_deploy": allowed.append_array(["machine_id", "position", "mode"])
		"machine_pack", "machine_cancel", "machine_resume": allowed.append("machine_id")
		"machine_enable": allowed.append_array(["machine_id", "enabled"])
		"machine_wire": allowed.append_array(["machine_id", "other_id", "item_id"])
		"machine_unwire": allowed.append_array(["machine_id", "item_id"])
		"machine_run": allowed.append_array(["machine_id", "recipe"])
		"machine_print": allowed.append_array(["machine_id", "kind"])
		_: return failure("Unknown machinery action.")
	if not ControlContractValidation.has_exact_fields(payload, PackedStringArray(allowed)): return failure("An exact construction intent is required.")
	var machine: String = String(payload.get("machine_id", ""))
	if not machine.is_empty():
		if not workshop["parts"].has(machine) or workshop["parts"][machine]["kind"] != "frame": return failure("Select a physical machine frame.")
		if not own_ids.has(machine):
			if not MachineryWorkshop.deployed(workshop, owner, machine): return failure("This frame is not owned or deployed.")
			var reachable: ServiceResult = inventory.production_capability(context, true, workshop["placements"][machine]["position"])
			if not reachable.is_success: return reachable
	var id: String = String(payload.get("item_id", ""))
	var changed: bool = false
	if operation in ["machine_craft", "machine_print"]:
		var kind: String = String(payload["kind"])
		var is_canister: bool = operation == "machine_print" and kind == "equipment.canister"
		if (not MachineryWorkshop.KINDS.has(kind) and not is_canister) or workshop["parts"].size() >= 128 or state["structures"].size() >= 32: return failure("Select a known part; the physical registries are bounded.")
		var blueprint: Dictionary = production.machine_blueprint(kind).value if is_canister else {}
		var bill: Dictionary = blueprint["materials"].duplicate(true) if is_canister else {"iron": int(MachineryWorkshop.KINDS[kind])}
		var print_energy: int = int(blueprint["fabrication_energy_joules"]) if is_canister else 500
		if operation == "machine_craft":
			# Manual bootstrap construction deliberately has no grid dependency.
			if not inventory.production_capability(context, true).is_success: return failure("Approach the workbench for manual construction.")
			if int(state["store"]["iron"]) < int(bill["iron"]): return failure("Hand assembly needs refined iron in the workbench store.")
			state["store"]["iron"] -= int(bill["iron"])
		else:
			if not MachineryWorkshop.operational(workshop, owner, machine, "printhead"): return failure("Fit a controller, power connector and printhead, then deploy the printer.")
			if kind in ["frame", "printhead", "refinery", "solar", "equipment.canister"] and not MachineryWorkshop.modules(workshop, owner, machine).has("expander"): return failure("Large prints require an installed expansion module.")
			var transfer: ServiceResult = transfer_plan(state, owner, machine, bill, {})
			if not transfer.is_success: return transfer
			if int(workshop["placements"][machine]["energy"]) < print_energy: return failure("The printer buffer has insufficient energy from the grid.")
			workshop["placements"][machine]["energy"] -= print_energy
			state["cargo"] = transfer.value
		id = "machine-part-%s" % request.sha256_text().substr(0, 24)
		if is_canister: state["structures"][id] = {"blueprint_id": kind, "fingerprint": blueprint["fingerprint"], "materials": bill.duplicate(true)}
		else: workshop["parts"][id] = {"kind": kind}
		var physical: Dictionary = {"item_id": id, "definition_id": blueprint["definition_id"] if is_canister else MachineryWorkshop.definition(kind), "definition_revision": 1, "condition_permille": 1000, "container_id": body_root if operation == "machine_craft" else MachineryWorkshop.container(owner, machine)}
		owner["ledger"]["items"].append(physical)
		var definition: ServiceResult = inventory.factory_definition(physical["definition_id"])
		if not definition.is_success: return definition
		if definition.value["storage"] != null: owner["ledger"]["containers"].append({"container_id": InventorySimulationSystem.factory_storage_id(id), "owner_item_id": id, "capacity": definition.value["storage"].duplicate(true)})
		changed = true
	elif operation == "machine_recycle":
		if not own_ids.has(id) or not workshop["parts"].has(id) or workshop["placements"].has(id) or workshop["links"].has(id): return failure("Pack and disconnect the owned component before recycling.")
		var storage: String = MachineryWorkshop.container(owner, id)
		for child in owner["ledger"]["items"]:
			if child["container_id"] == storage: return failure("Remove all nested parts and canisters before recycling.")
		state["store"]["iron"] += int(MachineryWorkshop.KINDS[workshop["parts"][id]["kind"]])
		workshop["mounts"].erase(id)
		workshop["parts"].erase(id)
		owner["ledger"]["items"].erase(MachineryWorkshop.item(owner, id))
		for entry in owner["ledger"]["containers"].duplicate():
			if entry["owner_item_id"] == id: owner["ledger"]["containers"].erase(entry)
		changed = true
	elif operation in ["machine_fit", "machine_unfit", "machine_insert", "machine_remove"]:
		var physical: Dictionary = MachineryWorkshop.item(owner, id)
		if physical.is_empty(): return failure("Select an actual physical item.")
		var storage: String = MachineryWorkshop.container(owner, machine)
		if operation == "machine_fit":
			if (not own_ids.has(id) and physical["container_id"] != storage) or not workshop["parts"].has(id) or workshop["parts"][id]["kind"] in ["frame", "cable"]: return failure("Fit an owned machine module.")
			var installed: Dictionary = MachineryWorkshop.modules(workshop, owner, machine)
			var kind: String = workshop["parts"][id]["kind"]
			if kind == "socket":
				if installed.get("socket", []).size() >= (6 if installed.has("expander") else 3): return failure("Add an expander for more than three sockets.")
			elif installed.has(kind): return failure("Remove the fitted module of this kind first.")
			physical["container_id"] = storage
			workshop["mounts"][id] = machine
		elif operation == "machine_unfit":
			if physical["container_id"] != storage or workshop["links"].has(id): return failure("Select a fitted module, disconnecting cables first.")
			physical["container_id"] = body_root
			workshop["mounts"].erase(id)
		else:
			var socket: String = String(payload["socket_id"])
			if not MachineryWorkshop.modules(workshop, owner, machine).get("socket", []).has(socket): return failure("Select a fitted canister socket.")
			var socket_storage: String = MachineryWorkshop.container(owner, socket)
			if operation == "machine_insert":
				if not own_ids.has(id) or physical["definition_id"] not in ["item.resource-canister.prototype", "item.resource-canister.fabricated"]: return failure("Insert an owned resource canister.")
				physical["container_id"] = socket_storage
			else:
				if physical["container_id"] != socket_storage: return failure("Select the canister in this socket.")
				physical["container_id"] = body_root
		changed = true
	elif operation == "machine_deploy":
		if not own_ids.has(machine) or workshop["placements"].has(machine) or workshop["placements"].size() >= 20 or not InventorySpatialMath.is_position(payload["position"]) or payload["mode"] not in ["freeform", "surface"]: return failure("Deploy an owned, packed frame at a bounded position.")
		if payload["mode"] == "surface" and int(payload["position"][1]) != 0: return failure("The prototype surface adapter supports floor placement at Y=0.")
		var reach: ServiceResult = inventory.production_capability(context, true, payload["position"])
		if not reach.is_success: return reach
		var root: String = MachineryWorkshop.root_id(machine)
		owner["ledger"]["containers"].append({"container_id": root, "owner_item_id": "", "capacity": {"max_mass_milligrams": 100000000, "max_volume_millilitres": 200000, "max_items": 1, "accepted_tags": ["machine.frame"]}})
		MachineryWorkshop.item(owner, machine)["container_id"] = root
		snapshot["world_storage"].append({"container_id": root, "position_millimetres": payload["position"].duplicate(), "accessible": true})
		workshop["placements"][machine] = {"position": InventorySpatialMath.normalized(payload["position"]), "mode": payload["mode"], "enabled": true, "energy": 0, "generation_remainder": 0}
		changed = true
	elif operation == "machine_pack":
		if not workshop["placements"].has(machine): return failure("This machine is already packed.")
		for link in workshop["links"].values():
			if machine in [link["a"], link["b"]]: return failure("Disconnect electrical cables first.")
		workshop["jobs"].erase(machine)
		workshop["placements"].erase(machine)
		MachineryWorkshop.item(owner, machine)["container_id"] = body_root
		for entry in owner["ledger"]["containers"].duplicate():
			if entry["container_id"] == MachineryWorkshop.root_id(machine): owner["ledger"]["containers"].erase(entry)
		for location in snapshot["world_storage"].duplicate():
			if location["container_id"] == MachineryWorkshop.root_id(machine): snapshot["world_storage"].erase(location)
		changed = true
	elif operation in ["machine_wire", "machine_unwire"]:
		if operation == "machine_wire":
			var other: String = String(payload["other_id"])
			if not own_ids.has(id) or not workshop["parts"].has(id) or workshop["parts"][id]["kind"] != "cable" or workshop["links"].has(id) or workshop["links"].size() >= 24 or not MachineryWorkshop.deployed(workshop, owner, machine) or not MachineryWorkshop.deployed(workshop, owner, other) or other == machine: return failure("Connect an owned cable between two deployed frames.")
			if not inventory.production_capability(context, true, workshop["placements"][other]["position"]).is_success or InventorySpatialMath.distance_millimetres(workshop["placements"][machine]["position"], workshop["placements"][other]["position"]) > MachineryWorkshop.MAX_CABLE_LENGTH: return failure("Both endpoints must be within reach and cable length.")
			if not MachineryWorkshop.modules(workshop, owner, machine).has("power") or not MachineryWorkshop.modules(workshop, owner, other).has("power"): return failure("Both frames need a power connector.")
			workshop["links"][id] = {"a": machine, "b": other}
			MachineryWorkshop.item(owner, id)["container_id"] = MachineryWorkshop.container(owner, machine)
		else:
			if not workshop["links"].has(id) or machine not in workshop["links"][id].values(): return failure("Select a cable attached to this machine.")
			workshop["links"].erase(id)
			MachineryWorkshop.item(owner, id)["container_id"] = body_root
		changed = true
	elif operation == "machine_enable":
		if not workshop["placements"].has(machine) or typeof(payload["enabled"]) != TYPE_BOOL: return failure("Enable or isolate a deployed frame.")
		workshop["placements"][machine]["enabled"] = payload["enabled"]
	elif operation == "machine_run":
		var recipe: String = String(payload["recipe"])
		var spec: Dictionary = production.machine_recipe(recipe)
		if spec.is_empty() or workshop["jobs"].has(machine) or not MachineryWorkshop.operational(workshop, owner, machine, spec["capability"]): return failure("Select a compatible recipe on an operational idle machine.")
		if not spec["deposit"].is_empty() and InventorySpatialMath.distance_millimetres(workshop["placements"][machine]["position"], ProductionSimulationSystem.SOURCE_POSITIONS[spec["deposit"]]) > 1500: return failure("The extractor must be deployed near its resource source.")
		workshop["jobs"][machine] = {"recipe": recipe, "progress": 0, "energy_spent": 0, "paused": false}
	elif operation in ["machine_cancel", "machine_resume"]:
		if not workshop["jobs"].has(machine): return failure("No batch exists on this machine.")
		if operation == "machine_cancel": workshop["jobs"].erase(machine)
		else: workshop["jobs"][machine]["paused"] = false
	if not changed: return ServiceResult.success({})
	return inventory.prepare_factory_graph(context, owner, snapshot["world_storage"], "machine-graph-%s" % request.sha256_text().substr(0, 24), production.payload_masses(state))


## All inputs and outputs are routed as one candidate transaction. Canisters contain
## one material and at most 2 kg; an emptied input canister can become an output.
static func transfer_plan(state: Dictionary, owner: Dictionary, machine: String, inputs: Dictionary, outputs: Dictionary) -> ServiceResult:
	var cargo: Dictionary = state["cargo"].duplicate(true)
	var carriers: Array = MachineryWorkshop.carriers(state["machinery"], owner, machine)
	for material in inputs:
		var remaining: int = int(inputs[material])
		for id in carriers:
			if not cargo.has(id): cargo[id] = empty_stock(state)
			var taken: int = mini(remaining, int(cargo[id][material]))
			cargo[id][material] -= taken
			remaining -= taken
		if remaining > 0: return failure("Load sufficient inputs into fitted canister sockets.")
	for material in outputs:
		var remaining: int = int(outputs[material])
		for id in carriers:
			if not cargo.has(id): cargo[id] = empty_stock(state)
			var mass: int = 0
			for amount in cargo[id].values(): mass += int(amount)
			if mass > int(cargo[id][material]): continue
			var given: int = mini(remaining, 2000000 - mass)
			cargo[id][material] += given
			remaining -= given
		if remaining > 0: return failure("Fit enough empty or matching output canisters.")
	if cargo.size() > 32: return failure("The carrier registry is full.")
	return ServiceResult.success(cargo)


static func empty_stock(state: Dictionary) -> Dictionary:
	var stock: Dictionary = {}
	for material in state["store"]: stock[material] = 0
	return stock


static func failure(message: String) -> ServiceResult:
	return ServiceResult.failure(&"invalid_machinery_intent", message)
