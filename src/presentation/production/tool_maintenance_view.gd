extends RefCounted
class_name ToolMaintenanceView

## Presentation of scoped observations only. No catalog, repair plan or state owner.
static func components(tools: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for assembly in tools.get("assemblies", []):
		for part in assembly["parts"]:
			result[part["part_id"]] = {"part": part, "assembly_id": assembly["assembly_id"], "actions": assembly["actions"]}
	for part in tools.get("loose_parts", []):
		result[part["part_id"]] = {"part": part, "assembly_id": "", "actions": {}}
	return result


static func blocker(tools: Dictionary, production: Dictionary, selected_id: String) -> String:
	if tools.is_empty() or production.is_empty():
		return "Waiting for current tool and workstation observations."
	if not components(tools).has(selected_id):
		return "Select a component; the previous stable ID may no longer be owned."
	if not production.get("can_operate", false):
		return "Approach the workstation with a conscious body and an unreserved hand."
	if not production.get("powered", {}).get("construction", false):
		return "Construction workstation power is off."
	if int(components(tools)[selected_id]["part"]["integrity_ppm"]) == 1000000:
		return "Healthy component: no maintenance needed."
	var quote: Dictionary = tools.get("maintenance", {}).get(selected_id, {})
	if not quote.is_empty() and production.has("energy_joules") and int(production["energy_joules"]) < int(quote["energy_joules"]):
		return "Insufficient station energy for this full-maintenance request."
	return ""


static func describe(tools: Dictionary, production: Dictionary, selected_id: String) -> String:
	var entries: Dictionary = components(tools)
	if not entries.has(selected_id):
		return ("Selected ID: " + selected_id + "\n" if not selected_id.is_empty() else "") + "Unavailable: " + blocker(tools, production, selected_id)
	var entry: Dictionary = entries[selected_id]
	var part: Dictionary = entry["part"]
	var lines: PackedStringArray = [
		"%s · %s" % [part["name"], part["material_name"]],
		"Component ID: " + selected_id,
		"Integrity: %.4f%% (%d / 1000000 ppm)" % [float(part["integrity_ppm"]) / 10000.0, part["integrity_ppm"]],
		"Condition: " + ("healthy" if int(part["integrity_ppm"]) == 1000000 else "zero integrity; retained for maintenance" if int(part["integrity_ppm"]) == 0 else "degraded")
	]
	if entry["assembly_id"] == "":
		lines.append("Loose component; no installed assembly capability observed.")
	else:
		lines.append("Tool: " + entry["assembly_id"])
		var actions: Array = entry["actions"].keys()
		actions.sort()
		for action in actions:
			var state: Dictionary = entry["actions"][action]
			lines.append("%s: %s" % [action, "available" if state["available"] else "disabled; missing " + ", ".join(PackedStringArray(state["missing_functions"]))])
	lines.append("Preview: maintain up to full integrity; host validates ownership, revisions, reach, voluntary action, power and energy.")
	var quote: Dictionary = tools.get("maintenance", {}).get(selected_id, {})
	if quote.is_empty():
		lines.append("Energy quote unavailable in current observation (legacy or missing).")
	else:
		lines.append("Observed quote: restore %d ppm for %d J; material stock required: none." % [quote["restored_ppm"], quote["energy_joules"]])
	lines.append("Requires owned component, workstation reach, conscious voluntary action, unreserved hand and construction power.")
	lines.append("Advisory observation: revisions, supply and capabilities may change before the tick; success is not guaranteed.")
	lines.append("Damage cause and post-repair capabilities are not observed.")
	if production.has("energy_joules"):
		lines.append("Station reserve: %d J." % int(production["energy_joules"]))
	else:
		lines.append("Station reserve unavailable.")
	var reason: String = blocker(tools, production, selected_id)
	if not reason.is_empty():
		lines.append("Unavailable: " + reason)
	return "\n".join(lines)


## Exact scoped selection is distinct from the host-observed mount occupant.
static func targets(tools: Dictionary, production: Dictionary, inspected_id: String, repair_id: String, mount_id: String, loose_id: String) -> String:
	if not ToolObservationValidation.valid(tools):
		return "Maintenance targets unavailable: current tool observation missing."
	var lines := PackedStringArray(["Inspected item ID: " + (inspected_id if not inspected_id.is_empty() else "unavailable")])
	var repair_observed: bool = false
	var assembly_found: bool = false
	for assembly in tools["assemblies"]:
		if assembly["assembly_id"] != inspected_id: continue
		assembly_found = true
		lines.append("Observed tool ID: " + inspected_id + "; selection does not equip it.")
		if assembly["slots"].has(mount_id):
			var occupant: String = assembly["slots"][mount_id]
			lines.append("Selected mount ID: " + mount_id)
			lines.append("Observed installed part ID: " + (occupant if not occupant.is_empty() else "empty"))
		else:
			lines.append("Selected mount ID: " + mount_id + "; unavailable in current tool observation.")
		for part in assembly["parts"]:
			if part["part_id"] == repair_id: repair_observed = true
	var loose_found: bool = false
	for part in tools["loose_parts"]:
		if part["part_id"] == loose_id: loose_found = true
		if part["part_id"] == inspected_id and part["part_id"] == repair_id:
			repair_observed = true
			lines.append("Inspected detached part ID: " + inspected_id + "; no installed tool or mount.")
	if not assembly_found: lines.append("Inspected tool/mount unavailable in current observation.")
	lines.append("Selected loose part ID: " + loose_id + ("; observed detached, intended fit/recycle target." if loose_found else "; unavailable in current loose inventory."))
	lines.append("Selected repair part ID: " + repair_id + ("; observed for inspected item." if repair_observed else "; unavailable for inspected item."))
	if repair_observed: lines.append(describe(tools, production, repair_id))
	lines.append("Fit intent uses the selected loose part and mount; detach intent uses the observed mount occupant. Selection confirms no replacement, repair or compatibility.")
	return "\n".join(lines)
