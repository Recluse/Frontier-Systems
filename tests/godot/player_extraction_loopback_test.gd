extends "res://tests/godot/player_equipment_loopback_test.gd"

## Controls and tick scheduling are synthetic; authentication, inventory, work,
## acknowledgements and observations use the existing production paths.
var production: ProductionSimulationSystem
var runner: SimulationRunner
var initial: Dictionary
var initial_tools: Dictionary
var completed: int = 0

func state() -> Dictionary:
	return production.capture_snapshot().value

func steps(count: int) -> void:
	for index in range(count): runner._physics_process(1.0 / 60.0)

func tick_command(command: SimulationCommand, foreign: bool = false) -> bool:
	if command == null: return false
	var receipts: Dictionary = foreign_results if foreign else results
	var id: String = String(command.command_id)
	if not await wait_for(func() -> bool: return not host._pending.is_empty() or receipts.has(id), "real host admits request " + id): return false
	steps(1)
	return await wait_for(func() -> bool: return receipts.has(id), "exact wire acknowledgement " + id)

func production_button(operation: String) -> SimulationCommand:
	var label: String = {"start_tool_extract": "Start sustained extraction", "resume_tool_extract": "Resume reserved extraction", "cancel_tool_extract": "Cancel and release remaining source reservation"}[operation]
	var payload: Dictionary = {"expected_revision": panel._production["state_revision"]}
	if operation == "start_tool_extract": payload.merge({"deposit_id": panel._deposit.get_item_metadata(panel._deposit.selected), "carrier_id": panel._carrier.get_item_metadata(panel._carrier.selected), "cycles": int(panel._work_cycles.value)})
	var count: int = remote.sent.size()
	for button in panel._buttons:
		if button.text == label:
			check(not button.disabled, "actual extraction control enabled: " + operation)
			button.pressed.emit()
			break
	check(remote.sent.size() == count + 1, "actual button emits one production intent")
	if remote.sent.size() != count + 1: return null
	var command: SimulationCommand = remote.sent[-1]
	check(command is ProductionDevelopmentCommand and command.operation == operation and command.payload == payload and command.authenticated_context == null, "exact source/carrier/cycles/revision without client authority")
	check(panel._pending == String(command.command_id), "shell retains exact pending production request")
	return command

func production_settled(command: SimulationCommand, before: Dictionary) -> bool:
	if not await tick_command(command): return false
	var id: String = String(command.command_id)
	if not await wait_for(func() -> bool: return panel._pending.is_empty() and int(panel._production.get("state_revision", -1)) == int(state()["state_revision"]), "fresh production revision settles shell"): return false
	check(results[id].is_success, "production accepts explicit " + String(command.operation))
	var request: String = "net-1-" + id
	var fingerprint: String = JSON.stringify(["local-inventory-target", String(command.operation), normalized(command.payload)], "", true).sha256_text()
	var retained: Array = state()["receipts"].filter(func(entry: Dictionary) -> bool: return entry["request_id"] == request)
	check(retained.size() == 1, "one canonical production receipt for exact wire request")
	if retained.size() == 1:
		check(retained[0]["fingerprint"] == fingerprint and int(retained[0]["state_revision"]) == int(before["state_revision"]) + 1 and int(retained[0]["tick_number"]) == world.current_tick_number(), "receipt binds authenticated principal, exact payload, revision and applying tick")
		var expected: Array = before["receipts"].duplicate(true)
		expected.append(retained[0])
		check(state()["receipts"] == expected, "only intended production receipt added")
	var saw_ack: bool = false
	var saw_observation: bool = false
	for frame in remote.frames:
		if frame.get("type") == "ack" and frame.get("request_id") == id and frame.get("ok") == true: saw_ack = true
		elif saw_ack and frame.get("type") == "observation" and int(frame["production"]["state_revision"]) == int(state()["state_revision"]): saw_observation = true
	check(saw_observation, "matching successful ack precedes fresh production observation")
	return results[id].is_success

