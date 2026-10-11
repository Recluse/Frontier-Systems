extends "res://tests/godot/machinery_runtime_test.gd"


func finish() -> void:
	var observed: Dictionary = production.observation(context).value
	var original: String = JSON.stringify(observed)
	var helper := MachineryOperationFeedback.new()
	var preview := MachineryPreview.new()
	root.add_child(preview)
	var panel := MachineryPanel.new()
	root.add_child(panel)
	panel.configure(world)
	var own: Dictionary = inventory.own_inventory_observation(context).value
	var record: Dictionary = {"production": observed, "inventory": own, "position": [0, 0, 0]}
	panel.observe(record)
	panel.select_machine(observed["machinery"]["placements"].keys()[0])
	var selected_machine: String = panel._selected(panel._machine)
	var selected_part: String = panel._selected(panel._part)
	var selected_recipe: String = panel._selected(panel._recipe)
	var snapshot: String = world.capture_world_snapshot_json().value
	panel._choose_group(1)
	check(panel._recipe.visible and not panel._coordinate_grid.visible and not panel._socket.visible, "operation hides assembly geometry and sockets")
	panel._choose_group(0)
	check(not panel._recipe.visible and panel._coordinate_grid.visible and panel._socket.visible, "assembly visibility returns after roundtrip")
	check(panel._selected(panel._machine) == selected_machine and panel._selected(panel._part) == selected_part and panel._selected(panel._recipe) == selected_recipe, "navigation retains stable identities and recipe")
	check(world.capture_world_snapshot_json().value == snapshot, "group roundtrip does not mutate finite-material world")
	panel._send("machine_run")
	snapshot = JSON.stringify([production.capture_snapshot().value, inventory.capture_snapshot().value])
	var pending: String = panel._pending
	var identity: String = panel._request_identity.text
	check(not pending.is_empty() and identity.contains(selected_machine) and identity.contains(selected_recipe) and identity.contains("Production revision"), "real queued operation pins machine recipe revision request")
	panel._choose_group(1)
	panel._choose_group(0)
	check(panel._pending == pending and panel._request_identity.text == identity and panel._recipe.disabled and panel._kind.disabled and panel._socket.disabled and panel._other.disabled, "pending group roundtrip freezes every command selector and exact identity")
	check(JSON.stringify([production.capture_snapshot().value, inventory.capture_snapshot().value]) == snapshot, "pending navigation preserves production and inventory before host tick")
	step(1)
	check(panel._pending.is_empty() and panel._feedback.text == ("Completed" if last.is_success else EngineeringFailureGuidance.describe(last, last.message)), "matching real host result clears only completed request")
	panel._choose_group(1)
	check(panel._request_identity.text == identity and panel._feedback.visible, "host outcome retains submitted identity across groups")
	observed = production.observation(context).value
	original = JSON.stringify(observed)
	record["production"] = observed
	panel.observe(record)
	preview.observe(observed)
	check(helper.observe(observed), "scoped production telemetry accepted")
	var id: String = observed["machinery"]["placements"].keys()[0]
	var body: int = preview.find_children("*", "StaticBody3D", true, false)[0].get_instance_id()
	check(not preview._labels[id]["label"].text.contains("READY"), "enabled never claims ready")
	check(panel._status.text.contains("Buffers are separate"), "grid total does not imply pooled energy")
	check(JSON.stringify(observed) == original, "helpers do not mutate source projection")
	var candidate: Dictionary = observed.duplicate(true)
	candidate["last_tick"] += 1
	candidate["machinery"]["placements"][id]["enabled"] = false
	candidate["machinery"]["placements"][id]["energy"] = 0
	candidate["machinery"]["jobs"][id] = {"recipe": "extract.ice", "progress": 4, "energy_spent": 17, "paused": false}
	check(helper.observe(candidate), "disabled telemetry accepted")
	check(helper.machines[id]["text"].contains("Isolated / disabled") and helper.machines[id]["text"].contains("Buffer 0 J"), "disabled empty buffer explained without inventing energy")
	check(helper.machines[id]["job"].contains("Not advancing"), "disabled unpaused job not shown running")
	for physical in candidate["machinery"]["inventory_items"]:
		if physical["item_id"] == id: physical["condition_permille"] = 0
	candidate["last_tick"] += 1
	candidate["machinery"]["placements"][id]["enabled"] = true
	helper.observe(candidate)
	check(helper.machines[id]["text"].contains("broken frame (retained)"), "broken enabled frame remains visible without capability promise")
	for physical in candidate["machinery"]["inventory_items"]:
		if physical["item_id"] == id: physical["condition_permille"] = 450
		if candidate["machinery"]["mounts"].get(physical["item_id"], "") == id: physical["condition_permille"] = 0
	candidate["last_tick"] += 1
	helper.observe(candidate)
	check(helper.machines[id]["text"].contains("damaged frame 450/1000") and helper.machines[id]["text"].contains("Broken modules retained"), "damage and unavailable component combinations explained")
	candidate["machinery"]["jobs"][id]["paused"] = true
	candidate["last_tick"] += 1
	helper.observe(candidate)
	check(helper.machines[id]["job"].contains("Paused · Resume required"), "explicit pause needs resume")
	candidate["machinery"]["jobs"][id]["paused"] = false
	candidate["last_tick"] += 1
	helper.observe(candidate)
	check(helper.machines[id]["job"].contains("Not advancing"), "unchanged progress cannot claim running")
	candidate["machinery"]["jobs"][id]["progress"] += 1
	candidate["last_tick"] += 1
	helper.observe(candidate)
	check(helper.machines[id]["job"].contains("Running · observed progress"), "running requires actual observed progress")
	helper.observe(candidate)
	check(helper.machines[id]["job"].contains("Running · observed progress"), "equal tick telemetry retains observed activity without flicker")
	preview.observe(candidate)
	check(preview.find_children("*", "StaticBody3D", true, false)[0].get_instance_id() == body, "energy condition and job updates retain body instance")
	candidate["machinery"]["jobs"].erase(id)
	candidate["last_tick"] += 1
	helper.observe(candidate)
	check(helper.machines[id]["job"].contains("completion/cancellation not distinguished"), "job removal cannot manufacture completion receipt")
	preview.observe(candidate)
	record["production"] = candidate
	panel.observe(record)
	panel.select_machine(id)
	panel._pending = "pending-fixture"
	panel._pending_deploy = {"machine_id": id, "position": [800, 0, 600], "mode": "surface", "display_size": Vector3(2.5, 1.5, 1.3)}
	panel._refresh_placement()
	check(not panel._pending_deploy.is_empty() and panel._machine.disabled and panel._placement_status.text.contains("host"), "operation telemetry preserves pending deployment feedback")
	var stale: Dictionary = candidate.duplicate(true)
	stale["last_tick"] -= 1
	check(not helper.observe(stale) and helper.machines.is_empty(), "older tick clears stale helper text")
	preview.observe(stale)
	check(preview._labels.is_empty(), "stale preview clears settled labels")
	record["production"] = stale
	panel.observe(record)
	check(panel._record.is_empty() and panel._status.text.contains("Stale"), "stale panel clears actions and telemetry")
	helper.observe({})
	preview.observe({})
	panel.observe({})
	check(helper.machines.is_empty() and preview._labels.is_empty() and panel._status.text.contains("unavailable"), "disconnect clears all operation telemetry")
	check(helper.observe(observed), "new connection resets tick history")
	check(not helper.machines[id]["job"].contains("previous batch"), "reconnect does not retain ended job inference")
	panel.free()
	preview.free()
	world.free()
	print("Machinery operation feedback: %d failures" % failures)
	quit(1 if failures else 0)
