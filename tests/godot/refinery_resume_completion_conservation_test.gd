extends "res://tests/godot/refinery_cancel_conservation_test.gd"

var completions: int = 0


func finish() -> void:
	create_timer(60.0).timeout.connect(func() -> void: push_error("Machinery recovery deadline"); quit(1))
	prepare_refinery()
	var machine: String = refinery
	directory = "user://refinery-resume-completion-%d" % Time.get_ticks_usec()
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
	select_id(panel._recipe, "refine.ice")
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
	production.batch_completed.connect(func(recipe: String, _tick: int) -> void: if recipe == "refine.ice": completions += 1)
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
	var resume_energy: Dictionary = charged_placements(1)
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
	var resumed: Dictionary = production.capture_snapshot().value
	var resumed_job: Dictionary = resumed["machinery"]["jobs"][machine]
	check(int(resumed_job["progress"]) == int(job["progress"]) + 1 and int(resumed_job["energy_spent"]) == int(resumed_job["progress"]) * 500 / 60, "Resume adds one work tick to saved progress and energy")
	resume_energy[machine]["energy"] -= int(resumed_job["energy_spent"]) - int(job["energy_spent"])
	check(resumed["machinery"]["placements"] == resume_energy and resumed["cargo"] == paid["cargo"], "Resume refunds no energy and preserves all canister inputs until atomic completion")
	check(int(resumed["state_revision"]) == revision + 1, "Resume advances revision once")
	check(resumed["receipts"].size() == mini(ProductionSimulationSystem.MAX_RECEIPTS, before["receipts"].size() + 1) and resumed["receipts"][-1]["request_id"] == "net-0-%s" % resume_id and int(resumed["receipts"][-1]["state_revision"]) == revision + 1, "one authenticated-slot-bound Resume receipt")
	check(JSON.parse_string(JSON.stringify(inventory.capture_snapshot().value["owner"])) == saved["systems"]["inventory"]["owner"], "Resume preserves entire inventory provenance and revisions")
	var spec: Dictionary = production.machine_recipe(job["recipe"])
	check(JSON.parse_string(JSON.stringify(spec["inputs"])) == JSON.parse_string(JSON.stringify({"ice": 1000000})) and JSON.parse_string(JSON.stringify(spec["outputs"])) == JSON.parse_string(JSON.stringify({"water": 1000000})) and int(spec["duration_ticks"]) == 60 and int(spec["energy_joules"]) == 500, "catalog supplies exact finite refinery work/energy/matter bill")
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
	var expected_cargo: Dictionary = paid["cargo"].duplicate(true)
	expected_cargo["resource-canister-1"]["ice"] -= 1000000
	# Sorted carrier allocation reuses the now-empty input canister first.
	expected_cargo["resource-canister-1"]["water"] += 1000000
	check(final_tick["cargo"] == paid["cargo"], "all inputs remain unconsumed and all outputs absent through penultimate work tick")
	check(completed["cargo"] == expected_cargo and ProductionSimulationSystem._mass(completed["cargo"]["resource-canister-1"]) == 1000000 and ProductionSimulationSystem._mass(completed["cargo"]["resource-canister-2"]) == 0, "atomic final tick converts exact full canister records: one kg ice to one kg water")
	check(int(completed["state_revision"]) == revision + 2 and completed["receipts"] == resumed["receipts"] and completions == 1, "one completion revision/event without duplicate command receipt")
	check(JSON.parse_string(JSON.stringify(inventory.capture_snapshot().value["owner"])) == saved["systems"]["inventory"]["owner"], "atomic equal-mass conversion preserves entire physical inventory graph, provenance and revisions")
	check_unchanged_matter(paid, completed, "completion")
	check(production.validate_snapshot_record(completed, runner.tick_number).is_success and world.capture_world_snapshot_json().is_success, "complete finite world mass/provenance/energy contract validates")
	var own_before: Dictionary = inventory.capture_snapshot().value["owner"].duplicate(true)
	var expected_idle: Dictionary = charged_placements(180)
	step(180)
	check_settled(completed, own_before, expected_idle, "idle completed ticks")
	await repeat_intent(exact, completed, own_before, true)
	acks.erase(resume_id)
	var changed := ProductionDevelopmentCommand.new()
	changed.command_id = exact.command_id
	changed.operation = "machine_cancel"
	changed.payload = exact.payload.duplicate(true)
	var conflict_energy: Dictionary = charged_placements(1)
	check(client._remote.enqueue_command(changed).is_success, "send changed operation under retained Resume ID")
	check(await wait_for(func() -> bool: return not host._pending.is_empty()), "host queues retained-ID conflict")
	step()
	check(await wait_for(func() -> bool: return acks.has(resume_id)) and not acks[resume_id].is_success and acks[resume_id].message.contains("different intent"), "retained Resume ID rejects changed intent")
	check_settled(completed, own_before, conflict_energy, "retained-ID conflict")
	check(await wait_for(func() -> bool: return int(client._latest["production"]["last_tick"]) == runner.tick_number), "observe current completed revision")
	var rejected_energy: Dictionary = charged_placements(1)
	check(not (await panel_action("machine_resume")).is_success, "fresh Resume rejects completed absent job")
	check_settled(completed, own_before, rejected_energy, "fresh absent-job Resume")
	check(await wait_for(func() -> bool: return int(client._latest["production"]["last_tick"]) == runner.tick_number), "observe completed checkpoint tick")
	client._host_actions[-1].pressed.emit()
	var completed_save: String = String(client._checkpoint_request.command_id)
	check(await wait_for(func() -> bool: return acks.has(completed_save)) and acks[completed_save].is_success, "worker commits completed native checkpoint")
	var completed_disk: ServiceResult = LocalWorldSaveStore.read_latest(directory)
	check(completed_disk.is_success, "checksum-valid completed checkpoint")
	var completed_saved: Dictionary = JSON.parse_string(completed_disk.value["snapshot_json"])
	check(completed_saved["systems"]["production"] == JSON.parse_string(JSON.stringify(production.capture_snapshot().value)), "native completed checkpoint retains full production state")
	host.free()
	check(await wait_for(func() -> bool: return client._latest.is_empty()), "same client observes completed-world disconnect")
	store.free()
	world.free()
	world = WorldRuntime.new()
	world.resource_carriers_enabled = true
	root.add_child(world)
	store = WorldPersistenceAdapter.new()
	root.add_child(store)
	store.set_process(false)
	check(store.configure(world, directory).is_success and world.start_simulation().is_success, "replacement restores native completed checkpoint")
	runner = world.get_node("SimulationRunner")
	runner.set_physics_process(false)
	production = world.get_simulation_system(ProductionSimulationSystem.SYSTEM_ID)
	inventory = world.get_simulation_system(InventorySimulationSystem.SYSTEM_ID)
	world.command_completed.connect(func(_action: SimulationCommand, result: ServiceResult) -> void: last = result)
	production.batch_completed.connect(func(recipe: String, _tick: int) -> void: if recipe == "refine.ice": completions += 1)
	check(JSON.parse_string(JSON.stringify(production.capture_snapshot().value)) == completed_saved["systems"]["production"], "completed restore retains all production energy, receipt and revision records")
	attach_host()
	await process_frame
	check(client._latest.is_empty() and host.received.is_empty(), "completed restore does not auto-reconnect or replay")
	client._reconnect.pressed.emit()
	check(await wait_for(func() -> bool: return not client._latest.is_empty()), "same client manually reconnects completed restore")
	check(host.received.is_empty(), "completed reconnect sends no implicit production intent")
	var restored_energy: Dictionary = charged_placements(180)
	step(180)
	check_settled(completed, own_before, restored_energy, "completed native restore idle ticks")
	await repeat_intent(exact, completed, own_before, false)
	check(await wait_for(func() -> bool: return int(client._latest["production"]["last_tick"]) == runner.tick_number), "observe restored absent job")
	rejected_energy = charged_placements(1)
	check(not (await panel_action("machine_resume")).is_success, "fresh Resume cannot recreate completed restored job")
	check_settled(completed, own_before, rejected_energy, "completed restore fresh Resume")
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
	print("Refinery durable Resume completion conservation: %d failures; synthetic controls, in-process replacement, no human/crash acceptance" % failures)
	quit(1 if failures else 0)




