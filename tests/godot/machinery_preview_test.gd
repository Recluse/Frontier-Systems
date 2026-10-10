extends "res://tests/godot/machinery_runtime_test.gd"


func finish() -> void:
	var preview := MachineryPreview.new()
	root.add_child(preview)
	var observed: Dictionary = production.observation(context).value
	preview.observe(observed)
	var bodies: Array = preview.find_children("*", "StaticBody3D", true, false)
	check(bodies.size() == observed["machinery"]["placements"].size(), "each settled assembly has one static body")
	check(preview.find_children("*", "RigidBody3D", true, false).is_empty(), "modules and cables create no independent rigid bodies")
	check(not preview._socket_labels.is_empty(), "attached resource canisters have actual content labels")
	var first_id: String = observed["machinery"]["placements"].keys()[0]
	var instance: int = bodies[0].get_instance_id()
	var energy: int = int(observed["machinery"]["placements"][first_id]["energy"]) + 1
	observed["machinery"]["placements"][first_id]["energy"] = energy
	preview.observe(observed)
	check(preview.find_children("*", "StaticBody3D", true, false)[0].get_instance_id() == instance, "changing telemetry does not rebuild physics assemblies")
	check(preview._labels[first_id]["label"].text.contains("%d J" % energy), "cached machine label updates with observed energy")
	check(int(production.capture_snapshot().value["machinery"]["placements"][first_id]["energy"]) != energy, "presentation updates cannot change canonical power")
	preview.free()
	print("Machinery presentation: %d failures" % failures)
	world.free()
	quit(1 if failures else 0)
