extends Node
class_name ProfileCaptureUploader

## Explicit host-side telemetry adapter. Never register as a simulation system.
## Only detached profiling bytes leave the world; receipts grant no game authority.
const MAX_PAYLOAD_BYTES: int = 8388608
const MAX_RESPONSE_BYTES: int = 4096

var _endpoint: String = ""
var _token: String = ""
var _maximum_bytes: int = 1048576
var _timeout_seconds: float = 15.0
var _request: HTTPRequest
var _pending: GamePromise
var _pending_tick: int = 0
var _generation: int = 0
var _completed: int = 0
var _failed: int = 0
var _cancelled: int = 0
var _rejected: int = 0


## Credentials come from host startup configuration, never clients, saves or LLMs.
## Redirects are disabled so authorization cannot follow a different destination.
func configure(endpoint: String, bearer_token: String, maximum_bytes: int = 1048576, timeout_seconds: float = 15.0, allow_local_http: bool = false) -> ServiceResult:
	if _pending != null:
		return ServiceResult.failure(&"profile_upload_busy", "Cancel or finish the upload before reconfiguring.")
	var https := RegEx.new()
	https.compile("^https://[A-Za-z0-9.\\-\\[\\]:]+/v1/profiling/captures\\z")
	var local := RegEx.new()
	local.compile("^http://(localhost|127\\.0\\.0\\.1|\\[::1\\])(:[0-9]{1,5})?/v1/profiling/captures\\z")
	var valid_url: bool = endpoint.length() <= 512 and https.search(endpoint) != null
	if allow_local_http and OS.is_debug_build() and endpoint.length() <= 512:
		valid_url = valid_url or local.search(endpoint) != null
	var token_format := RegEx.new()
	token_format.compile("^[A-Za-z0-9._~+/-]+={0,2}\\z")
	if not valid_url or bearer_token.length() > 4096 or token_format.search(bearer_token) == null:
		return ServiceResult.failure(&"invalid_profile_configuration", "A supported endpoint and opaque bearer credential are required.")
	if maximum_bytes < 1 or maximum_bytes > MAX_PAYLOAD_BYTES or not is_finite(timeout_seconds) or timeout_seconds <= 0.0 or timeout_seconds > 60.0:
		return ServiceResult.failure(&"invalid_profile_limits", "Upload size and timeout must be within supported bounds.")
	_endpoint = endpoint
	_token = bearer_token
	_maximum_bytes = maximum_bytes
	_timeout_seconds = timeout_seconds
	return ServiceResult.success()


## Invoke between ticks. Capture/report generation is bounded CPU work, not async.
## The HTTP operation and promise continuations do not suspend fixed simulation ticks.
func upload_world_capture(world: WorldRuntime, sample_limit: int = 120) -> GamePromise:
	var promise := GamePromise.new()
	if Engine.is_in_physics_frame():
		return _reject_submission(promise, &"profile_upload_during_physics", "Submit telemetry from idle processing rather than physics callbacks.")
	if not is_inside_tree() or _endpoint.is_empty() or _token.is_empty():
		return _reject_submission(promise, &"profile_upload_not_configured", "Attach and configure the host uploader before use.")
	if _pending != null:
		return _reject_submission(promise, &"profile_upload_busy", "One profiling upload is already active.")
	if not is_instance_valid(world) or sample_limit < 0 or sample_limit > TickProfileHistory.MAX_CAPACITY:
		return _reject_submission(promise, &"invalid_profile_capture_request", "A live world and bounded sample limit are required.")
	var captured: ServiceResult = world.capture_profiling(sample_limit)
	if not captured.is_success:
		_rejected += 1
		promise.reject(captured)
		return promise
	var capture: Dictionary = captured.value
	var json: String = JSON.stringify(capture, "", true, true)
	if json.to_utf8_buffer().size() > _maximum_bytes:
		return _reject_submission(promise, &"profile_capture_too_large", "Select a smaller capture window for this upload limit.")
	_generation += 1
	_pending = promise
	_pending_tick = int(capture["capture_tick_number"])
	_request = HTTPRequest.new()
	_request.timeout = _timeout_seconds
	_request.body_size_limit = MAX_RESPONSE_BYTES
	_request.max_redirects = 0
	_request.accept_gzip = false
	_request.use_threads = true
	_request.request_completed.connect(_on_completed.bind(_generation))
	add_child(_request)
	var headers := PackedStringArray(["Content-Type: application/json", "Accept: application/json", "Authorization: Bearer " + _token])
	var started: Error = _request.request(_endpoint, headers, HTTPClient.METHOD_POST, json)
	if started != OK:
		_finish(ServiceResult.failure(&"profile_upload_start_failed", "The HTTP upload could not start."))
	return promise


func cancel_upload() -> void:
	if _pending == null:
		return
	_cancelled += 1
	_generation += 1
	if is_instance_valid(_request):
		_request.cancel_request()
	_finish(ServiceResult.failure(&"profile_upload_cancelled", "The upload was cancelled; remote storage may already have committed."))


func diagnostics() -> Dictionary:
	return {"active_uploads": 1 if _pending != null else 0, "completed_uploads": _completed,
		"failed_uploads": _failed, "cancelled_uploads": _cancelled, "rejected_submissions": _rejected}


func _on_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, generation: int) -> void:
	if _pending == null or generation != _generation:
		return
	if result != HTTPRequest.RESULT_SUCCESS:
		_finish(ServiceResult.failure(&"profile_upload_transport_failed", "Upload transport failed or timed out; remote commit status is unknown."))
		return
	if response_code != 200:
		_finish(ServiceResult.failure(&"profile_upload_http_rejected", "Profiling endpoint returned HTTP %d." % response_code))
		return
	var value: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(value) != TYPE_DICTIONARY:
		_finish(ServiceResult.failure(&"invalid_profile_receipt", "The endpoint did not return a receipt record."))
		return
	var receipt: Dictionary = value
	var fields := PackedStringArray(["schema_version", "status", "sequence", "capture_tick_number", "fingerprint"])
	var valid: bool = ControlContractValidation.has_exact_fields(receipt, fields)
	valid = valid and ControlContractValidation.is_integer(receipt.get("schema_version"), 1, 1)
	valid = valid and receipt.get("status") == "stored"
	valid = valid and ControlContractValidation.is_integer(receipt.get("sequence"), 1, 9007199254740990)
	valid = valid and ControlContractValidation.is_integer(receipt.get("capture_tick_number"), _pending_tick, _pending_tick)
	var digest := RegEx.new()
	digest.compile("^[a-f0-9]{64}\\z")
	valid = valid and typeof(receipt.get("fingerprint")) == TYPE_STRING
	valid = valid and digest.search(String(receipt.get("fingerprint", ""))) != null
	if not valid:
		_finish(ServiceResult.failure(&"invalid_profile_receipt", "The receipt does not match the requested capture frontier."))
		return
	_finish(ServiceResult.success(receipt.duplicate(true)))


func _finish(result: ServiceResult) -> void:
	var promise: GamePromise = _pending
	_pending = null
	_pending_tick = 0
	if is_instance_valid(_request):
		_request.queue_free()
	_request = null
	if promise == null:
		return
	if result.is_success:
		_completed += 1
		promise.resolve(result)
	else:
		_failed += 1
		promise.reject(result)


func _reject_submission(promise: GamePromise, code: StringName, message: String) -> GamePromise:
	_rejected += 1
	promise.reject(ServiceResult.failure(code, message))
	return promise


func _exit_tree() -> void:
	cancel_upload()
	_token = ""
	_endpoint = ""