func self_step(payload: Dictionary) -> bool:
	var before: Dictionary = owner().duplicate(true)
	var command: SimulationCommand = action(payload)
	if not await tick_command(command): return false
	return await settled(command, before)

func production_probe(transport: RemoteWorldRuntime, operation: String, payload: Dictionary, id: String, foreign: bool = false, accepted: bool = false) -> void:
	var before: Dictionary = state().duplicate(true)
	var inventory_before: Dictionary = owner().duplicate(true)
	var tools_before: Dictionary = (world.get_simulation_system(ToolSimulationSystem.SYSTEM_ID) as ToolSimulationSystem).capture_snapshot().value
	var receipts: Dictionary = foreign_results if foreign else results
	receipts.erase(id) # A retained retry must receive a new ack, never reuse the old result.
	var frame_count: int = remote.frames.size()
	var command := ProductionDevelopmentCommand.new()
	command.command_id = StringName(id)
	command.operation = StringName(operation)
	command.payload = payload
	check(transport.enqueue_command(command).is_success, "explicit direct wire probe admitted")
	if not await tick_command(command, foreign): return
	check(receipts[id].is_success == accepted, "matching probe outcome: " + receipts[id].message)
	if not foreign:
		check(remote.frames.slice(frame_count).any(func(frame: Dictionary) -> bool: return frame.get("type") == "ack" and frame.get("request_id") == id and frame.get("ok") == accepted), "new wire ack settles this denial/retained retry")
	var after: Dictionary = state().duplicate(true)
	after["last_tick"] = before["last_tick"]
	var tools_after: Dictionary = (world.get_simulation_system(ToolSimulationSystem.SYSTEM_ID) as ToolSimulationSystem).capture_snapshot().value
	tools_after["last_tick"] = tools_before["last_tick"]
	check(after == before and owner() == inventory_before and tools_after == tools_before, "denial/retained retry preserves complete production, inventory and tools except time")
	await wait_for(func() -> bool: return int(panel._production.get("state_revision", -1)) == int(state()["state_revision"]), "probe observation catches up")

func conserved() -> void:
	var items: Array = owner()["ledger"]["items"].duplicate(true)
	for item in items:
		if item["item_id"] in ["crowbar-1", "extractor-2"]: item["container_id"] = canonical_item(baseline, item["item_id"])["container_id"]
	check(items == baseline["ledger"]["items"], "complete physical records conserve IDs, definitions, condition and provenance")
	check(body(owner(), "body.human-2") == body(baseline, "body.human-2"), "foreign body unchanged")
	var cargo: int = int(state()["cargo"].get("resource-canister-2", {}).get("ore.iron", 0))
	check(int(panel._record["mass_milligrams"]) == carried_mass + cargo, "shell-inclusive body mass counts completed payload once")

