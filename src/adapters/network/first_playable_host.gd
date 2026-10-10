extends Node
class_name FirstPlayableHost

## Invite-key host for two persistent fixture bodies. Never accepts client contexts.
const MAX_FRAME: int = 8192
var _world: WorldRuntime
var _listener := TCPServer.new()
var _peers: Dictionary = {}
var _keys: Array[String] = []
var _pending: Dictionary = {}
var _next_peer: int = 1
var _elapsed: float = 0.0
var _events: Array[Dictionary] = []
var persistence: WorldPersistenceAdapter
var _checkpoint_request: Dictionary = {}


func configure(world: WorldRuntime, keys: Array[String], port: int = 27840) -> ServiceResult:
	if _world != null or not is_instance_valid(world) or keys.size() != 2 or keys[0].length() < 32 or keys[1].length() < 32 or keys[0].length() > 256 or keys[1].length() > 256 or keys[0] == keys[1]:
		return ServiceResult.failure(&"host_configuration", "Two distinct operator-provided invite keys of at least 32 characters are required.")
	# Loopback default: publish through a TLS reverse proxy for remote access.
	var error: Error = _listener.listen(port, "127.0.0.1")
	if error != OK:
		return ServiceResult.failure(&"host_listen", "Cannot listen on the configured loopback port.")
	_world = world
	_keys = keys.duplicate()
	if persistence != null:
		persistence.checkpoint_completed.connect(_on_checkpoint_completed)
	world.command_completed.connect(_on_completed)
	(world.get_simulation_system(ProductionSimulationSystem.SYSTEM_ID) as ProductionSimulationSystem).batch_completed.connect(_on_batch_completed)
	return ServiceResult.success()


func _process(delta: float) -> void:
	if _world == null:
		return
	if _listener.is_connection_available():
		var stream := _listener.take_connection()
		if _peers.size() < 4:
			var socket := WebSocketPeer.new()
			socket.inbound_buffer_size = 16384
			socket.outbound_buffer_size = 262144
			socket.max_queued_packets = 16
			if socket.accept_stream(stream) == OK:
				_peers[_next_peer] = {"socket": socket, "slot": -1, "created": Time.get_ticks_msec(), "last_move": Time.get_ticks_msec(), "pending_move": false, "window": Time.get_ticks_msec(), "commands": 0}
				_next_peer += 1
	for id in _peers.keys():
		var peer: Dictionary = _peers[id]
		var socket: WebSocketPeer = peer["socket"]
		socket.poll()
		if socket.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			_peers.erase(id)
			continue
		if peer["slot"] < 0 and Time.get_ticks_msec() - peer["created"] > 5000:
			socket.close(1008, "Authentication timeout")
		if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
			continue
		for _packet in range(mini(4, socket.get_available_packet_count())):
			var bytes: PackedByteArray = socket.get_packet()
			if bytes.size() > MAX_FRAME or not socket.was_string_packet():
				socket.close(1009, "Invalid frame")
				break
			var value: Variant = JSON.parse_string(bytes.get_string_from_utf8())
			if typeof(value) != TYPE_DICTIONARY:
				socket.close(1008, "Invalid document")
				break
			_receive(id, value)
	_elapsed += delta
	if not _events.is_empty():
		var events: Array[Dictionary] = _events
		_events = []
		for event in events:
			if event.has("peer"):
				_send(event["peer"], event["frame"])
				continue
			for id in _peers:
				if _peers[id]["slot"] >= 0:
					_send(id, event)
	if _elapsed >= 0.1:
		_elapsed = 0.0
		for id in _peers:
			if _peers[id]["slot"] >= 0:
				_publish(id)


func _context(slot: int) -> AuthenticatedCommandContext:
	return AuthenticatedCommandContext.from_authenticated_session(&"local-inventory-actor" if slot == 0 else &"local-inventory-target", StringName("invite-slot-%d" % slot), _world.world_id, _world.region_id, PackedStringArray(["inventory.operate"]))


