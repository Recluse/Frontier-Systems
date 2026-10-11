extends "res://tests/godot/player_inventory_components_test.gd"

## Socket-free ordinary pointer dispatch through the real client shell.
class PointerRemote extends RecordingRemote:
	func connect_host(_url: String, _invite: String) -> ServiceResult:
		return ServiceResult.success()

class PointerClient extends FirstPlayableBootstrap:
	func _create_client_remote() -> RemoteWorldRuntime:
		return PointerRemote.new()

var client: PointerClient
var viewport: SubViewport
var container: SubViewportContainer
var feedback: HabitatTargetFeedback
var canonical: String
var picked_items: Array[String] = []
var picked_sources: Array[String] = []
var picked_walls: Array[String] = []
var workstation_picks: int = 0
var pointer_started: bool = false

func settle() -> void:
	for _frame in range(8): await physics_frame

func unchanged(label: String) -> void:
	check(world.capture_world_snapshot_json().value == canonical, label + " preserves canonical snapshot")
	check(remote.sent.is_empty(), label + " queues no command")

func pointer(point: Vector2) -> void:
	# Reset entry after the first injection without relying on OS cursor location.
	if pointer_started: root.notify_mouse_exited()
	root.notify_mouse_entered()
	pointer_started = true
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.window_id = root.get_window_id()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)
	await settle()

func aim(target: Node3D, offset: Vector3 = Vector3(0, 2, 1.2)) -> void:
	root.gui_release_focus()
	client._habitat.camera.position = target.global_position + offset
	client._habitat.camera.look_at(target.global_position)
	await settle()

func world_click() -> void:
	await pointer(container.get_global_rect().get_center())

