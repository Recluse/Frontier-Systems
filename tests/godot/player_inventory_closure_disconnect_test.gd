extends "res://tests/godot/player_inventory_closure_loopback_test.gd"

## Actual PR89 shell/transport fixture; only the host send seam loses one ack.
## No candidate owner records, receipts, permissions or client outcomes injected.
class LostAckHost extends FirstPlayableHost:
	var lose_request: String = ""
	var withheld: Dictionary = {}
	func _send(id: int, value: Dictionary) -> void:
		if value.get("type") == "ack" and value.get("request_id") == lose_request:
			withheld = value.duplicate(true)
			lose_request = ""
			_peers[id]["socket"].close(-1)
			return
		super._send(id, value)

func create_host() -> FirstPlayableHost:
	return LostAckHost.new()

func has_ack(command: SimulationCommand, from_frame: int = 0) -> bool:
	return remote.frames.slice(from_frame).any(func(frame: Dictionary) -> bool: return frame.get("type") == "ack" and frame.get("request_id") == String(command.command_id))

func verify_commit(before: Dictionary, command: SimulationCommand) -> Dictionary:
	var after: Dictionary = owner().duplicate(true)
	var request_id: String = "net-1-" + String(command.command_id)
	var fingerprint: String = JSON.stringify(["closure", before["owner_id"], "body.human-1", request_id, command.payload["container_id"], command.operation == &"open_container", int(command.payload["expected_revision"])]).sha256_text()
	var receipt: Dictionary = {"request_id": request_id, "fingerprint": fingerprint, "state_revision": int(before["state_revision"]) + 1}
	var receipts: Array = before["receipts"].duplicate(true)
	receipts.append(receipt)
	check(after["receipts"] == receipts and after["state_revision"] == receipt["state_revision"], "one exact authenticated body/intent/revision receipt; no other transaction")
	check(after["ledger"]["items"] == before["ledger"]["items"] and after["bodies"] == before["bodies"], "closure conserves every item/provenance field and both body bindings")
	var expected: Dictionary = before.duplicate(true)
	expected["schema_version"] = 2
	expected["state_revision"] = receipt["state_revision"]
	expected["receipts"] = receipts
	expected["ledger"]["schema_version"] = 2
	expected["ledger"]["state_revision"] = int(before["ledger"]["state_revision"]) + 1
	for container in expected["ledger"]["containers"]:
		if not container.has("is_open"): container["is_open"] = true
		if container["container_id"] == command.payload["container_id"]: container["is_open"] = command.operation == &"open_container"
	check(after == expected, "complete canonical state differs only by versioned closure/revisions/exact receipt")
	return after

func disconnected(command: SimulationCommand, sent_count: int) -> bool:
	if not await wait_for(func() -> bool: return not client._body_initialized and remote._requests.is_empty() and peer_for(1) == -1, "real socket disconnect fences owner shell and host session"): return false
	check(results.has(String(command.command_id)) and results[String(command.command_id)].error_code == &"remote_disconnected", "transport reports unknown outcome rather than host rejection/acceptance")
	check(panel._record.is_empty() and panel._equipment_record.is_empty() and panel._pending.is_empty() and panel._pending_closure.is_empty(), "disconnected presentation clears observations and pending controls")
	var feedback: String = panel._closure_feedback.text
	check(feedback.contains("outcome unknown") and feedback.contains(String(command.command_id)) and feedback.contains(String(command.operation)) and feedback.contains(command.payload["container_id"]) and feedback.contains("revision " + str(command.payload["expected_revision"])), "exact original closure identity remains readable as unknown")
	check(panel._closure_buttons["open_container"].disabled and panel._closure_buttons["close_container"].disabled and remote.sent.size() == sent_count and not has_ack(command), "offline controls disabled, no receipt claim and no replay")
	return true

