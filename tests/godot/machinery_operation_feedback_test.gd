extends "res://tests/godot/machinery_runtime_test.gd"


func finish() -> void:
	var observed: Dictionary = production.observation(context).value
	var original: String = JSON.stringify(observed)
	var helper := MachineryOperationFeedback.new()
	check(helper.observe(observed), "paid scoped fixture accepted for recipe prerequisites")
	var workshop: Dictionary = observed["machinery"]
	var carrier_machine: String = ""
	for module in workshop["mounts"]:
		if workshop["parts"][module]["kind"] != "socket": continue
		for physical in workshop["inventory_items"]:
			if physical["item_id"] == "resource-canister-1" and physical["container_id"] == InventorySimulationSystem.factory_storage_id(module): carrier_machine = workshop["mounts"][module]
	var prerequisites: String = helper.recipe_text(carrier_machine, "refine.iron")
	check(not carrier_machine.is_empty() and prerequisites.contains("resource-canister-1") and prerequisites.contains("ice 1.000 kg") and not prerequisites.contains("resource-canister-2"), "paid fitted contents scoped to selected machine; carried spare excluded")
	check(prerequisites.contains("ore.iron 1.000 kg") and prerequisites.contains("1000 J") and prerequisites.contains("power, controller, refinery") and prerequisites.contains("observed at least 0 / required 1000000 mg"), "observed recipe requirements distinguish unrelated canister feedstock")
	check(prerequisites.contains("Output amounts, allocation and free capacity quote unavailable") and prerequisites.contains("No active batch observed to resume"), "no yield readiness or resume promise")
	check(helper.recipe_text(carrier_machine, "extract.ice").contains("quote unavailable"), "extraction requirements absent from observation stay unknown")
	var legacy: Dictionary = observed.duplicate(true)
	legacy["schema_version"] = 7
	legacy.erase("recipe_requirements")
	check(helper.observe(legacy) and helper.recipe_text(carrier_machine, "refine.iron").contains("quote unavailable"), "legacy recipe requirements remain unknown")
	var malformed: Dictionary = observed.duplicate(true)
	malformed["machinery"]["inventory_items"] = "invalid"
	check(not helper.observe(malformed) and helper.recipe_text(carrier_machine, "refine.iron").contains("unavailable"), "invalid observation clears prerequisite details without crash")
	check(helper.observe(observed), "valid recovery restores prerequisite details")
	var preview := MachineryPreview.new()
	root.add_child(preview)
	var panel := MachineryPanel.new()
	root.add_child(panel)
	panel.configure(world)
	var own: Dictionary = inventory.own_inventory_observation(context).value
	var record: Dictionary = {"production": observed, "inventory": own, "position": [0, 0, 0]}
	await check_paid_shell(record, carrier_machine)
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
	check(panel._record.is_empty() and panel._status.text.contains("Stale") and panel._recipe_prerequisites.text.contains("unavailable"), "stale panel clears actions telemetry and prerequisites")
	helper.observe({})
	preview.observe({})
	panel.observe({})
	check(helper.machines.is_empty() and preview._labels.is_empty() and panel._status.text.contains("unavailable") and panel._recipe_prerequisites.text.contains("unavailable"), "disconnect clears all operation telemetry and recipe details")
	check(helper.observe(observed), "new connection resets tick history")
	check(not helper.machines[id]["job"].contains("previous batch"), "reconnect does not retain ended job inference")
	panel.free()
	preview.free()
	world.free()
	print("Machinery operation feedback: %d failures" % failures)
	quit(1 if failures else 0)


## Reuse the no-listener real shell with this richer paid deployed fixture.
func check_paid_shell(record: Dictionary, machine_id: String) -> void:
	var shell = preload("res://tests/godot/integrated_panel_layout_test.gd").FixtureClient.new()
	root.add_child(shell)
	shell.set_process(false)
	shell.set_process_unhandled_input(false)
	shell._remote.set_process(false)
	shell._habitat.character.read_local_keyboard = false
	shell._habitat.character.set_physics_process(false)
	var panel: MachineryPanel = shell._machinery_panel
	panel.observe(record)
	panel.select_machine(machine_id)
	for index in range(panel._recipe.item_count):
		if panel._recipe.get_item_metadata(index) == "refine.iron": panel._recipe.select(index)
	panel._choose_group(1)
	shell._tabs.current_tab = 3
	var snapshot: String = world.capture_world_snapshot_json().value
	for viewport_size: Vector2i in [Vector2i(1920, 1080), Vector2i(1100, 720)]:
		root.size = viewport_size
		for _frame in range(6): await process_frame
		var scroll := panel.get_parent() as ScrollContainer
		scroll.ensure_control_visible(panel._recipe_prerequisites)
		for _frame in range(6): await process_frame
		check(panel._recipe_prerequisites.text.contains("resource-canister-1") and panel._recipe_prerequisites.text.contains("ore.iron"), "real paid shell shows selected fitted canister and recipe")
		check(panel._recipe_prerequisites.size.x <= scroll.size.x + 1 and panel._recipe_prerequisites.get_line_count() == panel._recipe_prerequisites.get_visible_line_count(), "paid desktop/narrow canister prerequisites wrap within shell")
		check(scroll.get_global_rect().encloses(panel._recipe_prerequisites.get_global_rect()), "paid desktop/narrow prerequisite text fully revealed by shell scroll")
	check(world.capture_world_snapshot_json().value == snapshot, "paid shell recipe display preserves canonical matter energy and provenance")
	shell.free()
