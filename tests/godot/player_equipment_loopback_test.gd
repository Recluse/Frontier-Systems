extends "res://tests/godot/player_inventory_closure_loopback_test.gd"

## Reuse authenticated shell, traced production transport, bounded waits and cleanup.
## Only selector/button signals and fixture tick scheduling are synthetic.
var baseline: Dictionary
var carried_mass: int

func choose(picker: OptionButton, id: String) -> void:
	for index in range(picker.item_count):
		if picker.get_item_metadata(index) == id:
			picker.select(index)
			picker.item_selected.emit(index)
			return
	check(false, "observed picker includes " + id)

func choose_item(id: String) -> void:
	for index in range(panel._items.item_count):
		if panel._items.get_item_metadata(index)["item_id"] == id:
			panel._items.select(index)
			panel._items.item_selected.emit(index)
			return
	check(false, "observed item list includes " + id)

func intent(operation: String, item: String = "", source: String = "", destination: String = "", slot: String = "") -> Dictionary:
	return {"operation": operation, "item_id": item, "source_container_id": source, "destination_container_id": destination, "slot_id": slot, "expected_revision": panel._record["inventory_revision"]}

func action(payload: Dictionary) -> SimulationCommand:
	var count: int = remote.sent.size()
	var operation: String = payload["operation"]
	check(not panel._inventory_buttons[operation].disabled, "actual equipment button enabled for " + operation)
	panel._inventory_buttons[operation].pressed.emit()
	check(remote.sent.size() == count + 1, "button emits exactly one equipment intent")
	if remote.sent.size() != count + 1: return null
	var command: SimulationCommand = remote.sent[-1]
	check(command.operation == &"self" and command.payload == payload, "exact closed self payload reaches production transport")
	check(command.authenticated_context == null, "client supplies no authoritative principal")
	check(panel._pending == String(command.command_id) and panel._pending_inventory == payload, "panel retains exact pending identity and intent")
	return command

func body(record: Dictionary, id: String = "body.human-1") -> Dictionary:
	for entry in record["bodies"]:
		if entry["body_id"] == id: return entry
	check(false, "canonical body exists")
	return {}

func canonical_item(record: Dictionary, id: String) -> Dictionary:
	for entry in record["ledger"]["items"]:
		if entry["item_id"] == id: return entry
	check(false, "canonical item exists")
	return {}

func binding(record: Dictionary, slot: String) -> String:
	for entry in body(record)["equipped"]:
		if entry["slot_id"] == slot: return entry["item_id"]
	return ""

func conserved() -> void:
	var current: Dictionary = owner()
	var items: Array = current["ledger"]["items"].duplicate(true)
	for item in items:
		var original: Dictionary = canonical_item(baseline, item["item_id"])
		if item["item_id"] in ["crowbar-1", "extractor-2"]:
			item["container_id"] = original["container_id"]
	check(items == baseline["ledger"]["items"], "all item identities, definition revisions, condition and provenance fields conserved")
	check(body(current, "body.human-2") == body(baseline, "body.human-2"), "foreign body's complete equipment/revision state unchanged")
	check(panel._record["mass_milligrams"] == carried_mass, "exact integer carried mass conserved")

