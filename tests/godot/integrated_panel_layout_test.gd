extends "res://tests/godot/player_inventory_components_test.gd"

## Paid domain fixture inside the actual client shell; no sockets or local saves.
class ShellRemote extends RecordingRemote:
	func connect_host(_url: String, _invite: String) -> ServiceResult:
		return ServiceResult.success()

class FixtureClient extends FirstPlayableBootstrap:
	func _create_client_remote() -> RemoteWorldRuntime:
		return ShellRemote.new()

var client: FixtureClient
var capture: bool = false

func settle() -> void:
	for _frame in range(6): await process_frame

func key(code: Key, shift: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.shift_pressed = shift
	event.pressed = true
	root.push_input(event)
	await process_frame
	event = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.shift_pressed = shift
	root.push_input(event)
	await settle()

func observe_shell() -> void:
	var record: Dictionary = frame()
	record["position"] = [0, 950, 0]
	record["players"] = []
	record["terrain"] = {} # Terrain is outside this detached presentation fixture.
	check(remote._projection.accept_record(record["production"]).is_success, "real production projection accepts paid fixture")
	remote._observation = record.duplicate(true)
	remote.observation_received.emit(record)
	# Production panel is created on first observation; replay to its tool observer.
	remote.observation_received.emit(record)
	client._habitat.character.read_local_keyboard = false
	client._habitat.character.set_physics_process(false)

func visible(control: Control, scroll: ScrollContainer) -> bool:
	var rect: Rect2 = control.get_global_rect()
	var viewport: Rect2 = scroll.get_global_rect()
	return control.is_visible_in_tree() and viewport.encloses(rect)

func bounded(control: Control, width: float) -> void:
	if not control.is_visible_in_tree(): return
	check(control.size.x <= width + 1.0, "integrated bounded width: " + control.get_class())
	if control is Label:
		check(control.get_line_count() == control.get_visible_line_count(), "integrated label has all wrapped lines")
	for child in control.get_children():
		if child is Control: bounded(child, width)

func snap(name: String) -> void:
	if not capture: return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://var/ci/integrated-panel-render")
	check(root.get_texture().get_image().save_png("res://var/ci/integrated-panel-render/" + name + ".png") == OK, "ignored ordinary client-shell capture")

func run() -> void:
	create_timer(25.0).timeout.connect(func() -> void: check(false, "Integrated fixture deadline" ); quit(1))
	PlayerInputSettings.instance()._reset_map()
	capture = OS.get_cmdline_user_args().has("--capture-integrated")
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1920, 1080)
	world = WorldRuntime.new()
	world.resource_carriers_enabled = true
	root.add_child(world)
	check(world.start_simulation().is_success, "detached paid fixture starts")
	world.get_node("SimulationRunner").set_physics_process(false)
	world.command_completed.connect(func(_request: SimulationCommand, result: ServiceResult) -> void: last = result)
	context = AuthenticatedCommandContext.for_local_development(&"local-inventory-actor", world.world_id, world.region_id)
	for _batch in range(6):
		move(ProductionSimulationSystem.SOURCE_POSITIONS["deposit.iron"])
		command("extract", {"deposit_id": "deposit.iron", "carrier_id": "resource-canister-1", "amount_milligrams": 1000000})
		move([0, 0, 0])
		command("unload_cargo", {"carrier_id": "resource-canister-1", "material": "ore.iron", "amount_milligrams": 1000000})
		command("process", {"recipe_id": "refine.iron"})
		for _tick in range(120): step()
	command("fabricate_equipment", {"blueprint_id": "equipment.extractor"})
	command("fabricate_tool_part", {"blueprint_id": "part.head.basic", "expected_tool_revision": frame()["tools"]["state_revision"]})
	client = FixtureClient.new()
	root.add_child(client)
	client.set_process(false)
	client.set_process_unhandled_input(false)
	remote = client._remote
	remote.set_process(false)
	remote.server_slot = 0
	observe_shell()
	panel = client._inventory_panel
	var production: LocalProductionPanel = client._production_panel
	var tool: String = frame()["production"]["structures"].keys()[0]
	var loose: String = frame()["tools"]["loose_parts"][0]["part_id"]
	select_tool(tool)
	choose(panel._part_blueprints, "part.head.basic")
	choose(panel._loose_parts, loose)
	choose(panel._tool_mounts, "head")
	panel._update_buttons()
	var before: String = world.capture_world_snapshot_json().value
	for viewport_size: Vector2i in [Vector2i(1920, 1080), Vector2i(1100, 720)]:
		root.size = viewport_size
		(client._tabs.get_parent() as HSplitContainer).split_offset = 420 if viewport_size.x == 1100 else 540
		client._tabs.current_tab = 0
		await settle()
		check(client._tabs.get_global_rect().end.x <= root.size.x, "actual tab shell fits desktop/narrow window")
		check(client._content.get_child(1) is OverlayThemeController, "real client theme header retained")
		bounded(client._content, client._scroll.size.x)
		client._scroll.scroll_vertical = 0
		await settle()
		await snap("%d-header" % viewport_size.x)
		for index in range(production._sections.size()):
			production._navigation.select(index)
			production._navigation.item_selected.emit(index)
			production._navigation.grab_focus()
			await settle()
			check(visible(production._navigation, client._scroll), "outer scrolling reveals real task chooser")
		production._navigation.select(2)
		production._navigation.item_selected.emit(2)
		production._salvage_button.grab_focus()
		await settle()
		check(visible(production._salvage_button, production._section_scroll), "inner focus reveals lower equipment action")
		check(visible(production._salvage_button, client._scroll), "outer focus reveals focused action through nested viewport")
		await snap("%d-workstation" % viewport_size.x)
		client._tabs.current_tab = 1
		await settle()
		var inventory_scroll := panel.get_parent() as ScrollContainer
		bounded(panel, inventory_scroll.size.x)
		panel._tool_mounts.grab_focus()
		await settle()
		await key(KEY_TAB)
		check(root.gui_get_focus_owner() == panel._component_buttons["fit_tool_part"], "integrated Tab reaches fit")
		check(visible(panel._component_buttons["fit_tool_part"], inventory_scroll), "integrated focus reveals fit")
		await key(KEY_TAB, true)
		check(root.gui_get_focus_owner() == panel._tool_mounts, "integrated Shift+Tab returns to mount")
		inventory_scroll.grab_focus()
		var scroll_before: int = inventory_scroll.scroll_vertical
		await key(KEY_DOWN)
		check(inventory_scroll.scroll_vertical > scroll_before, "integrated focused pane scrolls")
		await snap("%d-inventory" % viewport_size.x)
	check(world.capture_world_snapshot_json().value == before, "layout/navigation preserves canonical paid fixture")
	panel._part_action("fit_tool_part")
	var pinned: Dictionary = panel._pending_component.duplicate(true)
	var request: SimulationCommand = remote.sent[-1]
	observe_shell()
	await settle()
	check(panel._pending_component == pinned, "integrated pending pins exact IDs/revisions")
	check(visible(panel._result, panel.get_parent()), "full integrated pending receipt visible")
	check(panel._result.text.contains(tool) and panel._result.text.contains(loose) and panel._result.text.contains("Production revision: %d" % pinned["expected_revision"]) and panel._result.text.contains("Tool revision: %d" % pinned["expected_tool_revision"]), "pending includes exact stable targets and both revisions")
	await snap("narrow-pending")
	root.size = Vector2i(1920, 1080)
	await settle()
	check(visible(panel._result, panel.get_parent()), "full desktop pending receipt visible")
	await snap("desktop-pending")
	root.size = Vector2i(1100, 720)
	(panel.get_parent() as ScrollContainer).scroll_vertical = 0
	await settle()
	apply(request)
	check(last.is_success, "integrated real paid fit")
	remote.command_completed.emit(request, last)
	observe_shell()
	await settle()
	check(panel._result.text.contains("Host accepted") and visible(panel._result, panel.get_parent()), "full accepted receipt visible")
	await snap("narrow-accepted")
	root.size = Vector2i(1920, 1080)
	await settle()
	check(visible(panel._result, panel.get_parent()), "full desktop accepted receipt visible")
	await snap("desktop-accepted")
	root.size = Vector2i(1100, 720)
	client._tabs.current_tab = 0
	production._send("process", {"recipe_id": "refine.iron"})
	await settle()
	check(not production._pending.is_empty(), "workstation pending intent retained")
	check(visible(production._feedback, client._scroll), "full workstation pending feedback visible")
	request = remote.sent[-1]
	remote.command_completed.emit(request, ServiceResult.failure(&"fixture_rejection", "Observed stock changed. Refresh the workstation before retrying; the host has applied no payment for this rejected request."))
	await settle()
	check(production._feedback.text.contains("Observed stock changed") and visible(production._feedback, client._scroll), "full workstation host rejection visible")
	bounded(client._content, client._scroll.size.x)
	check((client._tabs.get_parent() as Control).get_global_rect().end.x <= root.size.x, "long host failure does not expand shell beyond window")
	await snap("narrow-rejected")
	client.free()
	world.free()
	if failures == 0: print("PASS integrated client shell: paid fixture, desktop/narrow wrapping, focus/scroll, exact pending and full host feedback; no sockets.")
	quit(0 if failures == 0 else 1)
