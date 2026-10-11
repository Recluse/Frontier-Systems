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
