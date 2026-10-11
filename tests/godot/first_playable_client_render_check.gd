extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var terrain_route: bool = OS.get_cmdline_user_args().has("--terrain")
	var port: int = 27854 if terrain_route else 27850
	OS.set_environment("FRONTIER_HOST_URL", "ws://127.0.0.1:%d" % port)
	OS.set_environment("FRONTIER_INVITE_KEY", "render-player-one-key-000000000000000")
	var world := WorldRuntime.new()
	world.resource_carriers_enabled = true
	root.add_child(world)
	var host := FirstPlayableHost.new()
	root.add_child(host)
	var keys: Array[String] = [OS.get_environment("FRONTIER_INVITE_KEY"), "render-player-two-key-000000000000000"]
	if not host.configure(world, keys, port).is_success or not world.start_simulation().is_success:
		quit(1)
		return
	var client := FirstPlayableBootstrap.new()
	root.add_child(client)
	# Override before the first network poll; never read a player's real journal.
	var retry_directory: String = "user://first-playable-render-intent-%d" % Time.get_ticks_usec()
	client._remote.terrain_retry_directory = retry_directory
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
	var machinery_route: bool = OS.get_cmdline_user_args().has("--machinery")
	var wall_route: bool = OS.get_cmdline_user_args().has("--walls")
	var equipment_route: bool = OS.get_cmdline_user_args().has("--equipment-fabrication")
	var tool_parts_route: bool = OS.get_cmdline_user_args().has("--tool-parts")
	if terrain_route:
		if not await _terrain_route(client):
			quit(1)
			return
	elif wall_route:
		if not await _wall_route(client):
			quit(1)
			return
	elif machinery_route:
		if not await _machinery_route(client):
			quit(1)
			return
	elif tool_parts_route:
		if not await _tool_parts_route(client):
			quit(1)
			return
	elif equipment_route:
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
	if terrain_route:
		client._habitat.camera.position = Vector3(-5.75, 2.3, 4.5)
		client._habitat.camera.look_at(Vector3(-5.75, 1.0, 3.0))
	if wall_route:
		(client._machinery_panel.get_parent() as ScrollContainer).scroll_vertical = 650
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var directory: String = "res://reports/equipment-fabrication" if equipment_route else "res://reports/first-playable"
	if tool_parts_route: directory = "res://reports/tool-parts"
	if machinery_route: directory = "res://reports/machinery"
	if wall_route: directory = "res://reports/spatial-walls"
	if terrain_route: directory = "res://docs/gallery/terrain-controls"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var error: Error = image.save_png(directory.path_join("terrain-dig-fill.png" if terrain_route else "client.png"))
	print("First playable graphical client completed its seven-step loop using local physics and authenticated guide commands; screenshot result: %d" % error)
	client.free()
	DirAccess.remove_absolute(retry_directory)
	host.free()
	world.free()
	quit(0 if error == OK else 1)


