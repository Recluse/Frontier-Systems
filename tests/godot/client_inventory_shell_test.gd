extends "res://tests/godot/player_inventory_components_test.gd"

## Actual client shell, injected keyboard and a socket-free command adapter.
## The fixture owns canonical state; observations/receipts are explicitly delivered.
class InventoryRemote extends RecordingRemote:
	func connect_host(_url: String, _invite: String) -> ServiceResult:
		return ServiceResult.success()

class InventoryClient extends FirstPlayableBootstrap:
	func _create_client_remote() -> RemoteWorldRuntime:
		return InventoryRemote.new()

var client: InventoryClient
var capture: bool = false

func settle() -> void:
	for _frame in range(6): await process_frame

func observe_shell() -> void:
	var record: Dictionary = frame()
	record["position"] = [0, 950, 0]
	record["players"] = []
	record["terrain"] = {}
	remote._observation = record.duplicate(true)
	remote.observation_received.emit(record)
	remote.observation_received.emit(record)
	client._habitat.character.read_local_keyboard = false
	client._habitat.character.set_physics_process(false)

func visible_receipt() -> void:
	await settle()
	var scroll: ScrollContainer = panel.get_parent()
	check(panel._result.is_visible_in_tree() and scroll.get_global_rect().encloses(panel._result.get_global_rect()), "matching feedback fully visible in actual shell")

func activate(operation: String) -> SimulationCommand:
	var button: Button = panel._inventory_buttons[operation]
	check(not button.disabled and button.is_visible_in_tree(), operation + " enabled and visible")
	var scroll: ScrollContainer = panel.get_parent()
	scroll.ensure_control_visible(button)
	button.grab_focus()
	await settle()
	scroll.ensure_control_visible(button)
	await settle()
	check(button.has_focus() and scroll.get_global_rect().intersects(button.get_global_rect()), operation + " focus in viewport")
	var before: int = remote.sent.size()
	var event := InputEventKey.new()
	event.keycode = KEY_ENTER
	event.physical_keycode = KEY_ENTER
	event.pressed = true
	root.push_input(event)
	await process_frame
	event = InputEventKey.new()
	event.keycode = KEY_ENTER
	event.physical_keycode = KEY_ENTER
	root.push_input(event)
	await settle()
	check(remote.sent.size() == before + 1, operation + " injected GUI activation queues once")
	button.release_focus()
	return remote.sent[-1]

func accepted(operation: String) -> void:
	var items: Array = frame()["inventory"]["items"].duplicate(true)
	var mass: Variant = frame()["inventory"]["mass_milligrams"]
	var production: Dictionary = frame()["production"].duplicate(true)
	var request: SimulationCommand = await activate(operation)
	check(frame()["inventory"]["items"] == items, "queued GUI action does not mutate items")
	apply(request)
	check(last.is_success, operation + " real owner accepts: " + last.message)
	remote.command_completed.emit(request, last)
	observe_shell()
	await visible_receipt()
	check(panel._pending.is_empty() and panel._result.text.contains("Host accepted"), operation + " matching receipt clears pending")
	var expected_items: Array = items.duplicate(true)
	var actual_items: Array = frame()["inventory"]["items"].duplicate(true)
	for item in expected_items: item.erase("container_id")
	for item in actual_items: item.erase("container_id")
	expected_items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["item_id"] < b["item_id"])
	actual_items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["item_id"] < b["item_id"])
	check(actual_items == expected_items, operation + " conserves unique item identities, definitions and condition")
	check(frame()["inventory"]["items"].size() == items.size() and frame()["inventory"]["mass_milligrams"] == mass, operation + " conserves item count and carried mass")
	for field: String in ["store", "cargo", "deposits", "energy_joules", "structures", "components"]:
		check(frame()["production"][field] == production[field], operation + " conserves production " + field)

func snap(name: String) -> void:
	if not capture: return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://var/ci/client-inventory-render")
	check(root.get_texture().get_image().save_png("res://var/ci/client-inventory-render/" + name + ".png") == OK, "internal ordinary capture")

