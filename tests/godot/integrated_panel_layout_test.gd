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
	for _batch in range(9):
		move(ProductionSimulationSystem.SOURCE_POSITIONS["deposit.iron"])
		command("extract", {"deposit_id": "deposit.iron", "carrier_id": "resource-canister-1", "amount_milligrams": 1000000})
		move([0, 0, 0])
		command("unload_cargo", {"carrier_id": "resource-canister-1", "material": "ore.iron", "amount_milligrams": 1000000})
		command("process", {"recipe_id": "refine.iron"})
		for _tick in range(120): step()
	command("process", {"recipe_id": "craft.plate"})
	for _tick in range(120): step()
	command("materialize_plate", {})
	command("fabricate_equipment", {"blueprint_id": "equipment.extractor"})
	command("fabricate_tool_part", {"blueprint_id": "part.head.basic", "expected_tool_revision": frame()["tools"]["state_revision"]})
	command("machine_craft", {"kind": "frame"})
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
	var machinery: MachineryPanel = client._machinery_panel
	var plate: String = frame()["production"]["components"][0]
	choose(machinery._part, plate)
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
		client._tabs.current_tab = 3
		machinery._placement_kind.item_selected.emit(0)
		var selected_part: String = MachineryPanel._selected(machinery._part)
		for group_index in [0, 1, 0]:
			machinery._group.select(group_index)
			machinery._group.item_selected.emit(group_index)
			machinery._group.grab_focus()
			await settle()
			var group_scroll := machinery.get_parent() as ScrollContainer
			bounded(machinery, group_scroll.size.x)
			check(visible(machinery._group, group_scroll), "desktop/narrow keyboard focus reveals group chooser")
			check(machinery._recipe.is_visible_in_tree() == (group_index == 1) and machinery._coordinate_grid.is_visible_in_tree() == (group_index == 0), "real shell groups isolate recipes from assembly placement")
			check(MachineryPanel._selected(machinery._part) == selected_part, "real shell group roundtrip retains physical part identity")
			await key(KEY_TAB)
			var focused: Control = root.gui_get_focus_owner()
			check(focused != null and focused.is_visible_in_tree(), "Tab from chooser reaches visible control")
			if focused != null:
				await settle()
				check(visible(focused, group_scroll), "keyboard target revealed through machinery scroll")
			await key(KEY_TAB, true)
			check(machinery._group.has_focus(), "Shift Tab returns to machinery group chooser")
		check((client._tabs.get_parent() as HSplitContainer).get_child(0).size.x >= 300, "machinery groups preserve world camera area")
		machinery._placement_kind.item_selected.emit(1)
		await settle()
		var machinery_scroll := machinery.get_parent() as ScrollContainer
		bounded(machinery, machinery_scroll.size.x)
		check(not machinery._kind.is_visible_in_tree() and not machinery._recipe.is_visible_in_tree() and machinery._wall.is_visible_in_tree(), "real shell wall mode hides unrelated controls")
		check((client._tabs.get_parent() as HSplitContainer).get_child(0).size.x >= 300, "wall mode preserves world camera area")
		machinery._new_wall.pressed.emit()
		await settle()
		check(visible(machinery._axes[0], machinery_scroll), "wall start reveals X through real scroll pane")
		await key(KEY_TAB)
		check(machinery._axes[1].get_line_edit().has_focus() and visible(machinery._axes[1], machinery_scroll), "real shell Tab reveals wall Y")
		await key(KEY_TAB)
		await key(KEY_TAB)
		check(machinery._wall_turn.has_focus() and visible(machinery._wall_turn, machinery_scroll), "real shell Tab reveals wall orientation")
		await key(KEY_TAB, true)
		check(machinery._axes[2].get_line_edit().has_focus(), "real shell Shift Tab returns to Z")
		machinery._wall_remove_button.grab_focus()
		await settle()
		check(visible(machinery._wall_remove_button, machinery_scroll), "real shell focus reveals lower wall removal")
		await snap("%d-walls" % viewport_size.x)
	check(world.capture_world_snapshot_json().value == before, "layout/navigation preserves canonical paid fixture")
	machinery._send("wall_build")
	var wall_pending: Dictionary = machinery._pending_wall.duplicate(true)
	var wall_request: SimulationCommand = remote.sent[-1]
	await settle()
	check(visible(machinery._placement_status, machinery.get_parent()), "submitting wall reveals complete pinned feedback from lower build control")
	var wall_receipt: String = machinery._placement_status.text
	machinery._placement_kind.item_selected.emit(0)
	observe_shell()
	await settle()
	check(machinery._pending_wall == wall_pending and machinery._placement_kind.selected == 1 and machinery._placement_status.text == wall_receipt, "real shell mode switch and observation retain exact pending plate/pose/revision")
	for viewport_size: Vector2i in [Vector2i(1920, 1080), Vector2i(1100, 720)]:
		root.size = viewport_size
		(machinery.get_parent() as ScrollContainer).ensure_control_visible(machinery._placement_status)
		await settle()
		check(visible(machinery._placement_status, machinery.get_parent()), "full wall pending identity/pose feedback fits real desktop/narrow pane")
	remote.command_completed.emit(wall_request, ServiceResult.failure(&"fixture_rejection", "Host rejected this exact wall target; refresh owned plate observation before retrying."))
	await settle()
	check(machinery._feedback.text.contains("Host rejected this exact wall target"), "real wall host rejection remains visible in focused mode")

	check(visible(machinery._feedback, machinery.get_parent()), "complete wall outcome accessible in narrow pane")
	check(world.capture_world_snapshot_json().value == before, "real shell wall intent and rejection preserve canonical snapshot")
	client._tabs.current_tab = 1
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
	client._tabs.current_tab = 3
	machinery._choose_mode(0)
	var machine_id: String = frame()["production"]["machinery"]["parts"].keys()[0]
	machinery.select_machine(machine_id)
	machinery._send("machine_deploy")
	var deploy_request: SimulationCommand = remote.sent[-1]
	var pinned_deploy: Dictionary = machinery._pending_deploy.duplicate(true)
	var pinned_identity: String = machinery._request_identity.text
	var submitted_snapshot: String = world.capture_world_snapshot_json().value
	for viewport_size: Vector2i in [Vector2i(1920, 1080), Vector2i(1100, 720)]:
		root.size = viewport_size
		for group_index in [1, 0]:
			machinery._group.item_selected.emit(group_index)
			await settle()
			check(machinery._pending_deploy == pinned_deploy and machinery._request_identity.text == pinned_identity, "desktop/narrow groups retain exact deployment identity pose mode revision")
			check(machinery._machine.disabled and machinery._recipe.disabled and machinery._kind.disabled and machinery._other.disabled and machinery._socket.disabled, "pending groups freeze shared and hidden selectors")
			(machinery.get_parent() as ScrollContainer).ensure_control_visible(machinery._request_identity)
			await settle()
			check(visible(machinery._request_identity, machinery.get_parent()), "full submitted machinery identity fits desktop/narrow viewport")
			bounded(machinery, (machinery.get_parent() as ScrollContainer).size.x)
	check(world.capture_world_snapshot_json().value == submitted_snapshot, "real shell pending group switches preserve canonical paid snapshot")
	apply(deploy_request)
	remote.command_completed.emit(deploy_request, last)
	observe_shell()
	await settle()
	check(machinery._pending.is_empty() and machinery._request_identity.text == pinned_identity, "matching real host deploy feedback retains exact submitted identity")
	check(machinery._feedback.text == ("Completed" if last.is_success else EngineeringFailureGuidance.describe(last, last.message)), "real paid host deploy result matches panel feedback")
	machinery._send("machine_run")
	var pending_operation: String = machinery._pending
	var operation_identity: String = machinery._request_identity.text
	remote.connection_closed.emit("Connection lost; submitted machinery operation outcome is unknown.")
	for group_index in [1, 0, 1]: machinery._group.item_selected.emit(group_index)
	await settle()
	check(machinery._pending == pending_operation and machinery._request_identity.text == operation_identity and machinery._feedback.text.contains("unknown"), "disconnect and group switches retain pending operation and explicit uncertainty")
	check(machinery._recipe.disabled and machinery._kind.disabled and machinery._machine.disabled, "disconnect cannot reenable pending machinery selectors")
	client.free()
	world.free()
	if failures == 0: print("PASS integrated client shell: paid fixture, desktop/narrow wrapping, focus/scroll, exact pending and full host feedback; no sockets.")
	quit(0 if failures == 0 else 1)
