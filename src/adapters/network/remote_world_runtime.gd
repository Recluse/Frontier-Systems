extends WorldRuntime
class_name RemoteWorldRuntime

signal observation_received(record: Dictionary)
signal connection_closed(message: String)
var _socket := WebSocketPeer.new()
var _projection := RemoteProductionProjection.new()
var _invite_key: String = ""
var _authenticated: bool = false
var _sent_auth: bool = false
var _requests: Dictionary = {}
var _observation: Dictionary = {}
var _remote_sequence: int = 0
var _nonce: String = ""
var server_slot: int = -1
var _connecting: bool = false
var _connect_started: int = 0
var _terrain_record: Dictionary = {}
var _terrain_intent: Dictionary = {}
## Optional client intent journal; contains no keys or authoritative world records.
var terrain_retry_directory: String = ""


func _ready() -> void:
	# Intentionally no SimulationRunner or local authoritative systems.
	_nonce = Crypto.new().generate_random_bytes(8).hex_encode()
	add_child(_projection)


func connect_host(url: String, invite_key: String) -> ServiceResult:
	if _sent_auth or invite_key.length() < 32 or invite_key.length() > 256 or not (url.begins_with("ws://127.0.0.1:") or url.begins_with("ws://localhost:") or url.begins_with("wss://")):
		return ServiceResult.failure(&"remote_configuration", "Use loopback WebSocket or TLS with an operator-provided invite key.")
	_invite_key = invite_key
	_socket.inbound_buffer_size = 262144
	_socket.outbound_buffer_size = 16384
	_socket.max_queued_packets = 16
	var error: Error = _socket.connect_to_url(url)
	_connecting = error == OK
	_connect_started = Time.get_ticks_msec()
	set_process(true)
	return ServiceResult.success() if error == OK else ServiceResult.failure(&"remote_connect", "Cannot connect to the host.")


func _process(_delta: float) -> void:
	_socket.poll()
	if _connecting and Time.get_ticks_msec() - _connect_started > 5000 and not _authenticated:
		_socket.close(-1)
	if _socket.get_ready_state() == WebSocketPeer.STATE_CLOSED and _connecting:
		_projection.record = {}
		_terrain_record = {}
		_observation = {}
		_authenticated = false
		_sent_auth = false
		_connecting = false
		for command in _requests.values():
			command_completed.emit(command, ServiceResult.failure(&"remote_disconnected", "Host connection closed; preserve the original terrain intent and retry after reconnecting."))
		_requests.clear()
		connection_closed.emit("Host connection closed")
		set_process(false)
		return
	if _socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	if not _sent_auth:
		_socket.send_text(JSON.stringify({"type": "authenticate", "key": _invite_key}))
		_invite_key = ""
		_sent_auth = true
	for _packet in range(mini(8, _socket.get_available_packet_count())):
		var bytes: PackedByteArray = _socket.get_packet()
		if bytes.size() > 262144 or not _socket.was_string_packet():
			_socket.close(1009, "Invalid observation")
			return
		var frame: Variant = JSON.parse_string(bytes.get_string_from_utf8())
		if typeof(frame) != TYPE_DICTIONARY:
			_socket.close(1008, "Invalid host document")
			return
		_receive(frame)


func _receive(frame: Dictionary) -> void:
	match frame.get("type"):
		"authenticated":
			if _authenticated or not ToolComponentCatalog.exact(frame, ["type", "world_id", "region_id", "slot"]) or not ControlContractValidation.is_id(frame.get("world_id")) or not ControlContractValidation.is_id(frame.get("region_id")) or not ControlContractValidation.is_integer(frame.get("slot"), 0, 1):
				_socket.close(1008, "Invalid authenticated scope")
				return
			world_id = StringName(frame["world_id"])
			region_id = StringName(frame["region_id"])
			_authenticated = true
			server_slot = int(frame["slot"])
			if _terrain_intent.is_empty() and not terrain_retry_directory.is_empty():
				var loaded: ServiceResult = LocalTerrainRetryStore.read_intent(_retry_path())
				if loaded.is_success: _terrain_intent = loaded.value
				elif loaded.error_code != &"terrain_retry_missing":
					_socket.close(1008, "Invalid local terrain retry journal")
		"observation":
			if not TerrainObservationValidation.valid(frame.get("terrain")):
				_socket.close(1008, "Invalid terrain observation")
				return
			if not ToolObservationValidation.valid(frame.get("tools")):
				_socket.close(1008, "Invalid tool observation")
				return
			if not _authenticated or typeof(frame.get("production")) != TYPE_DICTIONARY or typeof(frame.get("inventory")) != TYPE_DICTIONARY or not InventorySpatialMath.is_position(frame.get("position")):
				return
			frame["position"] = InventorySpatialMath.normalized(frame["position"])
			if typeof(frame.get("players")) != TYPE_ARRAY or frame["players"].size() > 2:
				return
			for player in frame["players"]:
				if typeof(player) != TYPE_DICTIONARY or not ControlContractValidation.is_integer(player.get("slot"), 0, 1) or not InventorySpatialMath.is_position(player.get("position")):
					return
				player["position"] = InventorySpatialMath.normalized(player["position"])
			if not _projection.accept_record(frame["production"]).is_success:
				_socket.close(1008, "Invalid production observation")
				return
			_terrain_record = TerrainObservationValidation.normalized(frame["terrain"])
			frame["terrain"] = _terrain_record.duplicate(true)
			_observation = frame.duplicate(true)
			observation_received.emit(_observation.duplicate(true))
		"ack":
			if _requests.has(frame.get("request_id")) and typeof(frame.get("ok")) == TYPE_BOOL and typeof(frame.get("code")) == TYPE_STRING and frame["code"].length() <= 128 and typeof(frame.get("message")) == TYPE_STRING and frame["message"].length() <= 512:
				var command: SimulationCommand = _requests[frame["request_id"]]
				_requests.erase(frame["request_id"])
				if command is TerrainCommand and frame["code"] != "request_pending":
					if terrain_retry_directory.is_empty() or LocalTerrainRetryStore.clear_intent(_retry_path()).is_success: _terrain_intent = {}
				command_completed.emit(command, ServiceResult.success() if frame["ok"] else ServiceResult.failure(StringName(frame["code"]), frame["message"]))
		"batch_completed":
			if typeof(frame.get("recipe_id")) == TYPE_STRING and ControlContractValidation.is_integer(frame.get("tick_number"), 0, 9007199254740000):
				_projection.batch_completed.emit(frame["recipe_id"], int(frame["tick_number"]))


