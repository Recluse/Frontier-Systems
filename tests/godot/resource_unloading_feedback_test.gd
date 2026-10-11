extends "res://tests/godot/player_inventory_components_test.gd"

class ObservedWorld extends WorldRuntime:
	var override_view: Dictionary = {}
	var override_enabled: bool = false
	func production_observation(actor: AuthenticatedCommandContext) -> ServiceResult:
		return ServiceResult.success(override_view) if override_enabled else super.production_observation(actor)

func pick(picker: OptionButton, id: String) -> void:
	for index in range(picker.item_count):
		if picker.get_item_text(index) == id: picker.select(index)

func run() -> void:
	world = ObservedWorld.new()
	world.resource_carriers_enabled = true
	root.add_child(world)
	check(world.start_simulation().is_success, "fixture starts")
	world.get_node("SimulationRunner").set_physics_process(false)
	context = AuthenticatedCommandContext.for_local_development(&"local-inventory-actor", world.world_id, world.region_id)
	var requests: Array[SimulationCommand] = []
	world.command_completed.connect(func(request: SimulationCommand, result: ServiceResult) -> void:
		last = result
		requests.append(request))
	move(ProductionSimulationSystem.SOURCE_POSITIONS["deposit.iron"])
	command("extract", {"deposit_id": "deposit.iron", "carrier_id": "resource-canister-1", "amount_milligrams": 1000000})
	move([0, 0, 0])
	var outer := ScrollContainer.new()
	outer.size = Vector2(420, 500)
	outer.follow_focus = true
	root.add_child(outer)
	var ui := LocalProductionPanel.new()
	outer.add_child(ui)
	check(ui.configure(world).is_success, "actual production panel configures")
	pick(ui._carrier, "resource-canister-1")
	pick(ui._cargo_material, "ore.iron")
	ui._amount.value = 500
	ui.refresh()
	var before: Dictionary = frame()
	var canonical: Dictionary = frame()
	check(ui._unload_details.text.contains("production.store") and ui._unload_details.text.contains(str(world.world_id)) and ui._unload_details.text.contains("station identity unavailable"), "exact scoped store without invented station ID")
	check(ui._unload_details.text.contains("ore.iron 1.000 kg") and ui._unload_details.text.contains("stock: 0 mg") and ui._unload_details.text.contains("500000 mg"), "exact observed stock, cargo and intended amount")
	ui._cargo_action("unload_cargo")
	var pinned: Dictionary = ui._cargo_pending.duplicate(true)
	var other := ProductionDevelopmentCommand.new()
	other.command_id = &"unrelated-receipt"
	other.operation = "unload_cargo"
	ui._on_completed(other, ServiceResult.success())
	check(ui._cargo_pending == pinned and not ui._pending.is_empty(), "unrelated receipt cannot resolve pinned unload")
	pick(ui._cargo_material, "ice")
	ui._amount.value = 100
	ui.refresh()
	check(ui._cargo_pending == pinned and ui._unload_details.text.contains("Pinned pending unload_cargo: canister resource-canister-1; material ore.iron; 500000 mg"), "changed intent cannot retarget pending payload")
	var missing: Dictionary = before["production"].duplicate(true)
	missing["cargo"].erase("resource-canister-1")
	(world as ObservedWorld).override_view = missing
	(world as ObservedWorld).override_enabled = true
	ui.refresh()
	check(ui._carrier.get_item_text(ui._carrier.selected) == "resource-canister-1" and ui._carrier.is_item_disabled(ui._carrier.selected), "removed selected carrier retained unavailable")
	check(ui._cargo_pending == pinned and ui._unload_button.disabled, "removed selection cannot retarget queued work")
	(world as ObservedWorld).override_enabled = false
	check(frame() == canonical, "presentation and queue conserve canonical snapshot before tick")
	step()
	check(last.is_success and int(frame()["production"]["store"]["ore.iron"]) == 500000 and int(frame()["production"]["cargo"]["resource-canister-1"]["ore.iron"]) == 500000, "real unload conserves exact finite material identity")
	check(ui._feedback.text.contains("Host receipt " + str(requests[-1].command_id)) and ui._feedback.text.contains("ore.iron; 500000 mg") and ui._feedback.text.contains("production.store"), "exact receipt keeps submitted material rather than current intent")
	pick(ui._cargo_material, "ore.iron")
	ui._amount.value = 1000
	ui._cargo_action("unload_cargo")
	before = frame()
	step()
	check(not last.is_success and frame()["production"]["cargo"] == before["production"]["cargo"] and frame()["production"]["store"] == before["production"]["store"] and frame()["production"]["deposits"] == before["production"]["deposits"], "real rejected underflow conserves all finite material")
	check(ui._feedback.text.contains(last.message) and ui._feedback.text.contains("ore.iron; 1000000 mg"), "rejection keeps exact intent and reason")
	missing = frame()["production"].duplicate(true)
	missing["cargo"].erase("resource-canister-1")
	(world as ObservedWorld).override_view = missing
	(world as ObservedWorld).override_enabled = true
	ui.refresh()
	ui._cargo_action("unload_cargo")
	check(ui._pending.is_empty() and ui._feedback.text.contains("Unavailable selected"), "removed carrier blocks a new unload without choosing another")
	missing = frame()["production"].duplicate(true)
	missing.erase("store")
	(world as ObservedWorld).override_view = missing
	(world as ObservedWorld).override_enabled = true
	ui.refresh()
	check(ui._unload_details.text.contains("stock and canister contents unavailable") and ui._unload_button.disabled, "missing field cannot become zero stock or empty cargo")
	check(ui._cargo_material.get_item_text(ui._cargo_material.selected) == "ore.iron" and ui._cargo_material.is_item_disabled(ui._cargo_material.selected), "unavailable material selection retained")
	(world as ObservedWorld).override_enabled = false
	ui.refresh()
	check(not ui._cargo_material.is_item_disabled(ui._cargo_material.selected), "returning observation restores exact selected material")
	await process_frame
	await process_frame
	ui._unload_details.grab_focus()
	await process_frame
	await process_frame
	check(ui._unload_details.has_focus() and ui._section_scroll.follow_focus and ui._section_scroll.scroll_vertical > 0, "keyboard focus reveals actual lower guidance")
	var down := InputEventAction.new()
	down.action = &"ui_page_down"
	down.pressed = true
	ui._section_scroll.scroll_vertical = 0
	ui._unload_guidance_input(down)
	check(ui._section_scroll.scroll_vertical > 0, "focused page down scrolls")
	ui._amount.value = 100
	ui._cargo_action("unload_cargo")
	var pending_id: String = ui._pending
	ui._on_closed()
	var closed_text: String = ui._feedback.text
	var late := ProductionDevelopmentCommand.new()
	late.command_id = StringName(pending_id)
	late.operation = "unload_cargo"
	ui._on_completed(late, ServiceResult.success())
	check(ui._feedback.text == closed_text and closed_text.contains("outcome is unknown") and closed_text.contains("100000 mg") and ui._cargo_pending.is_empty(), "disconnect and late receipt retain exact uncertainty without retry")
	for _frame in range(4): await process_frame
	outer.free()
	world.free()
	if failures == 0: print("PASS exact unloading guidance, real conservation/rejection, pending fencing, missing fields, receipt/disconnect and focus/scroll")
	quit(0 if failures == 0 else 1)