func _terrain_route(client: FirstPlayableBootstrap) -> bool:
	var production: LocalProductionPanel = client._production_panel
	for _batch in range(3):
		if not await _walk(client, Vector3(-9.0, 0.95, 1.0)): return false
		production._send("extract", {"deposit_id": "deposit.iron", "carrier_id": "resource-canister-1", "amount_milligrams": 1000000})
		await create_timer(0.5).timeout
		if not await _walk(client, Vector3(-6.0, 0.95, 2.0)): return false
		production._send("unload_cargo", {"carrier_id": "resource-canister-1", "material": "ore.iron", "amount_milligrams": 1000000})
		await create_timer(0.5).timeout
		production._send("process", {"recipe_id": "refine.iron"})
		await create_timer(2.5).timeout
	for index in range(production._blueprint.item_count):
		if production._blueprint.get_item_metadata(index) == "equipment.shovel": production._blueprint.select(index)
	production._fabricate_equipment()
	await create_timer(0.5).timeout
	var shovel: String = ""
	for item in client._latest["inventory"]["items"]:
		if item["definition_id"] == "item.shovel.fabricated": shovel = item["item_id"]
	if shovel.is_empty(): return false
	client._tabs.current_tab = 1
	var inventory: PlayerInventoryPanel = client._inventory_panel
	for index in range(inventory._items.item_count):
		if inventory._items.get_item_metadata(index)["item_id"] == shovel: inventory._items.select(index)
	for index in range(inventory._slot.item_count):
		if inventory._slot.get_item_metadata(index) == "hand.left": inventory._slot.select(index)
	inventory._self_action("equip")
	await create_timer(0.5).timeout
	inventory._self_action("select_hand")
	await create_timer(0.5).timeout
	if not await _walk(client, Vector3(-6, 0.95, 3)): return false
	client._tabs.current_tab = 4
	var terrain: TerrainControlsPanel = client._terrain_panel
	terrain._amount.value = 0.25
	if terrain._dig.disabled: return false
	terrain._dig.pressed.emit()
	await create_timer(0.6).timeout
	if terrain._feedback.text != "Completed" or client._latest["terrain"]["transfers"].size() != 1: return false
	terrain._target.select(1)
	terrain._refresh()
	if terrain._fill.disabled: return false
	terrain._fill.pressed.emit()
	await create_timer(0.6).timeout
	if terrain._feedback.text != "Completed" or not client._latest["terrain"]["transfers"].is_empty() or client._latest["terrain"]["cells"]["terrain.dirt.fill"]["state"]["mass_milligrams"] != 250000: return false
	if client._terrain_preview._markers.size() != 2 or not terrain._status.text.contains("Host capability: ready"): return false
	print("Graphical terrain: finite shovel fabrication, inventory equip, local physical walking, real dig/fill button route, scoped escrow and two stable cell markers passed.")
	return true


func _wall_route(client: FirstPlayableBootstrap) -> bool:
	client._production_panel._send("materialize_plate", {})
	await create_timer(0.5).timeout
	var plates: Array = client._latest["production"]["components"]
	if plates.size() != 1: return false
	client._tabs.current_tab = 3
	var panel: MachineryPanel = client._machinery_panel
	_select_wall_plate(panel, plates[0])
	panel._axes[0].value = 0
	panel._axes[1].value = 0
	panel._axes[2].value = -1
	panel._send("wall_build")
	await create_timer(0.6).timeout
	if panel._feedback.text != "Completed" or client._latest["production"]["walls"].size() != 1:
		push_error("Graphical wall construction failed: " + panel._feedback.text)
		return false
	var id: String = client._latest["production"]["walls"].keys()[0]
	var preview: ProceduralProductionPreview = client._habitat.production
	if not preview._spatial_walls.has(id): return false
	var query := PhysicsRayQueryParameters3D.create(Vector3(-6, 1, 2), Vector3(-6, 1, 0))
	var hit: Dictionary = preview.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.get("collider") != preview._spatial_walls[id]:
		push_error("Placed wall has no matching native physics collision.")
		return false
	panel.select_wall(id)
	panel._send("wall_remove")
	await create_timer(0.6).timeout
	if not panel._feedback.text.contains("Host accepted removal of wall " + id) or not client._latest["production"]["walls"].is_empty() or preview._spatial_walls.has(id): return false
	plates = client._latest["production"]["components"]
	if plates.size() != 1: return false
	_select_wall_plate(panel, plates[0])
	panel._send("wall_build")
	await create_timer(0.6).timeout
	if panel._feedback.text != "Completed": return false
	print("Graphical walls: construct, native collision, select, remove, recover plate and rebuild through real authenticated UI passed.")
	return true


func _select_wall_plate(panel: MachineryPanel, id: String) -> void:
	for index in range(panel._part.item_count):
		if panel._part.get_item_metadata(index) == id:
			panel._part.select(index)
			return