func get_simulation_system(id: StringName) -> SimulationSystem:
	return _projection if id == ProductionSimulationSystem.SYSTEM_ID else null


func production_observation(_context: AuthenticatedCommandContext) -> ServiceResult:
	return _projection.observation(null)


func terrain_observation(_context: AuthenticatedCommandContext) -> ServiceResult:
	return ServiceResult.success(_terrain_record.duplicate(true)) if not _terrain_record.is_empty() else ServiceResult.failure(&"remote_not_ready", "Waiting for terrain observation.")


func terrain_pending_intent() -> Dictionary:
	return _terrain_intent.duplicate(true)


func restore_terrain_intent(record: Dictionary) -> ServiceResult:
	if not _terrain_intent.is_empty() or not LocalTerrainRetryStore.valid(record): return ServiceResult.failure(&"terrain_retry_invalid", "Restore one exact bounded client intent.")
	_terrain_intent = LocalTerrainRetryStore.normalized(record)
	return ServiceResult.success()


func retry_terrain_intent() -> ServiceResult:
	if _terrain_intent.is_empty(): return ServiceResult.failure(&"terrain_retry_missing", "There is no unresolved terrain intent.")
	var command := TerrainCommand.new()
	command.request_number = int(_terrain_intent["request_number"])
	command.command_id = StringName("terrain-client-%d" % command.request_number)
	command.operation = _terrain_intent["operation"]
	command.payload = _terrain_intent["payload"].duplicate(true)
	return enqueue_command(command)


func _retry_path() -> String:
	return terrain_retry_directory.path_join(JSON.stringify([String(world_id), String(region_id), server_slot]).sha256_text() + ".json")


func enqueue_command(command: SimulationCommand) -> ServiceResult:
	if not _authenticated or _socket.get_ready_state() != WebSocketPeer.STATE_OPEN or _requests.size() >= 8:
		return ServiceResult.failure(&"remote_not_ready", "Host is not ready or requests are pending.")
	var system: String = "terrain" if command is TerrainCommand else ("production" if command is ProductionDevelopmentCommand else ("inventory" if command is InventoryDevelopmentCommand else ("world" if command is CheckpointRequest else "")))
	if system.is_empty() or String(command.command_id).length() > 90 or _requests.has(String(command.command_id)):
		return ServiceResult.failure(&"remote_command_invalid", "Unsupported or duplicate client request.")
	var frame: Dictionary = {"type": "command", "request_id": String(command.command_id), "system": system, "operation": command.operation, "payload": command.payload}
	if command is TerrainCommand:
		if _terrain_record.is_empty() or not TerrainObservationValidation.valid_intent(command.request_number, command.operation, command.payload) or String(command.command_id) != "terrain-client-%d" % command.request_number:
			return ServiceResult.failure(&"terrain_intent_invalid", "Use an observed bounded terrain intent and its stable ordinal.")
		var intent: Dictionary = {"schema_version": 1, "world_id": String(world_id), "region_id": String(region_id), "slot": server_slot, "request_number": command.request_number, "operation": command.operation, "payload": command.payload.duplicate(true)}
		intent = LocalTerrainRetryStore.normalized(intent)
		if not _terrain_intent.is_empty() and _terrain_intent != intent:
			return ServiceResult.failure(&"terrain_retry_required", "Reconcile the original unresolved terrain intent before starting fresh work.")
		if _terrain_intent.is_empty() and (command.request_number != _terrain_record["next_request_number"] or _terrain_record["request_sequence_exhausted"]):
			return ServiceResult.failure(&"terrain_ordinal_invalid", "Use the observed next ordinal for fresh work only.")
		if not terrain_retry_directory.is_empty():
			var stored: ServiceResult = LocalTerrainRetryStore.write_intent(_retry_path(), intent)
			if not stored.is_success: return stored
		_terrain_intent = intent
		frame["request_number"] = command.request_number
		frame["payload"] = intent["payload"].duplicate(true)
		# Freeze the completion identity too: callers may reuse their mutable object.
		var frozen := TerrainCommand.new()
		frozen.command_id = command.command_id
		frozen.request_number = command.request_number
		frozen.operation = command.operation
		frozen.payload = intent["payload"].duplicate(true)
		command = frozen
	var sent: Error = _socket.send_text(JSON.stringify(frame))
	if sent != OK:
		return ServiceResult.failure(&"remote_send", "Host send buffer is unavailable.")
	_requests[String(command.command_id)] = command
	return ServiceResult.success()


func next_local_request_id() -> StringName:
	_remote_sequence += 1
	return StringName("%s-%d" % [_nonce, _remote_sequence])


func current_tick_number() -> int:
	return int(_observation.get("tick_number", 0))


func _exit_tree() -> void:
	_socket.close(-1)
