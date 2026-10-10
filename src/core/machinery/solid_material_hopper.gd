extends RefCounted
class_name SolidMaterialHopper

## Production-owned solid stock, keyed by its physical frame in the cargo ledger.
## All edits target detached transaction candidates; no runtime callbacks or grants.
const CAPACITY_MILLIGRAMS: int = 2000000


static func plan(state: Dictionary, owner: Dictionary, workshop: Dictionary, owned: Array, machine: String, id: String, operation: String, payload: Dictionary) -> ServiceResult:
	if not MachineryWorkshop.deployed(workshop, owner, machine) or not MachineryWorkshop.modules(workshop, owner, machine).has("autolathe"):
		return MachineryConstruction.failure("Fit an autolathe head and deploy the machine before using its hopper.")
	if not owned.has(id) or id == machine:
		return MachineryConstruction.failure("Select a physical feed item or receiving canister in your own inventory.")
	var physical: Dictionary = MachineryWorkshop.item(owner, id)
	var stock: Dictionary = state["cargo"].get(machine, MachineryConstruction.empty_stock(state)).duplicate(true)
	if operation == "machine_autolathe_eject":
		var amount: Variant = payload["amount_milligrams"]
		if not ControlContractValidation.is_integer(amount, 1, CAPACITY_MILLIGRAMS) or physical.get("definition_id") not in ["item.resource-canister.prototype", "item.resource-canister.fabricated"]:
			return MachineryConstruction.failure("Eject a bounded amount of iron into an owned resource canister.")
		var receiver: Dictionary = state["cargo"].get(id, MachineryConstruction.empty_stock(state)).duplicate(true)
		for material in receiver:
			if material != "iron" and int(receiver[material]) > 0: return MachineryConstruction.failure("The receiving canister must be empty or contain iron.")
		if int(stock["iron"]) < int(amount) or int(receiver["iron"]) + int(amount) > CAPACITY_MILLIGRAMS:
			return MachineryConstruction.failure("Insufficient hopper iron or receiving canister capacity.")
		if not state["cargo"].has(id) and state["cargo"].size() >= 32: return MachineryConstruction.failure("The payload registry is full.")
		stock["iron"] -= int(amount)
		receiver["iron"] += int(amount)
		state["cargo"][id] = receiver
	else:
		var amount: int = 0
		if physical.get("definition_id") == "item.plate.prototype":
			if not state["cargo"].has(id) or int(state["cargo"][id]["plate"]) != 1000000: return MachineryConstruction.failure("The plate has no trusted material provenance.")
			amount = 1000000
		elif workshop["parts"].has(id):
			if workshop["placements"].has(id) or workshop["links"].has(id) or workshop["mounts"].has(id): return MachineryConstruction.failure("Disconnect and remove fitted parts before feeding them.")
			var storage: String = MachineryWorkshop.container(owner, id)
			for child in owner["ledger"]["items"]:
				if child["container_id"] == storage: return MachineryConstruction.failure("Empty nested parts and canisters first.")
			for quantity in state["cargo"].get(id, {}).values():
				if int(quantity) > 0: return MachineryConstruction.failure("Empty this frame's hopper first.")
			amount = int(MachineryWorkshop.KINDS[workshop["parts"][id]["kind"]])
		else:
			return MachineryConstruction.failure("This hopper accepts physical iron plates and empty machine parts; it rejects tools, ore, liquids and gases.")
		if int(stock["iron"]) + amount > CAPACITY_MILLIGRAMS: return MachineryConstruction.failure("The solid hopper holds at most 2 kg of iron.")
		if not state["cargo"].has(machine) and not state["cargo"].has(id) and state["cargo"].size() >= 32: return MachineryConstruction.failure("The payload registry is full.")
		stock["iron"] += amount
		state["cargo"].erase(id)
		workshop["parts"].erase(id)
		owner["ledger"]["items"].erase(physical)
		for entry in owner["ledger"]["containers"].duplicate():
			if entry["owner_item_id"] == id: owner["ledger"]["containers"].erase(entry)
	state["cargo"][machine] = stock
	return ServiceResult.success()


static func consume(state: Dictionary, machine: String, bill: Dictionary) -> ServiceResult:
	var stock: Dictionary = state["cargo"].get(machine, {})
	for material in bill:
		if material != "iron" or int(stock.get(material, 0)) < int(bill[material]): return MachineryConstruction.failure("Load enough solid iron into the autolathe hopper for this design.")
	for material in bill: stock[material] -= int(bill[material])
	return ServiceResult.success()