func _tool_parts_route(client: FirstPlayableBootstrap) -> bool:
	var production: LocalProductionPanel = client._production_panel
	production._send("materialize_plate", {})
	await create_timer(0.5).timeout
	var components: Array = client._latest["production"]["components"]
	if components.is_empty(): return false
	production._send("recycle_component", {"item_id": components[0]})
	await create_timer(0.5).timeout
	for _batch in range(3):
		if not await _walk(client, Vector3(-9.0, 0.95, 1.0)): return false
		production._send("extract", {"deposit_id":"deposit.iron", "carrier_id":"resource-canister-1", "amount_milligrams":1000000})
		await create_timer(0.5).timeout
		if not await _walk(client, Vector3(-6.0, 0.95, 2.0)): return false
		production._send("unload_cargo", {"carrier_id":"resource-canister-1", "material":"ore.iron", "amount_milligrams":1000000})
		await create_timer(0.5).timeout
		production._send("process", {"recipe_id":"refine.iron"})
		await create_timer(2.5).timeout
	production._send("fabricate_equipment", {"blueprint_id":"equipment.extractor"})
	await create_timer(0.5).timeout
	var tool: String = client._latest["production"]["structures"].keys()[0]
	client._tabs.current_tab = 1
	var panel: PlayerInventoryPanel = client._inventory_panel
	for blueprint in ["part.head.basic", "part.controller.space"]:
		for index in range(panel._part_blueprints.item_count):
			if panel._part_blueprints.get_item_metadata(index) == blueprint: panel._part_blueprints.select(index)
		panel._part_action("fabricate_tool_part")
		await create_timer(0.5).timeout
		for index in range(panel._items.item_count):
			if panel._items.get_item_metadata(index)["item_id"] == tool: panel._items.select(index)
		panel._inspect()
		var mount: String = "head" if blueprint == "part.head.basic" else "module"
		for index in range(panel._tool_mounts.item_count):
			if panel._tool_mounts.get_item_metadata(index) == mount: panel._tool_mounts.select(index)
		var incoming: String = ""
		for part in client._latest["tools"]["loose_parts"]:
			if (mount == "head" and part["material_id"] == "grade.iron.basic") or (mount == "module" and part["definition_id"] == "part.controller"): incoming = part["part_id"]
		for index in range(panel._loose_parts.item_count):
			if panel._loose_parts.get_item_metadata(index) == incoming: panel._loose_parts.select(index)
		panel._part_action("fit_tool_part")
		await create_timer(0.5).timeout
		panel._inspect()
	if panel._tool_parts.item_count != 4 or not panel._details.text.contains("action.scan: available") or client._latest["tools"]["loose_parts"].size() != 1:
		push_error("Graphical part fabrication/replacement/upgrade failed: " + panel._result.text)
		return false
	print("Graphical tool parts: manufacture, replace head, retain old part and fit controller through inventory controls passed.")
	return true


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


func _machinery_route(client: FirstPlayableBootstrap) -> bool:
	client._production_panel._send("process", {"recipe_id": "salvage.plate"})
	await create_timer(2.0).timeout
	var panel: MachineryPanel = client._machinery_panel
	client._tabs.current_tab = 3
	for kind in ["frame", "controller", "power", "solar"]:
		panel._kind.select(MachineryWorkshop.KINDS.keys().find(kind))
		panel._send("machine_craft")
		await create_timer(0.5).timeout
		if panel._feedback.text != "Completed":
			push_error("Construction UI craft: " + panel._feedback.text)
			return false
		if kind != "frame":
			var workshop: Dictionary = client._latest["production"]["machinery"]
			for index in range(panel._part.item_count):
				var id: String = String(panel._part.get_item_metadata(index))
				if workshop["parts"].has(id) and workshop["parts"][id]["kind"] == kind: panel._part.select(index)
			panel._send("machine_fit")
			await create_timer(0.5).timeout
			if panel._feedback.text != "Completed": return false
	panel._axes[2].value = -1.0
	panel._send("machine_deploy")
	await create_timer(1.0).timeout
	if panel._feedback.text != "Completed" or client._machinery_preview.get_child_count() == 0:
		push_error("Construction UI deploy: " + panel._feedback.text)
		return false
	print("Construction UI assembled and deployed a powered generator through authenticated controls.")
	return true
