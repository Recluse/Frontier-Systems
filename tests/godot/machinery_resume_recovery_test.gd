extends "res://tests/godot/machinery_runtime_test.gd"

## Reuse the paid, conserved machinery fixture without changing its authority.
class RecordingHost extends FirstPlayableHost:
	var received: Array[Dictionary] = []
	func _receive(id: int, value: Dictionary) -> void:
		if value.get("type") == "command": received.append(value.duplicate(true))
		super._receive(id, value)

var host: RecordingHost
var store: WorldPersistenceAdapter
var client: FirstPlayableBootstrap
var acks: Dictionary = {}
var directory: String
var keys: Array[String] = ["machinery-recovery-one-000000000000000", "machinery-recovery-two-000000000000000"]


func wait_for(predicate: Callable) -> bool:
	var deadline: int = Time.get_ticks_msec() + 5000
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		if is_instance_valid(store): store._process(0.0)
		await process_frame
	return predicate.call()


func attach_host() -> void:
	host = RecordingHost.new()
	host.persistence = store
	root.add_child(host)
	check(host.configure(world, keys, 27849).is_success, "open exclusively leased loopback endpoint")


func select_id(picker: OptionButton, id: String) -> void:
	for index in range(picker.item_count):
		if picker.get_item_metadata(index) == id:
			picker.select(index)
			return
	check(false, "observed selector contains " + id)


func panel_action(operation: String) -> ServiceResult:
	var panel: MachineryPanel = client._machinery_panel
	panel._send(operation)
	var id: String = panel._pending
	check(not id.is_empty(), "actual client panel queues " + operation)
	check(await wait_for(func() -> bool: return not host._pending.is_empty()), "host receives authenticated " + operation)
	step()
	check(await wait_for(func() -> bool: return acks.has(id)), "matching network receipt " + operation)
	return acks.get(id, ServiceResult.failure(&"missing_receipt", "No receipt"))