func resources() -> void:
	var current: Dictionary = state()
	var reserve: int = int(current["job"].get("inputs", {}).get("ore.iron", 0))
	var cargo: int = int(current["cargo"].get("resource-canister-2", {}).get("ore.iron", 0))
	check(int(current["deposits"]["deposit.iron"]) + reserve + cargo == int(initial["deposits"]["deposit.iron"]), "finite iron source plus unprocessed reservation plus cargo conserves exact integer mass")
	var expected_cargo: Dictionary = initial["cargo"].duplicate(true)
	if completed > 0:
		var stock: Dictionary = {}
		for material in initial["store"]: stock[material] = 0
		stock["ore.iron"] = completed * 1000000
		expected_cargo["resource-canister-2"] = stock
	check(current["cargo"] == expected_cargo, "only bound carrier receives the exact ore identity; other material stocks unchanged")
	check(cargo == completed * 1000000 and int(current["energy_joules"]) == int(initial["energy_joules"]) - completed * 250, "only completed cycles produce matter and debit energy")
	var unchanged: Dictionary = current.duplicate(true)
	for field in ["last_tick", "state_revision", "receipts", "job", "deposits", "cargo", "energy_joules"]: unchanged[field] = initial[field]
	check(unchanged == initial, "all unrelated production records unchanged")
	var deposits: Dictionary = current["deposits"].duplicate(true)
	deposits["deposit.iron"] = initial["deposits"]["deposit.iron"]
	check(deposits == initial["deposits"], "other finite deposits unchanged")
	var tools: Dictionary = (world.get_simulation_system(ToolSimulationSystem.SYSTEM_ID) as ToolSimulationSystem).capture_snapshot().value
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/tools/catalog.v1.json"))
	for part_id in tools["ledger"]["assemblies"]["extractor-2"]["slots"].values():
		var part: Dictionary = tools["ledger"]["parts"][part_id]
		var original: Dictionary = initial_tools["ledger"]["parts"][part_id]
		var wear: int = int(catalog["materials"][part["material_id"]]["wear_ppm_per_cycle"]) * int(catalog["components"][part["definition_id"]]["wear_scale_permille"]) * completed + int(original["wear_remainder"])
		check(int(part["integrity_ppm"]) == int(original["integrity_ppm"]) - wear / 1000 and int(part["wear_remainder"]) == wear % 1000, "completed work charges exact whole/fractional wear only: " + part_id)
		part["integrity_ppm"] = original["integrity_ppm"]
		part["wear_remainder"] = original["wear_remainder"]
	check(int(tools["ledger"]["state_revision"]) == int(initial_tools["ledger"]["state_revision"]) + completed, "one tool ledger revision per completed cycle")
	tools["ledger"]["state_revision"] = initial_tools["ledger"]["state_revision"]
	tools["last_tick"] = initial_tools["last_tick"]
	check(tools == initial_tools, "all tool part identities, materials, mounts and provenance preserved apart from completed wear/revision")
	check(production.validate_snapshot_record(current, world.current_tick_number()).is_success, "complete production resource budget validates")

func paused() -> void:
	check(state()["job"]["extraction"]["status"] == "paused" and state()["job"]["extraction"]["pause_reason"] == "capability", "lost active tool pauses work canonically")
	var before: Dictionary = state().duplicate(true)
	steps(120)
	var after: Dictionary = state().duplicate(true)
	after["last_tick"] = before["last_tick"]
	check(after == before, "paused ticks cannot advance countdown, resurrect source, emit yield or debit energy")
	resources()

