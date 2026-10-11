extends RefCounted
class_name WorkstationResourceView

## Validated read-only host requirements. No command or canonical state ownership.
var _had_job: bool = false
var _ended: bool = false


static func valid(record: Dictionary) -> bool:
	var projection := RemoteProductionProjection.new()
	var accepted: bool = projection.accept_record(record).is_success
	projection.free()
	return accepted


func describe(record: Dictionary, recipe_id: String, pending: bool = false, include_recipe: bool = true) -> String:
	if not valid(record):
		_had_job = false
		_ended = false
		return "Resources and prerequisites unavailable: wait for a valid current observation."
	var job: Dictionary = record["job"]
	if _had_job and job.is_empty(): _ended = true
	if not job.is_empty(): _ended = false
	_had_job = not job.is_empty()
	var lines := PackedStringArray()
	lines.append("Workstation actions available" if record["can_operate"] else "Workstation actions unavailable: approach with a conscious body and an unreserved hand.")
	lines.append("Sources in extraction reach: " + (", ".join(PackedStringArray(record["extractable_sources"])) if not record["extractable_sources"].is_empty() else "none"))
	for id in record["deposits"]:
		lines.append("%s: %.3f kg remaining" % [id, float(record["deposits"][id]) / 1000000.0])
	lines.append("Shared station stock: " + stock_text(record["store"]))
	lines.append("Owned carried payloads: %d canister(s); unload at the station before recipe use." % record["cargo"].size())
	for id in record["cargo"]:
		lines.append("%s: %s" % [id, stock_text(record["cargo"][id])])
	lines.append("Physical plates owned: %d. Printed shared stock: %.3f kg; collect stock to obtain a physical plate." % [record["components"].size(), float(record["store"]["plate"]) / 1000000.0])
	lines.append("Station energy: %d J. Shared vessel: %s (%.1f kPa)." % [record["energy_joules"], stock_text(record["vessel"]), record["vessel_pressure_kpa"]])
	var unpowered := PackedStringArray()
	for id in record["powered"]:
		if not record["powered"][id]: unpowered.append(id)
	lines.append("Unpowered: " + (", ".join(unpowered) if not unpowered.is_empty() else "none"))
	lines.append("Legacy wall segments: %d" % (int(record["wall_mass_milligrams"]) / 1000000))
	if pending: lines.append("Command queued: awaiting receipt; no work or output confirmed.")
	if not job.is_empty():
		var name: String = job["recipe_id"] if job["recipe_id"] != "" else "resource extraction"
		var extraction: Dictionary = record.get("tool_extraction", {})
		var paused: bool = not record["powered"][job["station"]] or extraction.get("status", "") == "paused"
		lines.append("%s job: %s at %s; %.1f s remaining. Reserved inputs are not available stock; acceptance is not completion." % ["Paused" if paused else "Active", name, job["station"], float(job["remaining_ticks"]) / float(record["timebase_hz"])])
		if extraction.get("status", "") == "paused": lines.append("Pause reason: " + str(extraction.get("pause_reason", "unavailable")))
	elif _ended:
		lines.append("Previously observed job ended; completion or cancellation is unconfirmed here. Use current resource counts.")
	else:
		lines.append("No active job observed; this does not confirm past completion.")
	if include_recipe: lines.append(recipe_text(record, recipe_id))
	return "\n".join(lines)


static func recipe_text(record: Dictionary, recipe_id: String) -> String:
	if not valid(record): return "Recipe prerequisites unavailable: wait for a valid current observation."
	if recipe_id.is_empty() or not record["recipes"].has(recipe_id): return "Selected recipe unavailable in current observation."
	var blockers := PackedStringArray()
	if not record["can_operate"]: blockers.append("approach station with a conscious body and an unreserved hand")
	if not record["job"].is_empty(): blockers.append("station occupied; wait or use existing cancellation controls")
	var hint: String = "Recipe requirements unavailable from legacy v7 observation."
	if record.has("recipe_requirements"):
		var recipe: Dictionary = record["recipe_requirements"][recipe_id]
		var station: String = recipe["station"]
		var inputs: Dictionary = recipe["inputs"]
		hint = "Host catalog requirements: %s; %d J at %s." % [stock_text(inputs), recipe["energy_joules"], station]
		if not record["powered"][station]: blockers.append("%s needs power" % station)
		if int(record["energy_joules"]) < int(recipe["energy_joules"]): blockers.append("energy short by %d J" % (int(recipe["energy_joules"]) - int(record["energy_joules"])))
		for material in inputs:
			var available: int = int(record["store"].get(material, 0))
			if available < int(inputs[material]): blockers.append("shared %s short by %.3f kg; carried payloads must be unloaded" % [material, float(int(inputs[material]) - available) / 1000000.0])
	hint += " Duration and capacity quote unavailable."
	return "Selected: %s. %s\n%s" % [recipe_id, hint, "Current blockers: " + "; ".join(blockers) if not blockers.is_empty() else "No blockers found in observed fields; host still validates capability, capacity and revision."]


static func stock_text(stock: Dictionary) -> String:
	var entries := PackedStringArray()
	for id in stock:
		if int(stock[id]) > 0: entries.append("%s %.3f kg" % [id, float(stock[id]) / 1000000.0])
	return ", ".join(entries) if not entries.is_empty() else "empty"
