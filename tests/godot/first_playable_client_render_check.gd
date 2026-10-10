extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	OS.set_environment("FRONTIER_HOST_URL", "ws://127.0.0.1:27850")
	OS.set_environment("FRONTIER_INVITE_KEY", "render-player-one-key-000000000000000")
	var world := WorldRuntime.new()
	world.resource_carriers_enabled = true
	root.add_child(world)
	var host := FirstPlayableHost.new()
	root.add_child(host)
	var keys: Array[String] = [OS.get_environment("FRONTIER_INVITE_KEY"), "render-player-two-key-000000000000000"]
	if not host.configure(world, keys, 27850).is_success or not world.start_simulation().is_success:
		quit(1)
		return
	var client := FirstPlayableBootstrap.new()
	root.add_child(client)
	await create_timer(3.0).timeout
	if client._latest.is_empty() or client._production_panel == null:
		push_error("Graphical client failed to authenticate or build its production HUD.")
		quit(1)
		return
	client._habitat.character.read_local_keyboard = false
	if not await _walk(client, Vector3(-9.0, 0.95, 1.0)):
		quit(1)
		return
	for _collection in range(2):
		if not await _guide_action(client):
			quit(1)
			return
	if not await _walk(client, Vector3(-6.0, 0.95, 2.0)):
		quit(1)
		return
	for _step in range(8):
		if not await _guide_action(client):
			quit(1)
			return
	if not client._production_panel._guide._recrafted:
		push_error("The graphical collection guide did not finish the physical resource loop.")
		quit(1)
		return
	var equipment_route: bool = OS.get_cmdline_user_args().has("--equipment-fabrication")
	if equipment_route:
		if not await _equipment_route(client):
			quit(1)
			return
	else:
		client._production_panel._send("materialize_plate", {})
		await create_timer(0.5).timeout
		client._drop_first_definition("item.plate.prototype")
		await create_timer(0.5).timeout
	client._habitat.activate_inspection(HabitatInspectionCamera.Mode.OVERVIEW)
	client._habitat.camera._radius = 14.0
	client._habitat.camera._update_overview()
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var directory: String = "res://reports/equipment-fabrication" if equipment_route else "res://reports/first-playable"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var error: Error = image.save_png(directory.path_join("client.png"))
	print("First playable graphical client completed its seven-step loop using local physics and authenticated guide commands; screenshot result: %d" % error)
	client.free()
	host.free()
	world.free()
	quit(0 if error == OK else 1)


func _equipment_route(client: FirstPlayableBootstrap) -> bool:
	var panel: LocalProductionPanel = client._production_panel
	panel._send("materialize_plate", {})
	await create_timer(0.5).timeout
	var components: Array = client._latest["production"]["components"]
	if components.is_empty():
		return false
	panel._send("recycle_component", {"item_id": components[0]})
	await create_timer(0.5).timeout
	for index in range(panel._blueprint.item_count):
		if panel._blueprint.get_item_metadata(index) == "equipment.canister":
			panel._blueprint.select(index)
	panel._fabricate_equipment()
	await create_timer(0.5).timeout
	var structures: Dictionary = client._latest["production"]["structures"]
	if structures.size() != 1:
		push_error("Graphical equipment fabrication failed: " + panel._feedback.text)
		return false
	var id: String = structures.keys()[0]
	for index in range(panel._carrier.item_count):
		if panel._carrier.get_item_text(index) == id:
			panel._carrier.select(index)
	for index in range(panel._cargo_material.item_count):
		if panel._cargo_material.get_item_text(index) == "iron":
			panel._cargo_material.select(index)
	panel._amount.value = 100.0
	panel._cargo_action("load_cargo")
	await create_timer(0.5).timeout
	client._tabs.current_tab = 1
	var inventory: PlayerInventoryPanel = client._inventory_panel
	for index in range(inventory._items.item_count):
		if inventory._items.get_item_metadata(index)["item_id"] == id:
			inventory._items.select(index)
	for index in range(inventory._destination.item_count):
		if inventory._destination.get_item_metadata(index) == "storage.backpack-2":
			inventory._destination.select(index)
	inventory._self_action("move")
	await create_timer(0.5).timeout
	inventory._inspect()
	var found: bool = false
	for item in client._latest["inventory"]["items"]:
		if item["item_id"] == id and item["container_id"] == "storage.backpack-2":
			found = true
	if not found or not inventory._details.text.contains("1.10 kg") or not inventory._details.text.contains("Recoverable construction"):
		push_error("Graphical fabricated carrier nesting/inspection failed: " + inventory._result.text)
		return false
	print("Graphical equipment route: fabricate, load, move into backpack and inspect structural/contents mass passed.")
	for index in range(inventory._items.item_count):
		if inventory._items.get_item_metadata(index)["item_id"] == "extractor-1":
			inventory._items.select(index)
			inventory._inspect()
	if inventory._tool_parts.item_count != 3 or not inventory._details.text.contains("Component condition (authoritative)"):
		push_error("Graphical tool component inspection failed.")
		return false
	print("Graphical tool inspection: scoped extractor frame/head/drive condition and actions passed.")
	for index in range(inventory._items.item_count):
		if inventory._items.get_item_metadata(index)["item_id"] == id:
			inventory._items.select(index)
			inventory._inspect()
	return true


func _walk(client: FirstPlayableBootstrap, target: Vector3) -> bool:
	var character: LocalHabitatCharacter = client._habitat.character
	var deadline: int = Time.get_ticks_msec() + 5000
	while Vector2(character.position.x - target.x, character.position.z - target.z).length() > 0.15 and Time.get_ticks_msec() < deadline:
		var direction := Vector2(target.x - character.position.x, target.z - character.position.z).normalized()
		character.set_motion_intent(direction, false)
		await process_frame
	character.set_motion_intent(Vector2.ZERO, false)
	await create_timer(0.6).timeout
	if Vector2(character.position.x - target.x, character.position.z - target.z).length() > 0.3:
		push_error("Graphical character failed to walk to the interaction target.")
		return false
	return true


func _guide_action(client: FirstPlayableBootstrap) -> bool:
	var panel: LocalProductionPanel = client._production_panel
	await create_timer(0.25).timeout
	panel.refresh()
	if panel._guide_button.disabled:
		push_error("Expected the contextual guide action to be available.")
		return false
	panel._guide_action()
	var deadline: int = Time.get_ticks_msec() + 5000
	while (not panel._pending.is_empty() or not panel._guide._requested_recipe.is_empty()) and Time.get_ticks_msec() < deadline:
		await process_frame
	await create_timer(0.25).timeout
	if panel._feedback.text.begins_with("Rejected") or not panel._pending.is_empty() or not panel._guide._requested_recipe.is_empty():
		push_error("Graphical guide action failed: " + panel._feedback.text)
		return false
	return true
