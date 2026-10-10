extends SceneTree


func _initialize() -> void:
	var items: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/inventory/items.default.v1.json"))
	var equipment: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/production/equipment-blueprints.v1.json"))["blueprints"]
	var coverage: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/production/construction-coverage.v1.json"))
	var components: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/tools/catalog.v1.json"))["components"]
	var parts: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/tools/part-blueprints.v1.json"))["blueprints"]
	var buildable: Dictionary = {}
	var definitions: Dictionary = {}
	var failures: int = 0
	if coverage["schema_version"] != 1 or coverage["special_factories"] != {"item.plate.prototype": "materialize_plate", "item.tool-part.fabricated": "fabricate_tool_part"}:
		push_error("Coverage must reference only the actual special factories.")
		failures += 1
	for design in equipment.values(): buildable[design["definition_id"]] = true
	for kind in MachineryWorkshop.KINDS: buildable[MachineryWorkshop.definition(kind)] = true
	for id in coverage["special_factories"]: buildable[id] = true
	for item in items: definitions[item["definition_id"]] = item
	for id in coverage["fixture_equivalents"]:
		var replacement: String = coverage["fixture_equivalents"][id]
		if not definitions.has(id) or not definitions.has(replacement) or not buildable.has(replacement):
			push_error("Fixture equivalent has no real construction path: " + id)
			failures += 1
			continue
		var original: Dictionary = definitions[id]
		var fabricated: Dictionary = definitions[replacement]
		if original["storage"] != fabricated["storage"] or original["volume_millilitres"] != fabricated["volume_millilitres"]:
			push_error("Fixture equivalent changed storage or physical volume: " + id)
			failures += 1
		for tag in original["tags"]:
			if not fabricated["tags"].has(tag):
				push_error("Fixture equivalent lost a capability: " + id)
				failures += 1
	for id in definitions:
		if not buildable.has(id) and not coverage["fixture_equivalents"].has(id):
			push_error("Inventory definition lacks a construction path: " + id)
			failures += 1
	for id in buildable:
		if not definitions.has(id):
			push_error("Construction output has no inventory definition: " + id)
			failures += 1
	for id in components:
		var found: bool = false
		for part in parts.values():
			if part["definition_id"] == id: found = true
		if not found:
			push_error("Tool component has no fabrication blueprint: " + id)
			failures += 1
	print("Construction catalog coverage: %d definitions, %d component designs, %d failures" % [definitions.size(), components.size(), failures])
	quit(1 if failures else 0)