func finish() -> void:
	create_timer(60.0).timeout.connect(func() -> void: push_error("Machinery recovery deadline"); quit(1))
	var machine: String = ""
	for module in production.capture_snapshot().value["machinery"]["mounts"]:
		if production.capture_snapshot().value["machinery"]["parts"][module]["kind"] == "extractor":
			machine = production.capture_snapshot().value["machinery"]["mounts"][module]
	check(not machine.is_empty(), "paid base fixture supplies finite canister extractor")
	directory = "user://machinery-recovery-%d" % Time.get_ticks_usec()
	store = WorldPersistenceAdapter.new()
	root.add_child(store)
	store.set_process(false)
	check(store.configure(world, directory).is_success, "native temporary durable adapter")
	var old_url: String = OS.get_environment("FRONTIER_HOST_URL")
	var old_key: String = OS.get_environment("FRONTIER_INVITE_KEY")
	OS.set_environment("FRONTIER_HOST_URL", "ws://127.0.0.1:27849")
	OS.set_environment("FRONTIER_INVITE_KEY", keys[0])
	attach_host()
	client = FirstPlayableBootstrap.new()
	root.add_child(client)
	client._remote.terrain_retry_directory = directory.path_join("client-intents")
	client._remote.command_completed.connect(func(action: SimulationCommand, result: ServiceResult) -> void: acks[String(action.command_id)] = result)
	check(await wait_for(func() -> bool: return not client._latest.is_empty()), "actual client authenticates and receives scoped production")
	client.set_process(false)
	client._habitat.character.read_local_keyboard = false
	client._habitat.character.set_physics_process(false)
	var panel: MachineryPanel = client._machinery_panel
	panel.select_machine(machine)
	select_id(panel._recipe, "extract.ice")
	check((await panel_action("machine_run")).is_success, "client starts paid finite batch")
	step(30)
	var paid: Dictionary = production.capture_snapshot().value
	var job: Dictionary = paid["machinery"]["jobs"][machine].duplicate(true)
	check(job["progress"] > 0 and job["energy_spent"] > 0 and not job["paused"], "checkpoint source contains partly paid batch")
	check(await wait_for(func() -> bool: return int(client._latest["production"]["last_tick"]) == runner.tick_number), "observe exact source tick")
	client._host_actions[-1].pressed.emit()
	var save_id: String = String(client._checkpoint_request.command_id)
	check(await wait_for(func() -> bool: return acks.has(save_id)) and acks[save_id].is_success, "actual save control acknowledged after worker disk completion")
	var disk: ServiceResult = LocalWorldSaveStore.read_latest(directory)
	check(disk.is_success, "checksum-validated committed checkpoint readback")
	var saved: Dictionary = JSON.parse_string(disk.value["snapshot_json"])
	check(saved["systems"]["production"] == JSON.parse_string(JSON.stringify(paid)), "disk retains all paid production records at exact captured tick")
	# Deliberately disconnect before the host polls this pending Resume.
	panel._send("machine_resume")
	var abandoned: String = panel._pending
	check(not abandoned.is_empty(), "actual pending Resume precedes transport loss")
	host.free()
	check(await wait_for(func() -> bool: return client._latest.is_empty()), "same running client clears disconnected observation")
	check(acks.has(abandoned) and not acks[abandoned].is_success and client._remote._requests.is_empty(), "uncertain Resume abandoned without success or retry")
	store.free()
	world.free()
	world = WorldRuntime.new()
	world.resource_carriers_enabled = true
	root.add_child(world)
	store = WorldPersistenceAdapter.new()
	root.add_child(store)
	store.set_process(false)
	check(store.configure(world, directory).is_success, "replacement loads native durable checkpoint")
	check(world.start_simulation().is_success, "replacement starts at saved tick")
	runner = world.get_node("SimulationRunner")
	runner.set_physics_process(false)
	production = world.get_simulation_system(ProductionSimulationSystem.SYSTEM_ID)
	inventory = world.get_simulation_system(InventorySimulationSystem.SYSTEM_ID)
	world.command_completed.connect(func(_action: SimulationCommand, result: ServiceResult) -> void: last = result)
	attach_host()
	await process_frame
	check(client._latest.is_empty() and host.received.is_empty(), "replacement does not auto-reconnect client")
	client._reconnect.pressed.emit()
	check(await wait_for(func() -> bool: return not client._latest.is_empty()), "same client manual button reauthenticates persistent invite")
	check(host.received.is_empty() and client._remote._requests.is_empty(), "manual reconnect sends no abandoned Resume or automatic batch replay")
	var paused: Dictionary = job.duplicate(true)
	paused["paused"] = true
	check(JSON.parse_string(JSON.stringify(production.capture_snapshot().value["machinery"]["jobs"][machine])) == JSON.parse_string(JSON.stringify(paused)), "restore retains exact recipe progress and spent energy, changing only pause")
	step(180)
	var idle: Dictionary = production.capture_snapshot().value
	check(idle["machinery"]["jobs"][machine] == paused, "180 ticks cannot resume or complete restored paid job")
	for field in ["cargo", "deposits", "store", "structures", "loose_parts"]:
		check(JSON.parse_string(JSON.stringify(idle[field])) == saved["systems"]["production"][field], "paused ticks conserve " + field)
	check(JSON.parse_string(JSON.stringify(inventory.capture_snapshot().value["owner"])) == saved["systems"]["inventory"]["owner"], "paused ticks preserve every inventory provenance and revision record")
	for fault in ["canister", "module", "isolation"]:
		await prerequisite_probes(disk.value["snapshot_json"], machine, fault)
	check(await wait_for(func() -> bool: return int(client._latest["production"]["last_tick"]) == runner.tick_number), "fresh post-pause observation")
	panel = client._machinery_panel
	panel.select_machine(machine)
	# Resume never replaces the canonical saved recipe with this dropdown value.
	select_id(panel._recipe, "refine.iron")
	panel._choose_group(1)
	var revision: int = int(client._latest["production"]["state_revision"])
	var before: Dictionary = production.capture_snapshot().value
	var resume_button: Button
	for button in panel._action_buttons:
		if button.text == "Resume batch after restart": resume_button = button
	check(resume_button != null and not resume_button.disabled, "actual resumed client exposes explicit Resume control")
	resume_button.pressed.emit()
	var resume_id: String = panel._pending
	var exact: ProductionDevelopmentCommand = client._remote._requests.get(resume_id)
	check(exact != null and exact.operation == "machine_resume" and ControlContractValidation.has_exact_fields(exact.payload, PackedStringArray(["machine_id", "expected_revision"])) and exact.payload["machine_id"] == machine and int(exact.payload["expected_revision"]) == revision, "Resume freezes exact machine/revision request and sends no replacement recipe")
	var identity: String = panel._request_identity.text
	panel._choose_group(0)
	panel._choose_group(1)
	check(panel._pending == resume_id and panel._request_identity.text == identity and panel._machine.disabled and panel._recipe.disabled, "pending navigation retains request identity and freezes selectors")
	check(production.capture_snapshot().value == before, "presentation cannot mutate paid paused job before host tick")
	check(await wait_for(func() -> bool: return not host._pending.is_empty()), "host queues explicit Resume")
	check(host.received.size() == 1 and host.received[0]["request_id"] == resume_id and host.received[0]["payload"] == exact.payload, "one exact authenticated Resume frame after reconnect")
	step()
	check(await wait_for(func() -> bool: return acks.has(resume_id)) and acks[resume_id].is_success and panel._pending.is_empty(), "matching host acceptance settles Resume")
	check(production.capture_snapshot().value["machinery"]["jobs"][machine]["recipe"] == job["recipe"], "saved recipe survives unrelated selected dropdown")
	var spec: Dictionary = production.machine_recipe(job["recipe"])
	step(int(spec["duration_ticks"]) - int(job["progress"]) - 2)
	var final_tick: Dictionary = production.capture_snapshot().value
	# A genuine paused replacement supplies the identical grid-charge baseline.
	var energy_probe := WorldRuntime.new()
	energy_probe.resource_carriers_enabled = true
	root.add_child(energy_probe)
	check(energy_probe.restore_world_snapshot_json(world.capture_world_snapshot_json().value).is_success and energy_probe.start_simulation().is_success, "genuine final-tick paused clone for grid energy baseline")
	var energy_runner: SimulationRunner = energy_probe.get_node("SimulationRunner")
	energy_runner.set_physics_process(false)
	energy_runner._physics_process(1.0 / 60.0)
	var energy_system: ProductionSimulationSystem = energy_probe.get_simulation_system(ProductionSimulationSystem.SYSTEM_ID)
	var charged_energy: int = int(energy_system.capture_snapshot().value["machinery"]["placements"][machine]["energy"])
	energy_probe.free()
	check(final_tick["machinery"]["jobs"][machine]["progress"] == int(spec["duration_ticks"]) - 1 and final_tick["machinery"]["jobs"][machine]["energy_spent"] == (int(spec["duration_ticks"]) - 1) * int(spec["energy_joules"]) / int(spec["duration_ticks"]), "resumed energy accumulates only remaining work to final tick")
	step()
	var completed: Dictionary = production.capture_snapshot().value
	var remaining_energy: int = int(spec["energy_joules"]) - int(final_tick["machinery"]["jobs"][machine]["energy_spent"])
	check(int(completed["machinery"]["placements"][machine]["energy"]) == charged_energy - remaining_energy, "final tick debits only remaining paid recipe energy after identical grid charging")
	check(not completed["machinery"]["jobs"].has(machine), "remaining paid work completes exactly once after explicit Resume")
	check(int(completed["cargo"]["resource-canister-1"]["ice"]) == int(paid["cargo"]["resource-canister-1"]["ice"]) + 1000000 and int(completed["deposits"]["deposit.ice"]) == int(paid["deposits"]["deposit.ice"]) - 1000000, "one million mg source transfers once into fitted canister")
	check(production.validate_snapshot_record(completed, runner.tick_number).is_success and world.capture_world_snapshot_json().is_success, "complete finite world mass/provenance/energy contract validates")
	var once: Dictionary = completed["cargo"].duplicate(true)
	step(180)
	check(production.capture_snapshot().value["cargo"] == once, "later ticks cannot replay output")
	check((await panel_action("machine_resume")).is_success == false, "completed batch Resume rejects without new output")
	await process_frame
	await process_frame
	await process_frame
	client.free()
	host.free()
	store.free()
	world.free()
	PlayerInputSettings.instance().release_all()
	OS.set_environment("FRONTIER_HOST_URL", old_url)
	OS.set_environment("FRONTIER_INVITE_KEY", old_key)
	await process_frame
	for name in DirAccess.get_files_at(directory): check(DirAccess.remove_absolute(directory.path_join(name)) == OK, "remove disposable checkpoint")
	check(DirAccess.remove_absolute(directory) == OK, "remove disposable world directory")
	print("Machinery durable explicit Resume acceptance: %d failures; synthetic controls, in-process replacement, no human/crash acceptance" % failures)
	quit(1 if failures else 0)


