extends Node
class_name WorldEventOutbox

## Opt-in host telemetry. Enqueue from signals; HTTP only runs in idle processing.
const MAX_EVENTS: int = 256
const MAX_BYTES: int = 524288
var _world: WorldRuntime
var _url: String = ""
var _token: String = ""
var _nonce: String = ""
var _sequence: int = 0
var _queue: Array[Dictionary] = []
var _bytes: int = 0
var _request := HTTPRequest.new()
var _busy: bool = false
var _next_attempt_ms: int = 0
var _delivered: int = 0
var _dropped: int = 0


func configure(world: WorldRuntime, url: String, token: String) -> ServiceResult:
	if _world != null or world == null: return ServiceResult.failure(&"event_setup", "Bind one world to its telemetry outbox.")
	if not url.is_empty() and (not (url.begins_with("http://127.0.0.1:") or url.begins_with("https://")) or not url.ends_with("/v1/events") or token.length() < 32 or token.length() > 4096 or token.contains("\n") or token.contains("\r")): return ServiceResult.failure(&"event_setup", "Use a host-scoped token and loopback HTTP or HTTPS event endpoint.")
	_world = world
	_url = url
	_token = token
	_nonce = Crypto.new().generate_random_bytes(12).hex_encode()
	_request.timeout = 5.0
	_request.body_size_limit = 4096
	_request.max_redirects = 0
	add_child(_request)
	_request.request_completed.connect(_completed)
	world.command_completed.connect(_command_completed)
	var production := world.get_simulation_system(ProductionSimulationSystem.SYSTEM_ID) as ProductionSimulationSystem
	production.batch_completed.connect(func(recipe: String, _tick: int) -> void: publish("production.batch", "public", "", {"recipe_id": recipe}))
	production.extraction_cycle_completed.connect(func(id: String, cycles: int, _tick: int) -> void: publish("production.extraction", "staff", "", {"request_id": id, "completed_cycles": cycles}))
	return ServiceResult.success()


## Any subsystem may publish a registered event. The receiver enforces its classification.
## Never supply authentication headers, credentials, or raw arbitrary command payloads.
func publish(kind: String, audience: String, scope_id: String, data: Dictionary) -> ServiceResult:
	if _url.is_empty(): return ServiceResult.success(false)
	if not ControlContractValidation.is_id(kind) or audience not in ["public", "staff", "private"] or scope_id.length() > 128 or ((audience == "private") != (not scope_id.is_empty())): return ServiceResult.failure(&"event_invalid", "Invalid event classification.")
	if data.size() > 8: return ServiceResult.failure(&"event_invalid", "Too many event fields.")
	for field in data:
		if typeof(field) != TYPE_STRING or not ControlContractValidation.is_id(field): return ServiceResult.failure(&"event_invalid", "Invalid event field.")
		for credential in ["token", "password", "secret", "credential", "authorization"]:
			if field.to_lower().contains(credential): return ServiceResult.failure(&"event_invalid", "Credential fields cannot be logged.")
		var value: Variant = data[field]
		if typeof(value) not in [TYPE_STRING, TYPE_BOOL, TYPE_INT] or (typeof(value) == TYPE_STRING and value.to_utf8_buffer().size() > 8192): return ServiceResult.failure(&"event_invalid", "Event values must be bounded scalars.")
	_sequence += 1
	var record: Dictionary = {"schema_version": 1, "event_id": "event-%s-%d" % [_nonce, _sequence], "world_id": String(_world.world_id), "region_id": String(_world.region_id), "tick_number": _world.current_tick_number(), "kind": kind, "audience": audience, "scope_id": scope_id, "data": data.duplicate(true)}
	var json: String = JSON.stringify(record)
	var size: int = json.to_utf8_buffer().size()
	if size > 16384 or _queue.size() >= MAX_EVENTS or _bytes + size > MAX_BYTES:
		_dropped += 1
		return ServiceResult.failure(&"event_capacity", "Telemetry queue is full or the event exceeds its bound.")
	_queue.append({"json": json, "bytes": size, "attempts": 0, "event_id": record["event_id"]})
	_bytes += size
	return ServiceResult.success(record["event_id"])


## Promise settlement acknowledges receiver ingestion, never downstream Discord delivery.
## PromiseDispatcher runs continuations outside physics callbacks.
func publish_async(kind: String, audience: String, scope_id: String, data: Dictionary) -> GamePromise:
	var promise := GamePromise.new()
	var queued: ServiceResult = publish(kind, audience, scope_id, data)
	if not queued.is_success: promise.reject(queued)
	elif typeof(queued.value) == TYPE_BOOL and queued.value == false: promise.resolve(queued) # Explicitly disabled telemetry.
	else: _queue.back()["promise"] = promise
	return promise


func _command_completed(command: SimulationCommand, result: ServiceResult) -> void:
	var operation: String = "command"
	if command is ProductionDevelopmentCommand or command is InventoryDevelopmentCommand: operation = command.operation
	if operation == "move_to": return # Continuous poses belong in profiling, not discrete audit delivery.
	publish("simulation.command", "staff", "", {"operation": operation, "success": result.is_success, "request_id": String(command.command_id), "code": String(result.error_code)})


func _process(_delta: float) -> void:
	if _url.is_empty() or _busy or _queue.is_empty() or Time.get_ticks_msec() < _next_attempt_ms: return
	_busy = true
	_queue[0]["attempts"] += 1
	var result: Error = _request.request(_url, PackedStringArray(["Content-Type: application/json", "Authorization: Bearer " + _token]), HTTPClient.METHOD_POST, _queue[0]["json"])
	if result != OK: _completed(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray())


func _completed(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	_busy = false
	if _queue.is_empty(): return
	if result == HTTPRequest.RESULT_SUCCESS and code == 202:
		_delivered += 1
		if _queue[0].has("promise"): _queue[0]["promise"].resolve(ServiceResult.success({"event_id": _queue[0]["event_id"], "accepted": true}))
		_discard_front()
	elif _queue[0]["attempts"] >= 3 or (code >= 400 and code < 500 and code != 429):
		_dropped += 1
		if _queue[0].has("promise"): _queue[0]["promise"].reject(ServiceResult.failure(&"event_delivery_failed", "Event receiver rejected or exhausted this submission."))
		_discard_front()
	else:
		_next_attempt_ms = Time.get_ticks_msec() + int(_queue[0]["attempts"]) * 1000


func _discard_front() -> void:
	_bytes -= int(_queue[0]["bytes"])
	_queue.pop_front()


func counters() -> Dictionary:
	return {"enabled": not _url.is_empty(), "queued": _queue.size(), "queued_bytes": _bytes, "in_flight": _busy, "accepted": _delivered, "dropped": _dropped}


func _exit_tree() -> void:
	_request.cancel_request()
	if _request.get_parent() == null: _request.free()
	for entry in _queue:
		if entry.has("promise"): entry["promise"].reject(ServiceResult.failure(&"event_shutdown", "Telemetry outbox stopped."))
	_queue.clear()
	_bytes = 0
