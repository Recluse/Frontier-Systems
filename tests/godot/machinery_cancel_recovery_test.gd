extends "res://tests/godot/machinery_resume_recovery_test.gd"

## Reuse PR96 transport helpers and its original paid machinery fixture.
func finish() -> void:
	create_timer(60.0).timeout.connect(func() -> void: push_error("Machinery recovery deadline"); quit(1))
	var machine: String = ""
	for module in production.capture_snapshot().value["machinery"]["mounts"]:
		if production.capture_snapshot().value["machinery"]["parts"][module]["kind"] == "extractor":
			machine = production.capture_snapshot().value["machinery"]["mounts"][module]
	check(not machine.is_empty(), "paid base fixture supplies finite canister extractor")
	directory = "user://machinery-cancel-recovery-%d" % Time.get_ticks_usec()
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
	# Deliberately disconnect before the host polls this pending Cancel.
	panel._send("machine_cancel")
	var abandoned: String = panel._pending
	check(not abandoned.is_empty(), "actual pending Cancel precedes transport loss")
	host.free()
	check(await wait_for(func() -> bool: return client._latest.is_empty()), "same running client clears disconnected observation")
	check(acks.has(abandoned) and not acks[abandoned].is_success and client._remote._requests.is_empty(), "uncertain Cancel abandoned without success or retry")
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
	check(host.received.is_empty() and client._remote._requests.is_empty(), "manual reconnect sends no abandoned Cancel or automatic batch replay")
	var paused: Dictionary = job.duplicate(true)
	paused["paused"] = true
	check(JSON.parse_string(JSON.stringify(production.capture_snapshot().value["machinery"]["jobs"][machine])) == JSON.parse_string(JSON.stringify(paused)), "restore retains exact recipe progress and spent energy, changing only pause")
	step(180)
	var idle: Dictionary = production.capture_snapshot().value
	check(idle["machinery"]["jobs"][machine] == paused, "180 ticks cannot resume or complete restored paid job")
	for field in ["cargo", "deposits", "store", "structures", "loose_parts"]:
		check(JSON.parse_string(JSON.stringify(idle[field])) == saved["systems"]["production"][field], "paused ticks conserve " + field)
	check(JSON.parse_string(JSON.stringify(inventory.capture_snapshot().value["owner"])) == saved["systems"]["inventory"]["owner"], "paused ticks preserve every inventory provenance and revision record")
	await cancel_rejection_probes(disk.value["snapshot_json"], machine)
	check(await wait_for(func() -> bool: return int(client._latest["production"]["last_tick"]) == runner.tick_number), "fresh post-pause observation")
	panel = client._machinery_panel
	panel.select_machine(machine)
	select_id(panel._recipe, "refine.iron")
	panel._choose_group(1)
	var revision: int = int(client._latest["production"]["state_revision"])
	var before: Dictionary = production.capture_snapshot().value
	check(before["machinery"]["jobs"][machine]["recipe"] == job["recipe"], "unrelated dropdown preserves canonical saved recipe before cancellation")
	# A genuinely restored paused world performs the same charging tick without Cancel.
	var energy_probe := WorldRuntime.new()
	energy_probe.resource_carriers_enabled = true
	root.add_child(energy_probe)
	check(energy_probe.restore_world_snapshot_json(world.capture_world_snapshot_json().value).is_success and energy_probe.start_simulation().is_success, "genuine paused energy baseline")
	var energy_runner: SimulationRunner = energy_probe.get_node("SimulationRunner")
	energy_runner.set_physics_process(false)
	energy_runner._physics_process(1.0 / 60.0)
	var energy_system: ProductionSimulationSystem = energy_probe.get_simulation_system(ProductionSimulationSystem.SYSTEM_ID)
	var expected_energy: Dictionary = energy_system.capture_snapshot().value["machinery"]["placements"].duplicate(true)
	energy_probe.free()
	var cancel_button: Button
	for button in panel._action_buttons:
		if button.text == "Cancel batch (inputs stay in canisters)": cancel_button = button
	check(cancel_button != null and not cancel_button.disabled, "same reconnected client exposes explicit Cancel control")
	cancel_button.pressed.emit()
	var cancel_id: String = panel._pending
	var exact: ProductionDevelopmentCommand = client._remote._requests.get(cancel_id)
	check(exact != null and exact.operation == "machine_cancel" and ControlContractValidation.has_exact_fields(exact.payload, PackedStringArray(["machine_id", "expected_revision"])) and exact.payload["machine_id"] == machine and int(exact.payload["expected_revision"]) == revision, "Cancel freezes machine/revision/request with no recipe replacement")
	var identity: String = panel._request_identity.text
	check(not client._remote.enqueue_command(exact).is_success and client._remote._requests.size() == 1, "same pending request rejects locally without duplicate send")
	panel._choose_group(0)
	panel._choose_group(1)
	check(panel._pending == cancel_id and panel._request_identity.text == identity and panel._machine.disabled and panel._recipe.disabled, "pending navigation retains exact Cancel identity and freezes selectors")
	check(production.capture_snapshot().value == before, "Cancel presentation does not mutate paused paid job")
	check(await wait_for(func() -> bool: return not host._pending.is_empty()), "host queues explicit Cancel")
	check(host.received.size() == 1 and host.received[0]["request_id"] == cancel_id and host.received[0]["payload"] == exact.payload, "one authenticated exact Cancel frame after manual reconnect")
	step()
	check(await wait_for(func() -> bool: return acks.has(cancel_id)) and acks[cancel_id].is_success and panel._pending.is_empty(), "matching host receipt settles accepted Cancel")
	check(panel._request_identity.text == identity and panel._feedback.text.contains("Completed"), "settled receipt retains exact submitted identity and acceptance feedback")
	var cancelled: Dictionary = production.capture_snapshot().value
	check(not cancelled["machinery"]["jobs"].has(machine) and int(cancelled["state_revision"]) == revision + 1, "accepted Cancel removes only existing job and advances command revision once")
	check(cancelled["machinery"]["placements"] == expected_energy, "Cancel refunds no spent energy and charges exactly like genuine paused baseline")
	check(cancelled["receipts"].size() == before["receipts"].size() + 1 and cancelled["receipts"][-1]["request_id"] == "net-1-" + cancel_id and int(cancelled["receipts"][-1]["revision"]) == revision + 1, "one host-slot-bound production receipt records accepted Cancel")
	conserved(before, cancelled, "accepted Cancel")
	var own_before: Dictionary = inventory.capture_snapshot().value["owner"].duplicate(true)
	check(JSON.parse_string(JSON.stringify(own_before)) == saved["systems"]["inventory"]["owner"], "Cancel preserves complete physical provenance and inventory revisions")
	check(ProductionSimulationSystem._reserved_mass(cancelled) == ProductionSimulationSystem._reserved_mass(before) and cancelled["job"] == before["job"], "machine Cancel neither releases nor creates workstation reservations")
	check(production.validate_snapshot_record(cancelled, runner.tick_number).is_success and world.capture_world_snapshot_json().is_success, "cancelled whole-world matter/provenance contract validates")
	acks.erase(cancel_id)
	check(client._remote.enqueue_command(exact).is_success, "deliberate settled exact-request repeat uses original frozen revision")
	check(await wait_for(func() -> bool: return not host._pending.is_empty()), "host queues deliberate exact-request repeat")
	check(host.received.size() == 2 and host.received[1] == host.received[0], "repeated request preserves exact original wire intent")
	step()
	check(await wait_for(func() -> bool: return acks.has(cancel_id)) and acks[cancel_id].is_success, "settled identical request returns retained success without reapplying Cancel")
	check(production.capture_snapshot().value["state_revision"] == revision + 1, "repeated request cannot advance cancellation revision twice")
	check(production.capture_snapshot().value["receipts"] == cancelled["receipts"], "retained success creates no duplicate production receipt")
	acks.erase(cancel_id)
	var changed := ProductionDevelopmentCommand.new()
	changed.command_id = exact.command_id
	changed.operation = "machine_resume"
	changed.payload = exact.payload.duplicate(true)
	check(client._remote.enqueue_command(changed).is_success, "send deliberately changed intent under settled request ID")
	check(await wait_for(func() -> bool: return not host._pending.is_empty()), "host queues retained-ID conflict")
	step()
	check(await wait_for(func() -> bool: return acks.has(cancel_id)) and not acks[cancel_id].is_success and acks[cancel_id].message.contains("different intent"), "same retained ID with changed intent rejects")
	check(production.capture_snapshot().value["receipts"] == cancelled["receipts"] and production.capture_snapshot().value["state_revision"] == revision + 1, "conflicting retained ID leaves receipt and command revision unchanged")
	step(180)
	conserved(cancelled, production.capture_snapshot().value, "later ticks cannot replay cancelled output")
	check(not production.capture_snapshot().value["machinery"]["jobs"].has(machine) and inventory.capture_snapshot().value["owner"] == own_before, "later ticks preserve no-job state and exact inventory")
	check(await wait_for(func() -> bool: return int(client._latest["production"]["last_tick"]) == runner.tick_number), "observe current no-job state")
	check(not (await panel_action("machine_cancel")).is_success, "fresh repeated Cancel rejects absent job")
	check(not (await panel_action("machine_resume")).is_success, "Resume cannot replay cancelled batch")
	conserved(cancelled, production.capture_snapshot().value, "repeated Cancel and Resume")
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
	print("Machinery durable explicit Cancel: %d failures; synthetic controls, in-process replacement, no human/crash/tutorial acceptance" % failures)
	quit(1 if failures else 0)


