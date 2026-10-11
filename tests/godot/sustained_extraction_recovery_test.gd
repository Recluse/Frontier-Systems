extends "res://tests/godot/player_extraction_loopback_test.gd"

## PR97 helpers retain the actual equipment, transport and conservation owner.
## Only controls/tick scheduling are synthetic. Replacement is not a crash.
var paid: Dictionary
var paid_tools: Dictionary
var paid_owner: Dictionary
var start_intent: SimulationCommand

func tools() -> Dictionary:
	return (world.get_simulation_system(ToolSimulationSystem.SYSTEM_ID) as ToolSimulationSystem).capture_snapshot().value

func unchanged_paid(expected: Dictionary, message: String) -> void:
	var current: Dictionary = state().duplicate(true)
	current["last_tick"] = expected["last_tick"]
	check(same_record(current, expected), message + ": complete production state")
	var current_tools: Dictionary = tools().duplicate(true)
	current_tools["last_tick"] = paid_tools["last_tick"]
	check(same_record(current_tools, paid_tools), message + ": complete component identities/provenance/paid wear")
	check(same_record(owner(), paid_owner), message + ": exact owned equipment/carrier/revisions")
	resources()

## JSON fixture floats and restored integral values differ in Variant type.
## Preserve every key, array order and value; only allow exact integral numeric
## type conversion inside JSON's exact integer range. Never truncate fractions.
func same_record(left: Variant, right: Variant) -> bool:
	if left is Dictionary and right is Dictionary:
		if left.size() != right.size(): return false
		for key in left:
			if not right.has(key) or not same_record(left[key], right[key]): return false
		return true
	if left is Array and right is Array:
		if left.size() != right.size(): return false
		for index in range(left.size()):
			if not same_record(left[index], right[index]): return false
		return true
	if typeof(left) != typeof(right):
		if typeof(left) not in [TYPE_INT, TYPE_FLOAT] or typeof(right) not in [TYPE_INT, TYPE_FLOAT]: return false
		return abs(float(left)) <= 9007199254740991 and abs(float(right)) <= 9007199254740991 and float(left) == floor(float(left)) and float(right) == floor(float(right)) and left == right
	return left == right

func restored_identity() -> void:
	var items: Array = owner()["ledger"]["items"].duplicate(true)
	for item in items:
		if item["item_id"] in ["crowbar-1", "extractor-2"]: item["container_id"] = canonical_item(baseline, item["item_id"])["container_id"]
	check(same_record(items, baseline["ledger"]["items"]), "all original item fields/provenance conserved allowing only exact integral numeric type conversion")
	check(same_record(body(owner(), "body.human-2"), body(baseline, "body.human-2")), "foreign body exact keys/order/values/revisions preserved")
func replace_and_reconnect(abandon: bool) -> bool:
	var count: int = remote.sent.size()
	var abandoned: String = ""
	if abandon:
		# Cancel is valid while running; close host before it polls this request.
		var command: SimulationCommand = production_button("cancel_tool_extract")
		if command == null: return false
		abandoned = String(command.command_id)
		count += 1
	if is_instance_valid(observer): observer.free()
	host.free()
	if not await wait_for(func() -> bool: return not client._body_initialized and client._latest.is_empty(), "same shell observes real transport loss"): return false
	if abandon:
		check(results.has(abandoned) and not results[abandoned].is_success and remote._requests.is_empty(), "uncertain pending Cancel abandoned without claiming success")
	check(remote.sent.size() == count and panel._record.is_empty(), "disconnect clears observation without new action")
	store.free()
	world.free()
	if not start_host(27849): return false
	runner = world.get_node("SimulationRunner")
	runner.set_physics_process(false)
	production = world.get_simulation_system(ProductionSimulationSystem.SYSTEM_ID)
	completed = 1
	var expected: Dictionary = paid.duplicate(true)
	expected["job"]["extraction"]["status"] = "paused"
	expected["job"]["extraction"]["pause_reason"] = "restart"
	unchanged_paid(expected, "native replacement changes only restart pause")
	restored_identity()
	var frames: int = remote.frames.size()
	await process_frame
	check(client._latest.is_empty() and remote.sent.size() == count, "replacement never automatically reconnects or replays")
	check(not client._reconnect.disabled, "actual manual reconnect button enabled")
	client._reconnect.pressed.emit()
	if not await wait_for(func() -> bool: return client._body_initialized and not client._latest.is_empty(), "same client manually reauthenticates original invite"): return false
	panel = client._inventory_panel
	check(remote.server_slot == 1 and panel._record["body_id"] == "body.human-1", "host restores initiating principal and equipped body")
	check(remote.sent.size() == count and remote._requests.is_empty(), "manual reconnect transmits no abandoned or automatic extraction action")
	check(not remote.frames.slice(frames).any(func(frame: Dictionary) -> bool: return frame.get("type") == "ack"), "fresh reconnect receives observations without command acknowledgement")
	check(panel._active_tool.text.contains("extractor-2"), "fresh shell observes saved active equipped extractor")
	steps(180)
	unchanged_paid(expected, "paused replacement cannot advance countdown/yield/reserve/energy/wear")
	if not await wait_for(func() -> bool: return int(panel._production.get("state_revision", -1)) == int(state()["state_revision"]), "fresh restored production revision"): return false
	await production_probe(remote, "start_tool_extract", start_intent.payload, String(start_intent.command_id), false, true)
	await production_probe(remote, "resume_tool_extract", {"expected_revision": int(state()["state_revision"]) - 1}, "recovery.stale.%d" % count)
	unchanged_paid(expected, "retained start and stale Resume cannot mutate paid paused records")
	return true