func charged_placements(ticks: int) -> Dictionary:
	# Native validated snapshots only: restore pauses any job, giving a genuine
	# grid-charge baseline with no job energy debit or canonical fixture edits.
	var probe := WorldRuntime.new()
	probe.resource_carriers_enabled = true
	root.add_child(probe)
	check(probe.restore_world_snapshot_json(world.capture_world_snapshot_json().value).is_success and probe.start_simulation().is_success, "restore genuine grid-only energy baseline")
	var probe_runner: SimulationRunner = probe.get_node("SimulationRunner")
	probe_runner.set_physics_process(false)
	for tick in range(ticks): probe_runner._physics_process(1.0 / 60.0)
	var system: ProductionSimulationSystem = probe.get_simulation_system(ProductionSimulationSystem.SYSTEM_ID)
	var placements: Dictionary = system.capture_snapshot().value["machinery"]["placements"].duplicate(true)
	probe.free()
	return placements


func check_unchanged_matter(before: Dictionary, after: Dictionary, label: String) -> void:
	for field in ["deposits", "store", "structures", "loose_parts", "vessel", "job", "wall_mass_milligrams", "walls", "energy_joules", "powered"]:
		check(after[field] == before[field], label + " preserves unrelated " + field)
	for field in ["parts", "mounts", "links"]:
		check(after["machinery"][field] == before["machinery"][field], label + " preserves complete machinery " + field)
	check(ProductionSimulationSystem._reserved_mass(after) == ProductionSimulationSystem._reserved_mass(before), label + " preserves workstation reservations")