func conserved(before: Dictionary, after: Dictionary, label: String) -> void:
	for field in ["cargo", "deposits", "store", "structures", "loose_parts", "vessel", "job", "wall_mass_milligrams", "walls"]:
		check(after[field] == before[field], label + " conserves " + field)
	for field in ["parts", "mounts", "links"]:
		check(after["machinery"][field] == before["machinery"][field], label + " preserves machinery " + field)


func cancel_rejection_probes(snapshot: String, machine: String) -> void:
	var live_world: WorldRuntime = world
	var live_runner: SimulationRunner = runner
	var live_production: ProductionSimulationSystem = production
	var live_inventory: InventorySimulationSystem = inventory
	world = WorldRuntime.new()
	world.resource_carriers_enabled = true
	root.add_child(world)
	check(world.restore_world_snapshot_json(snapshot).is_success and world.start_simulation().is_success, "Cancel probes restore genuine partially paid snapshot")
	runner = world.get_node("SimulationRunner")
	runner.set_physics_process(false)
	production = world.get_simulation_system(ProductionSimulationSystem.SYSTEM_ID)
	inventory = world.get_simulation_system(InventorySimulationSystem.SYSTEM_ID)
	world.command_completed.connect(func(_action: SimulationCommand, result: ServiceResult) -> void: last = result)
	for invalid in ["stale", "recipe", "missing"]:
		var before: Dictionary = production.capture_snapshot().value
		var physical: Dictionary = inventory.capture_snapshot().value["owner"]
		var action := ProductionDevelopmentCommand.new()
		sequence += 1
		action.command_id = StringName("invalid-cancel-%d" % sequence)
		action.authenticated_context = context
		action.operation = "machine_cancel"
		action.payload = {"machine_id": machine, "expected_revision": int(before["state_revision"])}
		if invalid == "stale": action.payload["expected_revision"] -= 1
		if invalid == "recipe": action.payload["recipe"] = "refine.iron"
		if invalid == "missing": action.payload["machine_id"] = "missing-machine"
		check(world.enqueue_command(action).is_success, "queue bounded " + invalid + " Cancel")
		step()
		check(not last.is_success and production.capture_snapshot().value["machinery"]["jobs"] == before["machinery"]["jobs"] and production.capture_snapshot().value["state_revision"] == before["state_revision"], invalid + " Cancel rejects without job or command revision mutation")
		conserved(before, production.capture_snapshot().value, invalid + " Cancel")
		check(inventory.capture_snapshot().value["owner"] == physical, invalid + " Cancel preserves provenance")
	# Deployed machinery is shared within authenticated reach. Confirm the other
	# existing body reaches this frame through commands, never minted authority.
	var own_context: AuthenticatedCommandContext = context
	context = AuthenticatedCommandContext.for_local_development(&"local-inventory-target", world.world_id, world.region_id)
	move(production.capture_snapshot().value["machinery"]["placements"][machine]["position"])
	command("machine_cancel", {"machine_id": machine})
	check(not production.capture_snapshot().value["machinery"]["jobs"].has(machine), "reachable deployed frame permits other authenticated operator Cancel")
	command("machine_cancel", {"machine_id": machine}, false)
	context = own_context
	for cable in production.capture_snapshot().value["machinery"]["links"].keys():
		if machine in production.capture_snapshot().value["machinery"]["links"][cable].values(): command("machine_unwire", {"machine_id": machine, "item_id": cable})
	command("machine_pack", {"machine_id": machine})
	context = AuthenticatedCommandContext.for_local_development(&"local-inventory-target", world.world_id, world.region_id)
	command("machine_cancel", {"machine_id": machine}, false)
	check(last.message.contains("not owned or deployed"), "other principal cannot Cancel foreign owned packed frame")
	context = own_context
	world.free()
	world = live_world
	runner = live_runner
	production = live_production
	inventory = live_inventory