func reconnect_observe(command: SimulationCommand, committed: Dictionary, mass: int) -> bool:
	var sent_count: int = remote.sent.size()
	var frame_count: int = remote.frames.size()
	var feedback: String = panel._closure_feedback.text
	client._connect_client()
	check(panel._record.is_empty() and remote.sent.size() == sent_count and panel._closure_buttons["open_container"].disabled, "manual reconnect waits for fresh observation without action")
	if not await wait_for(func() -> bool: return client._body_initialized and observed_open("storage.backpack-1", false), "fresh same-owner authenticated observation establishes actual committed closure"): return false
	check(remote.server_slot == 1 and panel._record["body_id"] == "body.human-1" and int(panel._record["inventory_revision"]) == committed["state_revision"], "fresh observed identity and revision match canonical owner")
	await create_timer(0.25).timeout
	check(owner() == committed and panel._record["mass_milligrams"] == mass and remote.sent.size() == sent_count, "fresh observation and repeated ticks conserve exact owner/mass without replay")
	check(panel._closure_feedback.text == feedback and not has_ack(command, frame_count), "fresh state does not invent the lost receipt or replace original uncertainty")
	# A delayed old completion is ignored by the actual panel correlation fence.
	panel._completed(command, ServiceResult.success())
	check(panel._closure_feedback.text == feedback and panel._pending.is_empty(), "late old completion cannot turn unknown into accepted")
	return true

func exercise() -> void:
	directory = OS.get_user_data_dir().path_join("container-disconnect-%d" % Time.get_ticks_usec())
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
	if not await wait_for(func() -> bool: return client._body_initialized and remote.server_slot == 1, "owner authenticates through PR89 actual shell"): return
	var mass: int = panel._record["mass_milligrams"]
	var runner: Node = world.get_node("SimulationRunner")
	for lose_after_commit in [false, true]:
		var before: Dictionary = owner().duplicate(true)
		runner.set_physics_process(false)
		var command: SimulationCommand = closure("storage.backpack-1", "close_container")
		if command == null: return
		if not await wait_for(func() -> bool: return not host._pending.is_empty(), "closure admitted to real host queue before settlement"): return
		var sent_count: int = remote.sent.size()
		await create_timer(0.25).timeout
		check(owner() == before and not observed_open("storage.backpack-1", false) and not panel._pending_closure.is_empty() and remote.sent.size() == sent_count, "admitted command and continuing observations never optimistically close or replay")
		if lose_after_commit:
			(host as LostAckHost).lose_request = String(command.command_id)
			runner.set_physics_process(true)
		else:
			host._peers[peer_for(1)]["socket"].close(-1)
		if not await disconnected(command, sent_count): return
		if not lose_after_commit:
			check(owner() == before and host._pending.is_empty(), "disconnect removes transport routing but has not settled canonical queued work")
			runner.set_physics_process(true)
		if not await wait_for(func() -> bool: return int(owner()["state_revision"]) == int(before["state_revision"]) + 1, "original authenticated queued closure commits even without client receipt"): return
		var committed: Dictionary = verify_commit(before, command)
		if lose_after_commit:
			check((host as LostAckHost).withheld == {"type": "ack", "request_id": String(command.command_id), "ok": true, "code": "", "message": ""}, "production successful matching ack withheld only at host send seam after commit")
		if not await reconnect_observe(command, committed, mass): return
		# Explicit button resubmission allocates a fresh ID/revision, not old replay.
		var resubmitted: SimulationCommand = closure("storage.backpack-1", "close_container")
		if resubmitted == null: return
		check(resubmitted.command_id != command.command_id and int(resubmitted.payload["expected_revision"]) == committed["state_revision"] and remote.sent.size() == sent_count + 1, "explicit user resubmission uses fresh request identity and observed revision")
		if not await wait_for(func() -> bool: return results.has(String(resubmitted.command_id)) and panel._pending.is_empty(), "explicit same-state resubmission receives its own rejection" ): return
		check(not results[String(resubmitted.command_id)].is_success and results[String(resubmitted.command_id)].message.contains("already has") and owner() == committed and observed_open("storage.backpack-1", false), "same-state Close rejected without canonical mutation")
		check(panel._closure_feedback.text.contains("Host rejected") and panel._closure_feedback.text.contains(String(resubmitted.command_id)), "fresh rejected receipt replaces feedback only for explicit new intent")
		check(not has_ack(command) and results[String(command.command_id)].error_code == &"remote_disconnected", "old command stays unknown after fresh command rejected")
		var reopened: SimulationCommand = closure("storage.backpack-1", "open_container")
		if not await settle(reopened, "storage.backpack-1", true): return
		verify_commit(committed, reopened)
		check(panel._record["mass_milligrams"] == mass, "explicit resubmission/reopen preserve exact carried mass")
