extends "res://tests/godot/integrated_panel_layout_test.gd"

## Real shell and domain owners, injected GUI keys; no sockets or live services.
func pick_text(picker: OptionButton, id: String) -> void:
	for index in range(picker.item_count):
		if picker.get_item_text(index) == id: picker.select(index)

func button_named(ui: Node, caption: String) -> Button:
	for node in ui.find_children("*", "Button", true, false):
		if node.text == caption: return node
	check(false, "button exists: " + caption)
	return null

func activate_button(button: Button) -> SimulationCommand:
	check(button != null and not button.disabled, "intended action enabled")
	if button == null or button.disabled: return null
	await settle()
	button.grab_focus()
	await settle()
	var ancestor: Node = button.get_parent()
	while not ancestor is ScrollContainer: ancestor = ancestor.get_parent()
	check(button.has_focus() and visible(button, ancestor), "keyboard action revealed in actual shell: " + button.text)
	var sent: int = remote.sent.size()
	var before: String = world.capture_world_snapshot_json().value
	var confirm := InputEventKey.new()
	confirm.keycode = KEY_ENTER
	confirm.physical_keycode = KEY_ENTER
	confirm.pressed = true
	root.push_input(confirm)
	# Hold through the actual 100 ms observation refresh, not just a lucky frame.
	await create_timer(0.2).timeout
	check(button.button_pressed and remote.sent.size() == sent, "held Enter survives refresh without early activation: " + button.text)
	confirm = InputEventKey.new()
	confirm.keycode = KEY_ENTER
	confirm.physical_keycode = KEY_ENTER
	root.push_input(confirm)
	await settle()
	check(remote.sent.size() == sent + 1, "one Enter queues one intent: " + button.text + " sent=" + str(sent) + " now=" + str(remote.sent.size()) + " pressed=" + str(button.button_pressed) + " focused=" + str(button.has_focus()) + " disabled=" + str(button.disabled) + " pending=" + client._production_panel._pending + " feedback=" + client._production_panel._feedback.text)
	check(world.capture_world_snapshot_json().value == before, "queued GUI intent cannot mutate canonical state")
	button.release_focus()
	return remote.sent[-1] if remote.sent.size() > sent else null

func paid_action(button: Button, operation: String) -> SimulationCommand:
	var request: SimulationCommand = await activate_button(button)
	if request == null: return null
	check(request.operation == operation, "exact submitted operation: " + operation)
	apply(request)
	check(last.is_success, "real owner accepts " + operation + ": " + last.message)
	remote.command_completed.emit(request, last)
	observe_shell()
	await settle()
	check(client._production_panel._pending.is_empty(), "matching receipt settles exact pending request")
	return request

func recipe(id: String) -> void:
	client._habitat.production.workstation_selected.emit()
	await settle()
	var ui: LocalProductionPanel = client._production_panel
	check(root.gui_get_focus_owner() == null, "world workstation selection retains gameplay input")
	ui._recipe.grab_focus()
	await settle()
	check(root.gui_get_focus_owner() == ui._recipe and visible(ui._recipe, client._scroll), "recipe keyboard focus is revealed in actual shell")
	choose(ui._recipe, id)
	ui.refresh()
	await paid_action(button_named(ui, "Run selected recipe"), "process")
	check(not frame()["production"]["job"].is_empty(), "accepted recipe is reserved work, not completed output")
	for _tick in range(120): step()
	observe_shell()
	await settle()
	check(frame()["production"]["job"].is_empty(), "fresh observation reports completed batch")