func check_settled(completed: Dictionary, physical: Dictionary, expected_energy: Dictionary, label: String) -> void:
	var current: Dictionary = production.capture_snapshot().value
	check(current["cargo"] == completed["cargo"] and current["machinery"]["jobs"] == completed["machinery"]["jobs"] and completions == 1, label + " cannot replay output or completed batch event")
	check(current["state_revision"] == completed["state_revision"] and current["receipts"] == completed["receipts"], label + " preserves exact command/completion revision and receipts")
	check(current["machinery"]["placements"] == expected_energy, label + " has only genuine grid charging without spent-energy refund")
	check(inventory.capture_snapshot().value["owner"] == physical, label + " preserves complete physical provenance/revisions")
	check_unchanged_matter(completed, current, label)
	check(world.capture_world_snapshot_json().is_success, label + " validates whole-world conservation")


func repeat_intent(exact: ProductionDevelopmentCommand, completed: Dictionary, physical: Dictionary, retained_host: bool) -> void:
	var id: String = String(exact.command_id)
	acks.erase(id)
	var expected_energy: Dictionary = charged_placements(1)
	check(client._remote.enqueue_command(exact).is_success, "deliberate settled exact Resume repeat keeps original frozen revision")
	check(await wait_for(func() -> bool: return not host._pending.is_empty()), "host queues identical retained Resume intent")
	check(host.received[-1]["request_id"] == id and host.received[-1]["payload"] == exact.payload, "repeat preserves full original wire identity and payload")
	if retained_host: check(host.received[-1] == host.received[0], "same-host repeat preserves exact authenticated wire frame")
	step()
	check(await wait_for(func() -> bool: return acks.has(id)) and acks[id].is_success, "identical retained Resume returns success after completion/restore")
	check_settled(completed, physical, expected_energy, "retained Resume repeat")