func run() -> void:
	create_timer(30.0).timeout.connect(func() -> void: push_error("Inventory fixture deadline"); quit(1))
	capture = OS.get_cmdline_user_args().has("--capture-inventory")
	PlayerInputSettings.instance()._reset_map()
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1100, 700)
	world = WorldRuntime.new()
	root.add_child(world)
	check(world.start_simulation().is_success, "canonical fixture starts")
	world.get_node("SimulationRunner").set_physics_process(false)
	world.command_completed.connect(func(_request: SimulationCommand, result: ServiceResult) -> void: last = result)
	context = AuthenticatedCommandContext.for_local_development(&"local-inventory-target", world.world_id, world.region_id)
	client = InventoryClient.new()
	root.add_child(client)
	client.set_process(false)
	remote = client._remote
	remote.set_process(false)
	remote.server_slot = 0
	observe_shell()
	panel = client._inventory_panel
	client._open_panel(1)
	await settle()
	choose(panel._source, "storage.pouch-1")
	panel._fill_items()
	select_tool("crowbar-1")
	choose(panel._slot, "hand.right")
	panel._update_buttons()
	await accepted("equip")
	check(frame()["inventory"]["equipped"].has({"slot_id": "hand.right", "item_id": "crowbar-1"}), "owned tool bound to chosen hand")
	await accepted("select_hand")
	check(frame()["inventory"]["active_hand_slot_id"] == "hand.right", "chosen hand authoritative")
	await accepted("switch_hand")
	check(frame()["inventory"]["active_hand_slot_id"] != "hand.right", "switch changes active hand exactly once")
	choose(panel._destination, "body.human-1")
	panel._update_buttons()
	await accepted("unequip")
	choose(panel._source, "body.human-1")
	panel._fill_items()
	select_tool("crowbar-1")
	choose(panel._destination, "storage.pouch-1")
	panel._update_buttons()
	var request: SimulationCommand = await activate("move")
	var pinned: Dictionary = panel._pending_inventory.duplicate(true)
	var waiting: String = panel._result.text
	var unrelated := InventoryDevelopmentCommand.new()
	unrelated.command_id = &"unrelated-receipt"
	remote.command_completed.emit(unrelated, ServiceResult.failure(&"fixture", "Unrelated failure"))
	check(panel._pending_inventory == pinned and panel._result.text == waiting, "unrelated receipt preserves exact pending target and feedback")
	# Real intervening command makes this queued request stale; no fake rejection.
	var competing := InventoryDevelopmentCommand.new()
	competing.command_id = &"fixture-hand-change"
	competing.operation = "self"
	competing.payload = {"operation": "switch_hand", "item_id": "", "source_container_id": "", "destination_container_id": "", "slot_id": "", "expected_revision": frame()["inventory"]["inventory_revision"]}
	apply(competing)
	check(last.is_success, "real intervening hand command")
	var owner: InventorySimulationSystem = world.get_simulation_system(InventorySimulationSystem.SYSTEM_ID)
	var before: String = JSON.stringify(owner.capture_snapshot().value["owner"])
	apply(request)
	check(not last.is_success, "real stale move rejects")
	check(JSON.stringify(owner.capture_snapshot().value["owner"]) == before, "rejected move conserves canonical inventory owner/ledger/receipts")
	remote.command_completed.emit(request, last)
	await visible_receipt()
	check(panel._result.text.contains("Host rejected") and panel._pending.is_empty(), "matching rejection visible and clears pending")
	await snap("rejected")
	observe_shell()
	select_tool("crowbar-1")
	panel._update_buttons()
	await accepted("move")
	for item in frame()["inventory"]["items"]:
		if item["item_id"] == "crowbar-1": check(item["container_id"] == "storage.pouch-1", "retry moves same unique item into owned storage")
	await snap("accepted")
	client.free()
	world.free()
	PlayerInputSettings.instance().release_all()
	print("Actual-shell inventory fixture: %d failures; injected GUI, fixture selectors, explicit observations/receipts; no sockets or human acceptance" % failures)
	quit(1 if failures else 0)