func prerequisite_probes(snapshot: String, machine: String, fault: String) -> void:
	# Isolated genuine snapshot, production commands only; no canonical edits.
	var live_world: WorldRuntime = world
	var live_runner: SimulationRunner = runner
	var live_production: ProductionSimulationSystem = production
	var live_inventory: InventorySimulationSystem = inventory
	world = WorldRuntime.new()
	world.resource_carriers_enabled = true
	root.add_child(world)
	check(world.restore_world_snapshot_json(snapshot).is_success and world.start_simulation().is_success, "prerequisite probe restores genuine paid world")
	runner = world.get_node("SimulationRunner")
	runner.set_physics_process(false)
	production = world.get_simulation_system(ProductionSimulationSystem.SYSTEM_ID)
	inventory = world.get_simulation_system(InventorySimulationSystem.SYSTEM_ID)
	world.command_completed.connect(func(_action: SimulationCommand, result: ServiceResult) -> void: last = result)
	var socket: String = ""
	for physical in inventory.capture_snapshot().value["owner"]["ledger"]["items"]:
		if physical["item_id"] == "resource-canister-1":
			for module in production.capture_snapshot().value["machinery"]["mounts"]:
				if physical["container_id"] == InventorySimulationSystem.factory_storage_id(module): socket = module
	match fault:
		"canister": command("machine_remove", {"machine_id": machine, "item_id": "resource-canister-1", "socket_id": socket})
		"isolation": command("machine_enable", {"machine_id": machine, "enabled": false})
		"module":
			for module in production.capture_snapshot().value["machinery"]["mounts"]:
				if production.capture_snapshot().value["machinery"]["mounts"][module] == machine and production.capture_snapshot().value["machinery"]["parts"][module]["kind"] == "extractor":
					command("machine_unfit", {"machine_id": machine, "item_id": module, "socket_id": ""})
					break
	var before: Dictionary = production.capture_snapshot().value
	var stale := ProductionDevelopmentCommand.new()
	sequence += 1
	stale.command_id = StringName("stale-resume-%d" % sequence)
	stale.authenticated_context = context
	stale.operation = "machine_resume"
	stale.payload = {"machine_id": machine, "expected_revision": int(before["state_revision"]) - 1}
	check(world.enqueue_command(stale).is_success, "enqueue stale revision Resume without refreshing its frozen intent")
	step()
	check(not last.is_success and production.capture_snapshot().value["machinery"]["jobs"][machine] == before["machinery"]["jobs"][machine], "stale revision rejects without unpausing saved job")
	command("machine_run", {"machine_id": machine, "recipe": "refine.iron"}, false)
	command("machine_resume", {"machine_id": machine})
	check(not production.capture_snapshot().value["machinery"]["jobs"][machine]["paused"], fault + " prerequisite does not reject current Resume acceptance")
	step(180)
	var stalled: Dictionary = production.capture_snapshot().value
	check(stalled["machinery"]["jobs"][machine]["progress"] == before["machinery"]["jobs"][machine]["progress"] and stalled["machinery"]["jobs"][machine]["energy_spent"] == before["machinery"]["jobs"][machine]["energy_spent"], fault + " prerequisite stalls progress and spends no job energy")
	check(stalled["cargo"] == before["cargo"] and stalled["deposits"] == before["deposits"], "accepted but stalled Resume transfers no input/output matter")
	command("machine_cancel", {"machine_id": machine})
	for cable in production.capture_snapshot().value["machinery"]["links"].keys():
		if machine in production.capture_snapshot().value["machinery"]["links"][cable].values(): command("machine_unwire", {"machine_id": machine, "item_id": cable})
	command("machine_pack", {"machine_id": machine})
	var own_context: AuthenticatedCommandContext = context
	context = AuthenticatedCommandContext.for_local_development(&"local-inventory-target", world.world_id, world.region_id)
	command("machine_resume", {"machine_id": machine}, false)
	check(last.message.contains("not owned or deployed"), "foreign owned packed frame rejected at physical authority boundary")
	context = own_context
	world.free()
	world = live_world
	runner = live_runner
	production = live_production
	inventory = live_inventory