func run() -> void:
	create_timer(35.0).timeout.connect(func() -> void: check(false, "Pointer fixture deadline"); quit(1))
	OS.set_environment("FRONTIER_EVENT_URL", "")
	OS.set_environment("FRONTIER_EVENT_TOKEN", "")
	PlayerInputSettings.instance()._reset_map()
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1440, 900)
	world = WorldRuntime.new()
	world.resource_carriers_enabled = true
	root.add_child(world)
	check(world.start_simulation().is_success, "detached canonical fixture starts")
	world.get_node("SimulationRunner").set_physics_process(false)
	world.command_completed.connect(func(_request: SimulationCommand, result: ServiceResult) -> void: last = result)
	context = AuthenticatedCommandContext.for_local_development(&"local-inventory-actor", world.world_id, world.region_id)
	# Pay for a physical wall through existing deterministic command/tick seams.
	for _batch in range(4):
		move(ProductionSimulationSystem.SOURCE_POSITIONS["deposit.iron"])
		command("extract", {"deposit_id": "deposit.iron", "carrier_id": "resource-canister-1", "amount_milligrams": 1000000})
		move([0, 0, 0])
		command("unload_cargo", {"carrier_id": "resource-canister-1", "material": "ore.iron", "amount_milligrams": 1000000})
		command("process", {"recipe_id": "refine.iron"})
		for _tick in range(120): step()
	command("process", {"recipe_id": "craft.plate"})
	for _tick in range(120): step()
	command("materialize_plate", {})
	command("wall_build", {"item_id": frame()["production"]["components"][0], "position": [0, 0, -1000], "quarter_turn": 0})
	# Drop a real owned fixture backpack into the reachable tray.
	var drop := InventoryDevelopmentCommand.new()
	drop.command_id = &"pointer-fixture-drop"
	drop.authenticated_context = AuthenticatedCommandContext.for_local_development(&"local-inventory-target", world.world_id, world.region_id)
	drop.operation = "world"
	drop.payload = {"operation": "drop", "item_id": "backpack-1", "world_container_id": "world.tray-1", "destination_container_id": "", "slot_id": "", "expected_revision": frame()["inventory"]["inventory_revision"]}
	check(world.enqueue_command(drop).is_success, "fixture queues target backpack drop")
	step()
	check(last.is_success, "canonical backpack drop succeeds")
	client = PointerClient.new()
	root.add_child(client)
	client.set_process(false)
	remote = client._remote
	remote.set_process(false)
	remote.server_slot = 0
	var observation: Dictionary = frame()
	observation["position"] = [0, 950, 0]
	observation["players"] = []
	observation["terrain"] = {}
	check(remote._projection.accept_record(observation["production"]).is_success, "real client projection accepts fixture")
	remote._observation = observation.duplicate(true)
	remote.observation_received.emit(observation)
	remote.observation_received.emit(observation)
	client._habitat.character.read_local_keyboard = false
	client._habitat.character.set_physics_process(false)
	client._habitat.activate_inspection(HabitatInspectionCamera.Mode.OVERVIEW)
	client._habitat.camera.set_process(false)
	viewport = client._habitat.get_viewport()
	container = viewport.get_parent()
	for child in client._habitat.find_children("*", "Control", true, false):
		if child is HabitatTargetFeedback: feedback = child
	check(feedback != null, "actual habitat feedback exists")
	client._habitat.world_inventory.item_selected.connect(func(root_id: String, id: String) -> void: picked_items.append(JSON.stringify([root_id, id])))
	client._habitat.production.source_selected.connect(func(id: String) -> void: picked_sources.append(id))
	client._habitat.production.wall_selected.connect(func(id: String) -> void: picked_walls.append(id))
	client._habitat.production.workstation_selected.connect(func() -> void: workstation_picks += 1)
	await settle()
	canonical = world.capture_world_snapshot_json().value
	var item_key: String = JSON.stringify(["world.tray-1", "backpack-1"])
	var item: Node3D = client._habitat.world_inventory._visible_items[item_key]["mesh"]
	await aim(item, Vector3(0, 1.4, 3))
	await world_click()
	check(picked_items == [item_key], "ordinary click dispatches exact stable root/item pair")
	check(client._habitat.world_inventory._selected_key == item_key, "item card selects actual proxy")
	check(feedback.describe(feedback.selected).get("name", "").contains("backpack-1"), "feedback selects the clicked item")
	unchanged("item inspection")
	client._habitat.camera.rotation = Vector3(PI / 3.0, 0, 0)
	await settle()
	await world_click()
	check(feedback.selected == null and client._habitat.world_inventory._selected_key.is_empty() and not client._habitat.world_inventory._selection_label.visible, "empty click clears item card and target ring")
	unchanged("item empty-space clearing")
	await aim(item, Vector3(0, 1.4, 3))
	await world_click()
	check(picked_items.size() == 2 and feedback.describe(feedback.selected).get("name", "").contains("backpack-1"), "cleared item can be picked again")
	var source: Area3D = client._habitat.production._source_areas["deposit.ice"]
	await aim(source)
	await world_click()
	check(picked_sources == ["deposit.ice"] and feedback.selected == source, "switch dispatches correct stable source")
	check(client._production_panel._deposit.get_item_text(client._production_panel._deposit.selected) == "deposit.ice", "real source handler updates production picker")
	check(client._habitat.world_inventory._selected_key.is_empty(), "source switch clears obsolete item highlight")
	unchanged("source switch")
	var second_source: Area3D = client._habitat.production._source_areas["deposit.regolith"]
	await aim(second_source)
	await world_click()
	check(picked_sources == ["deposit.ice", "deposit.regolith"] and feedback.selected == second_source, "switching sources replaces stable target")
	unchanged("second source switch")
	# Ray into the sky: no target and no native target signal.
	client._habitat.camera.rotation = Vector3(PI / 3.0, 0, 0)
	await settle()
	check(WorldSelectionInput.ray_target(client._habitat.camera, Vector2(viewport.size) / 2.0).is_empty(), "empty-space fixture ray has no collider")
	await world_click()
	check(feedback.selected == null and client._habitat.world_inventory._selected_key.is_empty(), "empty click clears visual selection")
	check(picked_sources.size() == 2 and picked_items.size() == 2, "empty click emits no target selection")
	unchanged("empty-space clearing")
	var workstation: Area3D
	for child in client._habitat.production.get_children():
		if child is Area3D and child not in client._habitat.production._source_areas.values(): workstation = child
	client._tabs.current_tab = 1
	await aim(workstation)
	await world_click()
	check(workstation_picks == 1 and feedback.selected == workstation and client._tabs.current_tab == 0, "workstation click routes to real recipes tab")
	unchanged("workstation inspection")
	var wall_id: String = observation["production"]["walls"].keys()[0]
	var wall: StaticBody3D = client._habitat.production._spatial_walls[wall_id]
	await aim(wall)
	await world_click()
	var machinery: MachineryPanel = client._machinery_panel
	check(picked_walls == [wall_id] and feedback.selected == wall, "wall click dispatches exact stable wall")
	check(client._tabs.current_tab == 3 and machinery._selected(machinery._wall) == wall_id, "wall handler opens actual inspection panel")
	check(not machinery._coordinate_grid.visible and machinery._wall_build_button.disabled and not machinery._show_placement.button_pressed, "wall inspection is read-only and hides placement")
	unchanged("wall inspection")
	# Real UI pointer activation of the explicit placement transition.
	var scroll: ScrollContainer = machinery.get_parent()
	scroll.ensure_control_visible(machinery._new_wall)
	await settle()
	check(scroll.get_global_rect().encloses(machinery._new_wall.get_global_rect()), "placement button is visible in actual client pane")
	# Held look -> held UI cursor, through actual root/camera input handlers.
	var look := InputEventMouseButton.new()
	look.position = container.get_global_rect().get_center()
	look.global_position = look.position
	look.button_index = MOUSE_BUTTON_RIGHT
	look.pressed = true
	Input.parse_input_event(look)
	await settle()
	check(client._habitat.camera._looking, "injected look reaches the actual camera handler")
	if DisplayServer.get_name() != "headless":
		check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "native held look gives active camera capture")
	var cursor := InputEventKey.new()
	cursor.keycode = KEY_ALT
	cursor.physical_keycode = KEY_ALT
	cursor.location = KEY_LOCATION_LEFT
	cursor.pressed = true
	Input.parse_input_event(cursor)
	await settle()
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "held UI cursor releases camera capture for pointer controls")
	# End the right-button gesture before activating a different GUI control.
	look.pressed = false
	Input.parse_input_event(look)
	await settle()
	# Native capture may warp the pointer and update the inspection camera.
	await aim(wall)
	await pointer(machinery._new_wall.get_global_rect().get_center())
	check(picked_walls.size() == 1, "UI button cursor does not leak a world wall pick")
	check(machinery._selected(machinery._wall).is_empty() and machinery._coordinate_grid.visible and machinery._show_placement.button_pressed, "UI click enters explicit placement draft")
	check(root.gui_get_focus_owner() == machinery._axes[0].get_line_edit(), "coordinate editor owns UI focus")
	cursor.pressed = false
	Input.parse_input_event(cursor)
	await settle()
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "look and UI cursor release leave editor cursor visible")
	unchanged("explicit placement")
	var wall_picks_before: int = picked_walls.size()
	await world_click()
	check(picked_walls.size() == wall_picks_before and machinery._coordinate_grid.visible, "focused editor prevents world click from retargeting draft")
	unchanged("UI focus ownership")
	root.gui_release_focus()
	await world_click()
	check(picked_walls.size() == wall_picks_before + 1 and machinery._selected(machinery._wall) == wall_id, "released UI focus restores actual wall picking")
	unchanged("focus release")
	if OS.get_cmdline_user_args().has("--capture-pointer"):
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://var/ci/world-pointer-picking/captures")
		check(root.get_texture().get_image().save_png("res://var/ci/world-pointer-picking/captures/wall-inspection.png") == OK, "ignored internal native client capture")
	print("World pointer picking: %d failures; injected engine dispatch, no human acceptance" % failures)
	client.free()
	world.free()
	PlayerInputSettings.instance()._reset_map()
	quit(1 if failures else 0)