func _receive(id: int, value: Dictionary) -> void:
	var peer: Dictionary = _peers[id]
	if peer["slot"] < 0:
		if not ControlContractValidation.has_exact_fields(value, PackedStringArray(["type", "key"])) or value["type"] != "authenticate" or typeof(value["key"]) != TYPE_STRING:
			peer["socket"].close(1008, "Authentication required")
			return
		var slot: int = _keys.find(value["key"])
		for other in _peers.values():
			if other["slot"] == slot:
				slot = -1
				break
		if slot < 0:
			peer["socket"].close(1008, "Invalid or occupied invite")
			return
		peer["slot"] = slot
		_send(id, {"type": "authenticated", "slot": slot, "world_id": String(_world.world_id), "region_id": String(_world.region_id)})
		_publish(id)
		return
	if Time.get_ticks_msec() - peer["window"] >= 1000:
		peer["window"] = Time.get_ticks_msec()
		peer["commands"] = 0
	peer["commands"] += 1
	if peer["commands"] > 20 or not ControlContractValidation.has_exact_fields(value, PackedStringArray(["type", "request_id", "system", "operation", "payload"])) or value["type"] != "command" or not ControlContractValidation.is_id(value.get("request_id")) or String(value["request_id"]).length() > 90 or typeof(value.get("payload")) != TYPE_DICTIONARY:
		peer["socket"].close(1008, "Invalid or excessive command")
		return
	var command: SimulationCommand
	if value["system"] == "world" and value["operation"] == "checkpoint":
		if persistence == null or not value["payload"].is_empty() or not _checkpoint_request.is_empty():
			_ack(id, value["request_id"], ServiceResult.failure(&"checkpoint_unavailable", "A checkpoint is unavailable or already pending."))
			return
		var checkpoint: ServiceResult = persistence.request_checkpoint()
		if checkpoint.is_success:
			_checkpoint_request = {"peer": id, "request_id": value["request_id"]}
		else:
			_ack(id, value["request_id"], checkpoint)
		return
	if value["system"] == "production":
		var production_command := ProductionDevelopmentCommand.new()
		production_command.operation = value["operation"] if typeof(value["operation"]) == TYPE_STRING else ""
		production_command.payload = value["payload"]
		command = production_command
	elif value["system"] == "inventory" and value["operation"] in ["move_to", "world", "self"]:
		if value["operation"] == "move_to":
			var position: Variant = value["payload"].get("position_millimetres")
			var inventory := _world.get_simulation_system(InventorySimulationSystem.SYSTEM_ID) as InventorySimulationSystem
			var current: ServiceResult = inventory.own_position(_context(peer["slot"]))
			var elapsed: float = minf(0.5, float(Time.get_ticks_msec() - peer["last_move"]) / 1000.0)
			var inside_region: bool = InventorySpatialMath.is_position(position) and position[0] >= -14600 and position[0] <= 4600 and position[1] >= 0 and position[1] <= 3000 and position[2] >= -6600 and position[2] <= 2600
			if peer["pending_move"] or not inside_region or not current.is_success or InventorySpatialMath.distance_millimetres(current.value, position) > maxi(100, int(elapsed * 8000.0)):
				_ack(id, value["request_id"], ServiceResult.failure(&"movement_rejected", "Movement exceeds the server step budget."))
				return
			peer["pending_move"] = true
			peer["last_move"] = Time.get_ticks_msec()
		var inventory_command := InventoryDevelopmentCommand.new()
		inventory_command.operation = value["operation"]
		inventory_command.payload = value["payload"]
		command = inventory_command
	else:
		_ack(id, value["request_id"], ServiceResult.failure(&"system_denied", "This session cannot access that command system."))
		return
	command.command_id = StringName("net-%d-%s" % [peer["slot"], value["request_id"]])
	command.authenticated_context = _context(peer["slot"])
	if _pending.has(String(command.command_id)):
		_ack(id, value["request_id"], ServiceResult.failure(&"request_pending", "That request is already queued."))
		return
	var queued: ServiceResult = _world.enqueue_command(command)
	if queued.is_success:
		_pending[String(command.command_id)] = {"peer": id, "request_id": value["request_id"]}
	else:
		peer["pending_move"] = false
		_ack(id, value["request_id"], queued)


func _publish(id: int) -> void:
	var context: AuthenticatedCommandContext = _context(_peers[id]["slot"])
	var inventory := _world.get_simulation_system(InventorySimulationSystem.SYSTEM_ID) as InventorySimulationSystem
	var production: ServiceResult = _world.production_observation(context)
	var own: ServiceResult = inventory.own_inventory_observation(context, true)
	var position: ServiceResult = inventory.own_position(context)
	var world_items: ServiceResult = inventory.world_inventory_observation(context)
	if production.is_success and own.is_success and position.is_success:
		var players: Array = []
		for peer in _peers.values():
			if peer["slot"] >= 0:
				var peer_position: ServiceResult = inventory.own_position(_context(peer["slot"]))
				players.append({"slot": peer["slot"], "position": peer_position.value})
		_send(id, {"type": "observation", "tick_number": _world.current_tick_number(), "production": production.value, "inventory": own.value, "position": position.value, "players": players, "persistence": persistence.status() if persistence != null else {}, "world_items": world_items.value if world_items.is_success else {}})


func _send(id: int, value: Dictionary) -> void:
	if not _peers.has(id):
		return
	var socket: WebSocketPeer = _peers[id]["socket"]
	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		if socket.get_current_outbound_buffered_amount() > 131072:
			socket.close(1008, "Slow consumer")
		else:
			socket.send_text(JSON.stringify(value))


func _ack(id: int, request_id: String, result: ServiceResult) -> void:
	_send(id, {"type": "ack", "request_id": request_id, "ok": result.is_success, "message": result.message})


func _on_completed(command: SimulationCommand, result: ServiceResult) -> void:
	var id: String = String(command.command_id)
	if not _pending.has(id):
		return
	var pending: Dictionary = _pending[id]
	_pending.erase(id)
	if _peers.has(pending["peer"]):
		if command is InventoryDevelopmentCommand and command.operation == "move_to":
			_peers[pending["peer"]]["pending_move"] = false
		if _events.size() < 64:
			_events.append({"peer": pending["peer"], "frame": {"type": "ack", "request_id": pending["request_id"], "ok": result.is_success, "message": result.message}})


func _on_batch_completed(recipe_id: String, tick: int) -> void:
	if _events.size() < 64:
		_events.append({"type": "batch_completed", "recipe_id": recipe_id, "tick_number": tick})


func _on_checkpoint_completed(tick: int, result: ServiceResult) -> void:
	if not _checkpoint_request.is_empty():
		_ack(_checkpoint_request["peer"], _checkpoint_request["request_id"], ServiceResult.success({"tick_number": tick}) if result.is_success else result)
		_checkpoint_request = {}


func _exit_tree() -> void:
	_listener.stop()
	for peer in _peers.values():
		peer["socket"].close(-1)