func run() -> void:
	create_timer(45.0).timeout.connect(func() -> void: push_error("Engineering shell deadline"); quit(1))
	capture = OS.get_cmdline_user_args().has("--capture-integrated")
	PlayerInputSettings.instance()._reset_map()
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1920, 1080)
	world = WorldRuntime.new()
	world.resource_carriers_enabled = true
	root.add_child(world)
	check(world.start_simulation().is_success, "finite canonical world starts")
	world.get_node("SimulationRunner").set_physics_process(false)
	world.command_completed.connect(func(_request: SimulationCommand, result: ServiceResult) -> void: last = result)
	context = AuthenticatedCommandContext.for_local_development(&"local-inventory-actor", world.world_id, world.region_id)
	client = FixtureClient.new()
	root.add_child(client)
	client.set_process(false)
	client.set_process_unhandled_input(false)
	remote = client._remote
	remote.set_process(false)
	remote.server_slot = 0
	world.get_simulation_system(ProductionSimulationSystem.SYSTEM_ID).batch_completed.connect(func(recipe_id: String, tick_number: int) -> void:
		remote._receive({"type": "batch_completed", "recipe_id": recipe_id, "tick_number": tick_number}))
	observe_shell()
	var physical_ids: Array[String] = []
	var extraction: SimulationCommand
	for cycle in range(2):
		for _batch in range(2):
			client._open_panel(0)
			move(ProductionSimulationSystem.SOURCE_POSITIONS["deposit.iron"])
			observe_shell()
			var ui: LocalProductionPanel = client._production_panel
			ui._navigation.select(0)
			ui._navigation.item_selected.emit(0)
			pick_text(ui._deposit, "deposit.iron")
			pick_text(ui._carrier, "resource-canister-1")
			ui._amount.value = 1000
			ui.refresh()
			extraction = await paid_action(ui._extract_button, "extract")
			if extraction == null: quit(1); return
			check(extraction.payload["deposit_id"] == "deposit.iron" and extraction.payload["carrier_id"] == "resource-canister-1" and extraction.payload["amount_milligrams"] == 1000000, "exact finite source/canister/mass")
			move([0, 0, 0])
			observe_shell()
			pick_text(ui._cargo_material, "ore.iron")
			ui.refresh()
			var unload: SimulationCommand = await paid_action(ui._unload_button, "unload_cargo")
			check(ui._feedback.text.contains(String(unload.command_id)) and ui._feedback.text.contains("resource-canister-1") and ui._feedback.text.contains("ore.iron; 1000000 mg"), "host unload receipt retains exact identity")
			client._open_panel(1)
			await recipe("refine.iron")
		await recipe("craft.plate")
		await paid_action(button_named(client._production_panel, "Collect printed plate into inventory"), "materialize_plate")
		var components: Array = frame()["production"]["components"]
		check(components.size() == 1, "one paid physical plate exists")
		var plate_id: String = components[0]
		check(not physical_ids.has(plate_id), "repeat loop produces a new stable physical identity")
		physical_ids.append(plate_id)
		pick_text(client._production_panel._components, plate_id)
		await paid_action(button_named(client._production_panel, "Recycle selected carried plate"), "recycle_component")
		var production: Dictionary = frame()["production"]
		check(production["components"].is_empty() and production["store"]["plate"] == 0, "physical recycle consumes that plate exactly once")
		check(production["deposits"]["deposit.iron"] == 10000000 - (cycle + 1) * 2000000 and production["store"]["iron"] == (cycle + 1) * 1200000 and production["store"]["tailings"] == (cycle + 1) * 800000 and production["store"]["ore.iron"] == 0 and production["cargo"]["resource-canister-1"]["ore.iron"] == 0, "repeat finite loop conserves all 10 kg of source matter")
	# Place an additional paid physical plate through the current Construction panel.
	await recipe("craft.plate")
	await paid_action(button_named(client._production_panel, "Collect printed plate into inventory"), "materialize_plate")
	var construction_plate: String = frame()["production"]["components"][0]
	client._open_panel(3)
	var machinery: MachineryPanel = client._machinery_panel
	choose(machinery._part, construction_plate)
	machinery._new_wall.pressed.emit()
	machinery._axes[2].value = -1.0
	var wall_request: SimulationCommand = await paid_action(machinery._wall_build_button, "wall_build")
	var walls: Dictionary = frame()["production"]["walls"].duplicate(true)
	check(walls.size() == 1 and frame()["production"]["components"].is_empty(), "paid physical plate becomes one persistent wall")
	var wall_id: String = walls.keys()[0]
	check(wall_request.payload["item_id"] == construction_plate and walls[wall_id]["position"] == [0, 0, -1000], "construction receipt uses exact consumed plate and observed wall target")
	# Real checkpoint files in unique temporary test storage; UI receipt delivered by adapter.
	client._open_panel(2)
	var save_request: CheckpointRequest = await activate_button(client._host_actions[3])
	var snapshot: String = world.capture_world_snapshot_json().value
	var directory: String = "user://engineering-shell-%d" % Time.get_ticks_usec()
	var written: ServiceResult = LocalWorldSaveStore.write_checkpoint(directory, 1, snapshot)
	check(written.is_success, "real disk checkpoint completes")
	remote.command_completed.emit(save_request, written)
	observe_shell()
	await settle()
	check(client._checkpoint_status.text.contains("confirmed on disk") and visible(client._checkpoint_status, client._checkpoint_scroll), "matching save result automatically revealed after observation")
	client._checkpoint_status.grab_focus()
	await settle()
	check(client._checkpoint_status.has_focus(), "checkpoint feedback accessible to keyboard")
	await snap("engineering-checkpoint")
	var abandoned: CheckpointRequest = await activate_button(client._host_actions[3])
	var sent: int = remote.sent.size()
	remote.connection_closed.emit("Fixture disconnect after save submission")
	remote.command_completed.emit(abandoned, ServiceResult.success())
	await settle()
	check(client._checkpoint_status.text.contains("outcome unknown"), "late success cannot confirm disconnected save")
	var checkpoint: ServiceResult = LocalWorldSaveStore.read_latest(directory)
	check(checkpoint.is_success, "real disk checkpoint reads")
	world.free()
	world = WorldRuntime.new()
	world.resource_carriers_enabled = true
	root.add_child(world)
	check(world.restore_world_snapshot_json(checkpoint.value["snapshot_json"]).is_success and world.start_simulation().is_success, "replacement canonical owner restores checkpoint")
	world.get_node("SimulationRunner").set_physics_process(false)
	world.command_completed.connect(func(_request: SimulationCommand, result: ServiceResult) -> void: last = result)
	observe_shell()
	await settle()
	check(remote.sent.size() == sent and client._checkpoint_status.text.contains("outcome unknown"), "fresh reconnect observation cannot replay or confirm abandoned request")
	var recovered: Dictionary = frame()
	check(recovered["production"]["deposits"]["deposit.iron"] == 6000000 and recovered["production"]["store"]["iron"] == 1400000 and recovered["production"]["store"]["tailings"] == 1600000 and recovered["production"]["walls"] == walls, "fresh recovery observes exact finite loop balances and stable physical wall")
	apply(extraction)
	for field: String in ["state_revision", "deposits", "store", "cargo", "components", "structures", "energy_joules", "job"]:
		check(frame()["production"][field] == recovered["production"][field], "retained extraction replay preserves " + field + " after recovery")
	await snap("engineering-recovered")
	client.free()
	world.free()
	for name in ["world-a.json", "world-b.json"]:
		if FileAccess.file_exists(directory.path_join(name)): DirAccess.remove_absolute(directory.path_join(name))
	DirAccess.remove_absolute(directory)
	PlayerInputSettings.instance().release_all()
	await process_frame
	print("Engineering shell keyboard/finite loop/disk recovery: %d failures; scripted input, no human acceptance" % failures)
	quit(1 if failures else 0)
