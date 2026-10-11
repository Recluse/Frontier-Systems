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
	lines.append("1 · Finite iron source: %.2f kg remains. %s" % [float(remaining) / 1000000.0,
		"Depleted; this source cannot supply more ore." if remaining == 0 else ("In extraction reach; use Workstation controls." if production["extractable_sources"].has("deposit.iron") else "Approach iron ore with a conscious body and a free hand.")])
	lines.append("2 · Carried canister: %d scoped payload(s), %.2f kg iron ore. %s" % [canisters, float(ore) / 1000000.0,
		"Collect a canister from the nearby tray." if canisters == 0 else ("Unload ore at the workstation." if ore > 0 else "Extract into a carried canister; capacity is checked by the host.")])
	var stored_ore: int = int(production["store"]["ore.iron"])
	var iron: int = int(production["store"]["iron"])
	lines.append("3 · Refining: %.2f kg stored ore; %.2f kg stored iron. %s" % [float(stored_ore) / 1000000.0, float(iron) / 1000000.0,
		_recipe_hint(production, "refine.iron", "refinery", stored_ore)])
	var plates: int = production["components"].size()
	lines.append("4 · Physical plate: %d carried; %.2f kg printed stock. %s" % [plates, float(production["store"]["plate"]) / 1000000.0,
		"Select a carried plate in Construction for wall placement." if plates > 0 else ("Approach the workstation to collect printed stock; host checks free hand and inventory capacity." if int(production["store"]["plate"]) >= 1000000 else _recipe_hint(production, "craft.plate", "printer", iron))])
	lines.append("5 · Physical walls: %d currently observed. %s" % [production["walls"].size(),
		"No carried plate for another wall; make or recover one." if plates == 0 else "Construction checks reach, free hand, grid, orientation, capacity and overlap at submission."])
	var job: Dictionary = production["job"]
	if not job.is_empty():
		lines.append("Active job: %s · %.1f s remaining%s. Acceptance is not completion." % [job["recipe_id"], float(job["remaining_ticks"]) / float(production["timebase_hz"]), " · paused without power" if not production["powered"][job["station"]] else ""])
	return lines


static func _recipe_hint(record: Dictionary, recipe: String, station: String, input_mass: int) -> String:
	if not record["recipes"].has(recipe): return "Recipe unavailable in this observation."
	if not record["can_operate"]: return "Approach the workstation with a conscious body and a free hand."
	if not record["job"].is_empty(): return "Workstation occupied; wait or cancel through existing controls."
	if not record["powered"][station]: return "%s needs power." % station.capitalize()
	if int(record["energy_joules"]) < 1000: return "Needs 1000 J available energy."
	if input_mass < 1000000: return "Needs 1 kg stored input; transfer or refine more material."
	return "Observed prerequisites present for %s; the host rechecks the action." % recipe
