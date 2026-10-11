extends RefCounted
class_name FirstPlayableTaskGuide

## Current scoped facts only. No command, receipt, progression or world ownership.
static func describe(production: Dictionary) -> PackedStringArray:
	var projection := RemoteProductionProjection.new()
	var accepted: bool = projection.accept_record(production).is_success
	projection.free()
	if not accepted:
		return PackedStringArray(["Current tasks unavailable. Wait for a valid host observation; no progress is confirmed."])
	var lines := PackedStringArray()
	var remaining: int = int(production["deposits"]["deposit.iron"])
	var ore: int = 0
	var canisters: int = 0
	# Production cargo is already scoped to owned resource carriers.
	for stock in production["cargo"].values():
		canisters += 1
		ore += int(stock.get("ore.iron", 0))
	var gather: String = "Approach iron ore with a conscious body and a free hand."
	if remaining == 0:
		gather = "Depleted; this source cannot supply more ore. Use ore already carried or stored."
	elif canisters == 0:
		gather = "Collect a canister from the nearby tray through Inventory before extraction."
	elif production["extractable_sources"].has("deposit.iron"):
		gather = "Extraction reach/capability observed. In Workstation, select iron ore and an owned canister; host checks remaining mass and capacity."
	lines.append("1 · Gather finite iron: %.2f kg remains. %s" % [float(remaining) / 1000000.0, gather])
	lines.append("2 · Transport ore: %d scoped canister payload(s), %.2f kg iron ore. %s" % [canisters, float(ore) / 1000000.0,
		"Collect a canister from the nearby tray." if canisters == 0 else ("Return to the workstation with a conscious body and a free hand, then unload the selected canister's iron ore; host checks receiving capacity." if ore > 0 else "No carried iron ore observed; gather first or use stored ore.")])
	var stored_ore: int = int(production["store"]["ore.iron"])
	var iron: int = int(production["store"]["iron"])
	var plates: int = production["components"].size()
	var printed: int = int(production["store"]["plate"])
	lines.append("3 · Refine: %.2f kg stored ore; %.2f kg stored iron. %s" % [float(stored_ore) / 1000000.0, float(iron) / 1000000.0,
		_recipe_hint(production, "refine.iron", "Refine iron ore")])
	lines.append("4 · Print: %.2f kg printed stock currently observed, not carried inventory. %s" % [float(printed) / 1000000.0,
		_recipe_hint(production, "craft.plate", "Print a plate")])
	lines.append("5 · Collect: %d carried plate(s). %s" % [plates,
		("Use Workstation to collect printed stock into inventory; host checks free hand, reach and physical capacity." if production["can_operate"] else "Approach the workstation with a conscious body and a free hand to collect printed stock.") if printed >= 1000000 else "Needs 1 kg printed stock before collection. An accepted print job is not a carried plate."])
	lines.append("6 · Recycle: %d carried plate(s). %s" % [plates, _recycle_hint(production)])
	lines.append("7 · Reprint: %.2f kg stored iron available now. %s Shared iron cannot prove recycling or completion of your loop." % [float(iron) / 1000000.0,
		_recipe_hint(production, "craft.plate", "Print a plate again after recycling")])
	lines.append("Optional construction · Physical walls: %d currently observed. %s" % [production["walls"].size(),
		"No carried plate for another wall; make or recover one." if plates == 0 else "Select a carried plate in Construction. Host checks reach, free hand, grid, orientation, capacity and overlap."])
	var job: Dictionary = production["job"]
	if not job.is_empty():
		lines.append("Pending work observed: %s · %.1f s remaining%s. Acceptance is not completion; wait for output and check the Workstation's session guide." % [job["recipe_id"], float(job["remaining_ticks"]) / float(production["timebase_hz"]), " · paused without power" if not production["powered"][job["station"]] else ""])
	else:
		lines.append("No active recipe observed. Job disappearance alone does not prove completion; stock can be shared, consumed or transferred. See Workstation for confirmed session steps.")
	return lines


static func _recipe_hint(record: Dictionary, recipe: String, action: String) -> String:
	if not record["recipes"].has(recipe): return "Recipe unavailable in this observation."
	if not record["job"].is_empty(): return "Recipe work pending; wait or cancel through Workstation. Cancellation is not completion."
	if not record["can_operate"]: return "Approach the workstation with a conscious body and a free hand."
	if not record.has("recipe_requirements"): return "Recipe costs unavailable in this legacy observation; inspect Workstation before acting."
	var requirements: Dictionary = record["recipe_requirements"][recipe]
	var station: String = requirements["station"]
	if not record["powered"][station]: return "%s needs power." % station.capitalize()
	if int(record["energy_joules"]) < int(requirements["energy_joules"]): return "Needs %d J available energy." % requirements["energy_joules"]
	for material in requirements["inputs"]:
		var needed: int = int(requirements["inputs"][material])
		if int(record["store"][material]) < needed:
			var hint: String = "Needs %.2f kg stored %s; unload or process more material." % [float(needed) / 1000000.0, material]
			if recipe == "craft.plate" and material == "iron" and needed == 1000000:
				hint += " One ore batch may not supply a whole plate; observe iron output and refine another batch if needed."
			return hint
	return "In Workstation, choose %s. Observed input, energy and power are present; host rechecks capacity and access." % action


static func _recycle_hint(record: Dictionary) -> String:
	if record["components"].is_empty(): return "Collect a printed plate first, or recover a placed one. Printed stock is not a carried plate."
	if not record["can_operate"]: return "Approach the workstation with a conscious body and a free hand."
	if not record["powered"]["recycler"]: return "Recycler needs power."
	# Physical recycling is an immediate command with fixed cost, not salvage.plate's stock recipe.
	if int(record["energy_joules"]) < 500: return "Needs 500 J available energy for the physical plate."
	return "In Workstation, select a carried plate and recycle it: 500 J spent, 1 kg iron returned to shared stock if accepted. Host checks ownership and receiving capacity; the plate is consumed."