func settled(command: SimulationCommand, before: Dictionary) -> bool:
	if command == null: return false
	var id: String = String(command.command_id)
	if not await wait_for(func() -> bool: return results.has(id) and panel._pending.is_empty() and panel._record.get("inventory_revision") == owner()["state_revision"], "matching equipment wire receipt and post-tick observation"): return false
	check(results[id].is_success, "host accepts explicit equipment intent")
	check(remote.frames.any(func(frame: Dictionary) -> bool: return frame.get("type") == "ack" and frame.get("request_id") == id and frame.get("ok") == true), "real successful ack retains exact client request ID")
	var after: Dictionary = owner()
	var request_id: String = "net-1-" + id
	var payload: Dictionary = command.payload
	var fingerprint: String = JSON.stringify(["self", before["owner_id"], request_id, "body.human-1", payload["operation"], payload["item_id"], payload["source_container_id"], payload["destination_container_id"], payload["slot_id"], int(payload["expected_revision"])]).sha256_text()
	var matching: Array = after["receipts"].filter(func(receipt: Dictionary) -> bool: return receipt["request_id"] == request_id)
	check(matching.size() == 1, "exact authenticated canonical self receipt retained once")
	if matching.size() == 1:
		check(matching[0]["fingerprint"] == fingerprint and int(matching[0]["state_revision"]) == int(before["state_revision"]) + 1, "canonical receipt binds exact owner/body/payload/revision")
	var expected_receipts: Array = before["receipts"].duplicate(true)
	expected_receipts.append({"request_id": request_id, "fingerprint": fingerprint, "state_revision": int(before["state_revision"]) + 1})
	check(after["receipts"] == expected_receipts and int(after["state_revision"]) == int(before["state_revision"]) + 1, "exact prior receipt history plus only this accepted request")
	var saw_ack: bool = false
	var ack_then_observation: bool = false
	for frame in remote.frames:
		if frame.get("type") == "ack" and frame.get("request_id") == id: saw_ack = true
		elif saw_ack and frame.get("type") == "observation" and frame["inventory"]["inventory_revision"] == after["state_revision"]: ack_then_observation = true
	check(ack_then_observation, "matching ack precedes fresh canonical equipment observation on real wire")
	if payload["operation"] in ["switch_hand", "select_hand"]:
		check(after["ledger"] == before["ledger"] and body(after)["equipped"] == body(before)["equipped"], "hand selection preserves complete ledger and bindings")
	check(int(body(after)["state_revision"]) == int(body(before)["state_revision"]) + 1, "only acting body revision advances for self intent")
	check(panel._equipment_record["equipped"] == body(after)["equipped"] and panel._equipment_record["active_hand_slot_id"] == body(after)["active_hand_slot_id"], "shell bindings/active hand equal fresh canonical observation")
	conserved()
	return true

func denied(transport: RemoteWorldRuntime, payload: Dictionary, id: String, foreign: bool = false) -> void:
	var before: Dictionary = owner().duplicate(true)
	var command := InventoryDevelopmentCommand.new()
	command.command_id = StringName(id)
	command.operation = &"self"
	command.payload = payload
	check(transport.enqueue_command(command).is_success, "denial probe admitted through authenticated real transport")
	var receipts: Dictionary = foreign_results if foreign else results
	if not await wait_for(func() -> bool: return receipts.has(id), "matching host rejection arrives"): return
	check(not receipts[id].is_success and owner() == before, "rejection preserves full canonical owner including receipts/revisions")

