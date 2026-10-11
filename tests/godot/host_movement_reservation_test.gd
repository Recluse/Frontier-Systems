extends "res://tests/godot/player_inventory_closure_route_test.gd"

## Real host admission and fixed-tick completion; only socket output is recorded.
func run() -> void:
	world = WorldRuntime.new()
	root.add_child(world)
	check(world.start_simulation().is_success, "start canonical runtime")
	var runner := world.get_node("SimulationRunner") as SimulationRunner
	runner.set_physics_process(false)
	inventory = world.get_simulation_system(InventorySimulationSystem.SYSTEM_ID)
	host = RecordingHost.new()
	root.add_child(host)
	host.set_process(false)
	host._world = world
	host._keys = ["movement-reservation-actor-000000000000", "movement-reservation-target-00000000000"]
	world.command_completed.connect(host._on_completed)
	add_peer(1)
	host._receive(1, {"type": "authenticate", "key": host._keys[0]})
	host._peers[1]["last_move"] = Time.get_ticks_msec() - 500
	var admitted_at: int = host._peers[1]["last_move"]
	host._receive(1, {"type": "command", "request_id": "duplicate", "system": "inventory", "operation": "self", "payload": {}})
	check(host._pending.size() == 1, "nonmovement request is genuinely queued")
	host._receive(1, move_frame("duplicate"))
	check(host.frames[-1]["frame"]["code"] == "request_pending", "duplicate route is rejected")
	check(not host._peers[1]["pending_move"] and host._peers[1]["last_move"] == admitted_at, "duplicate rejection reserves neither movement nor elapsed budget")
	runner._physics_process(1.0 / 60.0)
	check(host._pending.is_empty(), "original nonmovement request completes")
	host._receive(1, move_frame("fresh"))
	check(host._pending.size() == 1 and host._peers[1]["pending_move"], "fresh movement is admitted after duplicate rejection")
	# An unrelated queue rejection must not release the real pending movement.
	var queue_limit: int = runner.max_queued_external_commands
	runner.max_queued_external_commands = 0
	host._receive(1, {"type": "command", "request_id": "unrelated", "system": "inventory", "operation": "self", "payload": {}})
	runner.max_queued_external_commands = queue_limit
	check(host.frames[-1]["frame"]["code"] == "command_queue_full" and host._peers[1]["pending_move"], "unrelated queue failure preserves movement reservation")
	# Exercise host backpressure independently of the simulation queue limit.
	for index in range(31): host._pending["fixture-%d" % index] = {"peer": 2, "request_id": "fixture-%d" % index}
	host._receive(1, {"type": "command", "request_id": "busy", "system": "inventory", "operation": "self", "payload": {}})
	check(host.frames[-1]["frame"]["code"] == "host_backpressure" and host._peers[1]["pending_move"], "unrelated host backpressure preserves movement reservation")
	for index in range(31): host._pending.erase("fixture-%d" % index)
	host._receive(1, move_frame("second"))
	check(host.frames[-1]["frame"]["code"] == "movement_rejected" and host._pending.size() == 1, "one pending move still excludes a second move")
	runner._physics_process(1.0 / 60.0)
	check(not host._peers[1]["pending_move"] and host._pending.is_empty(), "actual movement completion releases reservation")
	check(inventory.own_position(host._context(0, 1)).value == [100, 0, 0], "admitted movement reaches canonical position")
	host.free()
	world.free()
	print("Movement admission reservation: %d failures" % failures)
	quit(1 if failures else 0)

func move_frame(id: String) -> Dictionary:
	return {"type": "command", "request_id": id, "system": "inventory", "operation": "move_to", "payload": {"position_millimetres": [100, 0, 0]}}