func exercise() -> void:
	directory = OS.get_user_data_dir().path_join("extraction-recovery-%d" % Time.get_ticks_usec())
	if not start_host(27849): return
	client = ContainerClient.new()
	(client as ContainerClient).port = 27849
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
	check(observer.connect_host("ws://127.0.0.1:27849", KEYS[0]).is_success, "foreign invite authenticates")
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
	panel._work_cycles.value = 2
	var probe: Dictionary = {"deposit_id": "deposit.iron", "carrier_id": "resource-canister-2", "cycles": 2, "expected_revision": state()["state_revision"]}
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
	check(int(state()["deposits"]["deposit.iron"]) == int(initial["deposits"]["deposit.iron"]) - 2000000, "start reserves exactly finite requested mass")
	start_intent = start
	steps(int(state()["job"]["remaining_ticks"]))
	completed = 1
	steps(13)
	if not await wait_for(func() -> bool: return int(panel._production["state_revision"]) == int(state()["state_revision"]) and int(panel._record["mass_milligrams"]) == carried_mass + 1000000, "one paid cycle and partial next countdown observed"): return
	resources()
	conserved()
	paid = state().duplicate(true)
	paid_tools = tools().duplicate(true)
	paid_owner = owner().duplicate(true)
	check(paid["job"]["extraction"]["completed_cycles"] == 1 and paid["job"]["extraction"]["remaining_cycles"] == 1 and int(paid["job"]["remaining_ticks"]) > 0 and int(paid["job"]["remaining_ticks"]) < ToolExtractionWork.CYCLE_TICKS, "genuine partly completed paid work with partial remaining countdown")
	# Capture completion synchronously: a subsequent observation may replace status.
	var saves: Dictionary = {}
	remote.command_completed.connect(func(command: SimulationCommand, result: ServiceResult) -> void:
		if command is CheckpointRequest: saves[String(command.command_id)] = {"ok": result.is_success, "status": client._checkpoint_status.text})
	client._host_actions[-1].pressed.emit()
	var save_id: String = String(client._checkpoint_request.command_id)
	if not await wait_for(func() -> bool: return saves.has(save_id), "actual save control receives native disk completion"): return
	check(saves[save_id]["ok"] and saves[save_id]["status"].contains("confirmed on disk"), "checkpoint acknowledgement/status captured at delivery")
	var disk: ServiceResult = LocalWorldSaveStore.read_latest(directory)
	check(disk.is_success, "checksum-validated native checkpoint readback")
	if not disk.is_success: return
	var saved: Dictionary = JSON.parse_string(disk.value["snapshot_json"])
	check(same_record(saved["systems"]["production"], paid) and same_record(saved["systems"]["tools"], paid_tools) and same_record(saved["systems"]["inventory"]["owner"], paid_owner), "disk retains complete paid production, components, equipped tool and carrier")
	if not await replace_and_reconnect(true): return
	before = state().duplicate(true)
	var resumed: SimulationCommand = production_button("resume_tool_extract")
	if not await production_settled(resumed, before): return
	# Resume acceptance itself advances one work tick, with no paid cycle repeated.
	check(state()["job"]["extraction"]["request_id"] == paid["job"]["extraction"]["request_id"] and int(state()["job"]["remaining_ticks"]) == int(paid["job"]["remaining_ticks"]) - 1, "explicit Resume preserves original work binding and remaining countdown")
	steps(int(state()["job"]["remaining_ticks"]) - 1)
	check(not state()["job"].is_empty(), "work cannot complete before exact remaining final tick")
	resources()
	steps(1)
	completed = 2
	check(state()["job"].is_empty(), "explicit valid Resume finishes remaining cycle exactly once")
	resources()
	steps(180)
	resources()
	var resume_receipt: Dictionary = state()["receipts"].filter(func(entry: Dictionary) -> bool: return entry["request_id"] == "net-1-" + String(resumed.command_id))[0].duplicate(true)
	await production_probe(remote, "resume_tool_extract", resumed.payload, String(resumed.command_id), false, true)
	check(state()["receipts"].has(resume_receipt), "completed identical Resume preserves exact immutable prior receipt")
	var changed_resume: Dictionary = resumed.payload.duplicate(true)
	changed_resume["expected_revision"] = state()["state_revision"]
	await production_probe(remote, "resume_tool_extract", changed_resume, String(resumed.command_id))
	check(results[String(resumed.command_id)].message == "Retained request ID identifies different intent.", "changed revision under retained Resume ID rejects")
	await production_probe(remote, "resume_tool_extract", resumed.payload, "resume.fresh-absent")
	check(results["resume.fresh-absent"].message == "No sustained extraction is reserved.", "fresh absent-job Resume remains denied")
	observer = RemoteWorldRuntime.new()
	root.add_child(observer)
	observer.command_completed.connect(func(command: SimulationCommand, result: ServiceResult) -> void: foreign_results[String(command.command_id)] = result)
	check(observer.connect_host("ws://127.0.0.1:27849", KEYS[0]).is_success, "foreign invite reauthenticates replacement host")
	if not await wait_for(func() -> bool: return observer.server_slot == 0, "foreign replacement shell authenticated"): return
	await production_probe(observer, "resume_tool_extract", resumed.payload, String(resumed.command_id), true)
	# Direct canonical ID collision also cannot read another principal's receipt.
	var foreign_context := AuthenticatedCommandContext.from_authenticated_session(&"local-inventory-actor", &"retry.foreign", world.world_id, world.region_id, PackedStringArray(["inventory.operate"]))
	var denied: ServiceResult = production.apply_local(foreign_context, String(resume_receipt["request_id"]), "resume_tool_extract", resumed.payload, world.current_tick_number() + 1)
	check(not denied.is_success and denied.message == "Retained request ID identifies different intent.", "authorized foreign principal cannot retrieve original canonical Resume receipt")
	var revoked_context := AuthenticatedCommandContext.from_authenticated_session(&"local-inventory-target", &"retry.revoked", world.world_id, world.region_id, PackedStringArray())
	denied = production.apply_local(revoked_context, String(resume_receipt["request_id"]), "resume_tool_extract", resumed.payload, world.current_tick_number() + 1)
	check(not denied.is_success, "identical receipt cannot bypass revoked actor permission")
	await production_probe(remote, "resume_tool_extract", resumed.payload, String(resumed.command_id), false, true)
	var original_context := AuthenticatedCommandContext.from_authenticated_session(&"local-inventory-target", &"retry.original", world.world_id, world.region_id, PackedStringArray(["inventory.operate"]))
	var retrieved: ServiceResult = production.apply_local(original_context, String(resume_receipt["request_id"]), "resume_tool_extract", resumed.payload, world.current_tick_number() + 1)
	check(retrieved.is_success and retrieved.value == resume_receipt, "repeated completed retry returns original revision/tick/fingerprint")
	var scope_command := ProductionDevelopmentCommand.new()
	scope_command.command_id = StringName(resume_receipt["request_id"])
	scope_command.operation = "resume_tool_extract"
	scope_command.payload = resumed.payload
	scope_command.authenticated_context = AuthenticatedCommandContext.from_authenticated_session(&"local-inventory-target", &"retry.scope", &"foreign-world", world.region_id, PackedStringArray(["inventory.operate"]))
	check(not scope_command.validate(world).is_success, "retained Resume cannot bypass authenticated world scope")
	await production_probe(remote, "start_tool_extract", start_intent.payload, String(start_intent.command_id), false, true)
	check(state()["job"].is_empty(), "retained Resume/start cannot resurrect completed work")
	# Independently restore the same checkpoint; do not synthesize a replacement job.
	if not await replace_and_reconnect(false): return
	before = state().duplicate(true)
	var canceled: SimulationCommand = production_button("cancel_tool_extract")
	if not await production_settled(canceled, before): return
	check(state()["job"].is_empty() and int(state()["deposits"]["deposit.iron"]) == int(initial["deposits"]["deposit.iron"]) - 1000000, "Cancel returns only one unprocessed reserved kg to original source")
	resources()
	steps(180)
	resources()
	await production_probe(remote, "cancel_tool_extract", canceled.payload, String(canceled.command_id), false, true)
	await production_probe(remote, "start_tool_extract", start_intent.payload, String(start_intent.command_id), false, true)
	check(state()["job"].is_empty(), "retained Cancel/start cannot resurrect canceled work")
	resources()
	if not await wait_for(func() -> bool: return int(panel._record["mass_milligrams"]) == carried_mass + 1000000, "completed original cargo remains observed after Cancel"): return
	check(same_record(owner(), paid_owner), "complete saved equipment/carrier/provenance/body revisions preserved after Cancel")
	check(world.capture_world_snapshot_json().is_success, "complete recovered finite world remains persistable")
	if failures == 0: print("Sustained extraction recovery: native paid checkpoint, explicit reconnect, exact remaining Resume/Cancel and no replay passed.")