func exercise() -> void:
	directory = OS.get_user_data_dir().path_join("equipment-wire-%d" % Time.get_ticks_usec())
	if not start_host(27861): return
	client = ContainerClient.new()
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
	check(observer.connect_host("ws://127.0.0.1:27861", KEYS[0]).is_success, "foreign principal authenticates")
	if not await wait_for(func() -> bool: return client._body_initialized and observer.server_slot == 0, "both authenticated sessions observed"): return
	check(remote.server_slot == 1 and panel._record["body_id"] == "body.human-1", "host selects owner body independently from client")
	baseline = owner().duplicate(true)
	carried_mass = panel._record["mass_milligrams"]
	choose_item("crowbar-1")
	choose(panel._slot, "hand.right")
	var equip: Dictionary = intent("equip", "crowbar-1", "storage.pouch-1", "", "hand.right")
	await denied(observer, equip, "equipment.foreign.equip", true)
	var close: SimulationCommand = closure("storage.backpack-1", "close_container")
	if not await settle(close, "storage.backpack-1", false): return
	equip["expected_revision"] = int(panel._record["inventory_revision"])
	var count: int = remote.sent.size()
	check(panel._inventory_buttons["equip"].disabled, "closed ancestor disables real equip button")
	panel._self_action("equip")
	check(remote.sent.size() == count and panel._result.text.contains("storage.backpack-1"), "local closed path guidance submits nothing")
	await denied(remote, equip, "equipment.closed.equip")
	var opened: SimulationCommand = closure("storage.backpack-1", "open_container")
	if not await settle(opened, "storage.backpack-1", true): return
	choose_item("crowbar-1")
	choose(panel._slot, "hand.right")
	var before: Dictionary = owner().duplicate(true)
	world.get_node("SimulationRunner").set_physics_process(false)
	var command: SimulationCommand = action(intent("equip", "crowbar-1", "storage.pouch-1", "", "hand.right"))
	if command == null: return
	var pinned: Dictionary = command.payload.duplicate(true)
	if not await wait_for(func() -> bool: return not host._pending.is_empty(), "host queues original equipment request"): return
	count = remote.sent.size()
	var frames: int = remote.frames.size()
	choose(panel._slot, "hand.left")
	if not await wait_for(func() -> bool: return remote.frames.size() > frames, "fresh real observations continue during held equip"): return
	panel._self_action("switch_hand")
	check(owner() == before and panel._equipment_record["equipped"] == body(before)["equipped"], "pending equip never predicts a canonical or observed binding")
	check(remote.sent.size() == count and command.payload == pinned and panel._pending_inventory == pinned, "picker change/repeat cannot retarget or replay pending command")
	world.get_node("SimulationRunner").set_physics_process(true)
	if not await settled(command, before): return
	check(binding(owner(), "hand.right") == "crowbar-1" and canonical_item(owner(), "crowbar-1")["container_id"] == "body.human-1", "equip moves one nested item to owner root and binds exact slot")
	check(body(owner())["active_hand_slot_id"] == "hand.left", "equipping right hand does not select it")
	choose(panel._slot, "hand.right")
	before = owner().duplicate(true)
	command = action(intent("select_hand", "", "", "", "hand.right"))
	if not await settled(command, before): return
	check(panel._equipment.text.contains("Active hand item: Crowbar · crowbar-1"), "explicit hand selection observes exact held tool")
	before = owner().duplicate(true)
	command = action(intent("switch_hand"))
	if not await settled(command, before): return
	check(body(owner())["active_hand_slot_id"] == "hand.left" and binding(owner(), "hand.right") == "crowbar-1", "hand switch preserves right tool binding")
	choose(panel._slot, "hand.right")
	choose(panel._destination, "storage.pouch-1")
	var closed: SimulationCommand = closure("storage.backpack-1", "close_container")
	if not await settle(closed, "storage.backpack-1", false): return
	await denied(remote, intent("unequip", "", "", "storage.pouch-1", "hand.right"), "equipment.closed.unequip")
	check(binding(owner(), "hand.right") == "crowbar-1", "closed destination preserves equipped tool")
	opened = closure("storage.backpack-1", "open_container")
	if not await settle(opened, "storage.backpack-1", true): return
	before = owner().duplicate(true)
	command = action(intent("unequip", "", "", "storage.pouch-1", "hand.right"))
	if not await settled(command, before): return
	check(binding(owner(), "hand.right") == "" and canonical_item(owner(), "crowbar-1")["container_id"] == "storage.pouch-1", "explicit unequip returns exact nested tool and removes only its binding")
	choose_item("extractor-2")
	choose(panel._slot, "hand.right")
	before = owner().duplicate(true)
	command = action(intent("equip", "extractor-2", "storage.backpack-1", "", "hand.right"))
	if not await settled(command, before): return
	before = owner().duplicate(true)
	command = action(intent("select_hand", "", "", "", "hand.right"))
	if not await settled(command, before): return
	check(panel._active_tool.text.contains("Active hand item: Resource extractor · extractor-2"), "hand-tool control uses fresh host-observed selected extractor")
	await denied(observer, intent("unequip", "", "", "storage.pouch-1", "hand.right"), "equipment.foreign.unequip", true)
	choose(panel._destination, "storage.backpack-1")
	before = owner().duplicate(true)
	command = action(intent("unequip", "", "", "storage.backpack-1", "hand.right"))
	if not await settled(command, before): return
	check(panel._equipment.text.contains("Active hand item: empty in this observation."), "unequipping active tool observes empty hand")
	check(owner()["ledger"]["items"] == baseline["ledger"]["items"], "final full ledger item records restored without material loss")
	check(body(owner())["equipped"] == body(baseline)["equipped"], "final original equipment bindings restored")
	print("Equipment transport acceptance: exact self receipts, foreign/closed denials, explicit reopening, active tools and conservation checked.")
