extends RefCounted
class_name EquipmentPrerequisiteView

## Advisory observations only; never predicts compatibility or repair.
static func fill(picker: OptionButton, entries: Dictionary, prompt: String) -> void:
	var selected_id: String = selected(picker)
	var ids: Array = entries.keys()
	ids.sort()
	var choices: Array = [["", prompt, false]]
	for id in ids:
		choices.append([id, "%s · %s" % [entries[id], id], false])
	if not selected_id.is_empty() and not entries.has(selected_id):
		choices.append([selected_id, "Unavailable selected ID · " + selected_id, true])
	var unchanged: bool = picker.item_count == choices.size()
	for index in range(choices.size()):
		if not unchanged: break
		unchanged = picker.get_item_metadata(index) == choices[index][0] and picker.get_item_text(index) == choices[index][1] and picker.is_item_disabled(index) == choices[index][2]
	if unchanged: return
	picker.clear()
	for choice in choices:
		picker.add_item(choice[1])
		picker.set_item_metadata(picker.item_count - 1, choice[0])
		picker.set_item_disabled(picker.item_count - 1, choice[2])
		if choice[0] == selected_id: picker.select(picker.item_count - 1)


static func selected(picker: OptionButton) -> String:
	return str(picker.get_item_metadata(picker.selected)) if picker.selected >= 0 else ""


static func quote(production: Dictionary, blueprints: Dictionary, id: String, station: String) -> String:
	if not WorkstationResourceView.valid(production):
		return "Fabrication prerequisites unavailable: wait for a valid current observation."
	if not blueprints.has(id):
		return "Select a blueprint. Previously selected ID: " + id
	var blueprint: Dictionary = blueprints[id]
	var lines := PackedStringArray(["Blueprint: %s · %s" % [blueprint["name"], id]])
	var materials: Array = blueprint["materials"].keys()
	materials.sort()
	for material in materials:
		var required: int = int(blueprint["materials"][material])
		var stock: int = int(production["store"].get(material, 0))
		lines.append("%s: required %d mg; shared stock %d mg; shortfall %d mg." % [material, required, stock, maxi(0, required - stock)])
	lines.append("Fabrication energy: %d J; station reserve: %d J." % [blueprint["fabrication_energy_joules"], production["energy_joules"]])
	lines.append("%s power: %s. Workstation access: %s." % [station, "on" if production["powered"].get(station, false) else "off", "observed available" if production["can_operate"] else "unavailable"])
	lines.append("Carried cargo, physical parts and mounted parts are not shared stock. Unload cargo or use existing recycling actions to return materials.")
	lines.append("Host checks current revisions, ownership, reach, conscious voluntary action, hand, power, energy, stock and capacity at the tick; this preview guarantees no output.")
	return "\n".join(lines)


static func part_text(tools: Dictionary, production: Dictionary, blueprint_id: String, tool_id: String, slot_id: String, loose_id: String, pending: bool) -> String:
	if not ToolObservationValidation.valid(tools):
		return "Component prerequisites unavailable: wait for a valid current tool observation."
	var lines := PackedStringArray([quote(production, tools["part_blueprints"], blueprint_id, "printer")])
	lines.append("Owned physical loose parts: %d; select one to fit or recycle. Mounted components are not loose inventory." % tools["loose_parts"].size())
	lines.append("Selected loose ID: " + loose_id)
	for part in tools["loose_parts"]:
		if part["part_id"] == loose_id:
			lines.append("%s · %s · integrity %d / 1000000 ppm." % [part["name"], part["material_name"], part["integrity_ppm"]])
	var found: bool = false
	for assembly in tools["assemblies"]:
		if assembly["assembly_id"] != tool_id: continue
		found = true
		lines.append("Tool ID: %s; mount: %s; installed part: %s." % [tool_id, slot_id, assembly["slots"].get(slot_id, "unavailable")])
		var actions: Array = assembly["actions"].keys()
		actions.sort()
		for action in actions:
			var state: Dictionary = assembly["actions"][action]
			lines.append("%s: %s." % [action, "available" if state["available"] else "disabled; missing " + ", ".join(PackedStringArray(state["missing_functions"]))])
	if not found: lines.append("Select an owned manufactured tool and an observed mount.")
	lines.append("Fit replaces the installed part and returns it to loose inventory. Detach retains the part; unaffected functions may remain usable. Make inventory room.")
	lines.append("Mount compatibility does not guarantee useful capability. Starter shells cannot be modified by manufactured-part actions. Damage causes and future capability recovery are not observed.")
	lines.append("Fit/detach require construction power, station energy and current ownership/capacity; their energy cost is not quoted in this observation. Recycling also requires the host's matching specification, recycler power, energy and receiving capacity.")
	if pending: lines.append("Command pending: no fabricated output or changed mount confirmed; wait for the host receipt.")
	return "\n".join(lines)