func exercise() -> void:
	directory = OS.get_user_data_dir().path_join("extraction-wire-%d" % Time.get_ticks_usec())
	if not start_host(27863): return
	client = ContainerClient.new()
	(client as ContainerClient).port = 27863
	client.invite = KEYS[1]
	root.add_child(client)
	client.set_process(false)
	client._habitat.character.read_local_keyboard = false
	client._habitat.character.set_physics_process(false)
	remote = client._remote as TracedRemote
	remote.command_completed.connect(func(command: SimulationCommand, result: ServiceResult) -> void: results[String(command.command_id)] = result)
	panel = client._inventory_panel
	observer = RemoteWorldRuntime.new()
	root.add_child(observer)
	observer.command_completed.connect(func(command: SimulationCommand, result: ServiceResult) -> void: foreign_results[String(command.command_id)] = result)
	check(observer.connect_host("ws://127.0.0.1:27863", KEYS[0]).is_success, "foreign invite authenticates")
	if not await wait_for(func() -> bool: return client._body_initialized and observer.server_slot == 0, "two authenticated shells observed"): return
	check(remote.server_slot == 1 and panel._record["body_id"] == "body.human-1", "host chooses body and principal")
	production = world.get_simulation_system(ProductionSimulationSystem.SYSTEM_ID)
	runner = world.get_node("SimulationRunner")
	runner.set_physics_process(false)
	choose(panel._world_root, "world.tray-1")
	choose(panel._destination, "body.human-1")
	for index in range(panel._world_items.item_count):
		if panel._world_items.get_item_metadata(index)["item_id"] == "resource-canister-2":
			panel._world_items.select(index)
			panel._world_items.item_selected.emit(index)
	var count: int = remote.sent.size()
	check(not panel._inventory_buttons["pickup"].disabled, "world canister pickup enabled")
	panel._inventory_buttons["pickup"].pressed.emit()
	check(remote.sent.size() == count + 1, "actual shell collects existing physical canister")
	if remote.sent.size() != count + 1: return
	var pickup: SimulationCommand = remote.sent[-1]
	if not await tick_command(pickup): return
	if not await wait_for(func() -> bool: return panel._pending.is_empty() and panel._record["inventory_revision"] == owner()["state_revision"], "fresh owned canister observation"): return
	check(results[String(pickup.command_id)].is_success and canonical_item(owner(), "resource-canister-2")["container_id"] == "body.human-1", "production world pickup grants physical possession, no owner injection")
	baseline = owner().duplicate(true)
	carried_mass = int(panel._record["mass_milligrams"])
	initial = state().duplicate(true)
	initial_tools = (world.get_simulation_system(ToolSimulationSystem.SYSTEM_ID) as ToolSimulationSystem).capture_snapshot().value
	choose_item("crowbar-1")
	choose(panel._slot, "hand.right")
	if not await self_step(intent("equip", "crowbar-1", "storage.pouch-1", "", "hand.right")): return
	if not await self_step(intent("select_hand", "", "", "", "hand.right")): return
	# Move through the actual shell's bounded movement sampler, never canonical pose injection.
	runner.set_physics_process(true)
	await create_timer(0.6).timeout
	var approach: SimulationCommand = move_to([0, 950, 0])
	if approach == null: return
	if not await wait_for(func() -> bool: return results.has(String(approach.command_id)) and not client._movement_pending, "first bounded shell movement"): return
	check(results[String(approach.command_id)].is_success, "first bounded step accepted")
	await create_timer(0.6).timeout
	var movement: SimulationCommand = move_to([-3000, 950, -1000])
	if movement == null: return
	if not await wait_for(func() -> bool: return results.has(String(movement.command_id)) and not client._movement_pending, "authenticated source approach"): return
	check(results[String(movement.command_id)].is_success and own_position(1) == [-3000, 950, -1000], "host accepts source-reachable shell movement")
	runner.set_physics_process(false)
	if not await wait_for(func() -> bool: return panel._production["extractable_sources"].has("deposit.iron"), "host observes exact source reach"): return
	choose(panel._deposit, "deposit.iron")
	choose(panel._carrier, "resource-canister-2")
	panel._work_cycles.value = 3
	var probe: Dictionary = {"deposit_id": "deposit.iron", "carrier_id": "resource-canister-2", "cycles": 3, "expected_revision": state()["state_revision"]}
	await production_probe(remote, "start_tool_extract", probe, "extract.wrong-tool")
	choose(panel._destination, "storage.pouch-1")
	if not await self_step(intent("unequip", "", "", "storage.pouch-1", "hand.right")): return
	choose_item("extractor-2")
	if not await self_step(intent("equip", "extractor-2", "storage.backpack-1", "", "hand.right")): return
	check(panel._active_tool.text.contains("extractor-2"), "actual extraction label observes explicitly active equipped tool")
	probe["carrier_id"] = "resource-canister-1"
	await production_probe(remote, "start_tool_extract", probe, "extract.foreign-carrier")
	probe["carrier_id"] = "resource-canister-2"
	probe["deposit_id"] = "deposit.ice"
	await production_probe(remote, "start_tool_extract", probe, "extract.out-of-reach")
	probe["deposit_id"] = "deposit.iron"
	var before: Dictionary = state().duplicate(true)
	var start: SimulationCommand = production_button("start_tool_extract")
	if start == null: return
	var pinned: Dictionary = start.payload.duplicate(true)
	if not await wait_for(func() -> bool: return not host._pending.is_empty(), "host holds original extraction intent"): return
	count = remote.sent.size()
	choose(panel._deposit, "deposit.ice")
	panel._work_cycles.value = 1
	panel._sustained_action("start_tool_extract")
	check(remote.sent.size() == count and start.payload == pinned and state() == before, "picker changes/repeated action cannot alter pending intent or reserve optimistically")
	if not await production_settled(start, before): return
	check(state()["job"]["extraction"]["tool_id"] == "extractor-2" and state()["job"]["extraction"]["carrier_id"] == "resource-canister-2" and state()["job"]["extraction"]["request_id"] == "net-1-" + String(start.command_id), "canonical work binds original authenticated request/tool/carrier")
	check(int(state()["deposits"]["deposit.iron"]) == int(initial["deposits"]["deposit.iron"]) - 3000000, "start reserves exactly finite requested mass")
	# Midwork loss is exercised using actual equipment controls.
	steps(10)
	if not await self_step(intent("switch_hand")): return
	paused()
	await production_probe(remote, "resume_tool_extract", {"expected_revision": state()["state_revision"]}, "extract.wrong-hand-resume")
	choose(panel._slot, "hand.right")
	if not await self_step(intent("select_hand", "", "", "", "hand.right")): return
	check(state()["job"]["extraction"]["status"] == "paused", "restoring hand never automatically resumes")
	before = state().duplicate(true)
	if not await production_settled(production_button("resume_tool_extract"), before): return
	steps(int(state()["job"]["remaining_ticks"]))
	completed = 1
	if not await wait_for(func() -> bool: return int(panel._production["state_revision"]) == int(state()["state_revision"]) and int(panel._record["mass_milligrams"]) == carried_mass + 1000000, "completed yield and loaded mass observed"): return
	resources()
	conserved()
	choose(panel._destination, "storage.backpack-1")
	if not await self_step(intent("unequip", "", "", "storage.backpack-1", "hand.right")): return
	paused()
	await production_probe(remote, "resume_tool_extract", {"expected_revision": state()["state_revision"]}, "extract.unequipped-resume")
	choose_item("extractor-2")
	if not await self_step(intent("equip", "extractor-2", "storage.backpack-1", "", "hand.right")): return
	check(state()["job"]["extraction"]["status"] == "paused", "re-equipping never automatically resumes")
	# Exact original retained request is retried through production transport; no new yield.
	await production_probe(remote, "start_tool_extract", pinned, String(start.command_id), false, true)
	await production_probe(observer, "cancel_tool_extract", {"expected_revision": state()["state_revision"]}, "extract.foreign-cancel", true)
	before = state().duplicate(true)
	if not await production_settled(production_button("resume_tool_extract"), before): return
	steps(int(state()["job"]["remaining_ticks"]))
	completed = 2
	if not await wait_for(func() -> bool: return int(panel._production["state_revision"]) == int(state()["state_revision"]) and int(panel._record["mass_milligrams"]) == carried_mass + 2000000, "second bounded output observed"): return
	resources()
	steps(60)
	check(state()["job"]["extraction"]["status"] == "paused" and state()["job"]["extraction"]["pause_reason"] == "capacity", "full 2 kg carrier pauses final reserved cycle")
	resources()
	if not await wait_for(func() -> bool: return int(panel._production["state_revision"]) == int(state()["state_revision"]), "capacity pause observed"): return
	before = state().duplicate(true)
	if not await production_settled(production_button("cancel_tool_extract"), before): return
	check(state()["job"].is_empty() and int(state()["deposits"]["deposit.iron"]) == int(initial["deposits"]["deposit.iron"]) - 2000000, "cancel releases only unprocessed reserve, keeps completed yield finite")
	await production_probe(remote, "start_tool_extract", {"deposit_id": "deposit.iron", "carrier_id": "resource-canister-2", "cycles": 9, "expected_revision": state()["state_revision"]}, "extract.finite-source")
	await production_probe(remote, "start_tool_extract", pinned, String(start.command_id), false, true)
	steps(120)
	check(state()["job"].is_empty(), "retained canceled start never resurrects work")
	resources()
	conserved()
	if failures == 0: print("Active-hand extraction transport: explicit owned tool/carrier, exact receipts, denials, interruption, retained retries, finite conservation passed.")
