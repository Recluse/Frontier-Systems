extends SceneTree

## Explicit integration smoke test against tools/run-profiling-receiver.php.
var _world: WorldRuntime
var _uploader: ProfileCaptureUploader
var _config: Dictionary
var _finished: bool = false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var config_path: String = "res://config/development/profiling.json"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--profiling-config="):
			config_path = argument.trim_prefix("--profiling-config=")
	var file := FileAccess.open(config_path, FileAccess.READ)
	if file == null or file.get_length() > 16384:
		_fail("Local development configuration is missing or oversized.")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY or parsed.get("development_only") != true:
		_fail("Local development configuration is invalid.")
		return
	_config = parsed
	_world = WorldRuntime.new()
	_world.world_id = StringName(_config["host"]["world_id"])
	_world.region_id = StringName(_config["host"]["region_id"])
	root.add_child(_world)
	var configured: ServiceResult = _world.configure_profile_history(true, int(_config["uploader"]["history_capacity"]))
	var started: ServiceResult = _world.start_simulation()
	if not configured.is_success or not started.is_success:
		_fail("World setup failed.")
		return
	_uploader = ProfileCaptureUploader.new()
	root.add_child(_uploader)
	configured = _uploader.configure(_config["uploader"]["endpoint"], _config["authentication"]["bearer_token"],
		int(_config["receiver"]["maximum_bytes"]), float(_config["uploader"]["timeout_seconds"]), true)
	if not configured.is_success:
		_fail("Uploader configuration failed.")
		return
	create_timer(0.3).timeout.connect(_upload)
	create_timer(20.0).timeout.connect(func() -> void: _fail("Local upload test deadline elapsed."))


func _upload() -> void:
	var upload: GamePromise = _uploader.upload_world_capture(_world, int(_config["uploader"]["sample_limit"]))
	var concurrent: GamePromise = _uploader.upload_world_capture(_world, int(_config["uploader"]["sample_limit"]))
	if concurrent.state != GamePromise.State.REJECTED or not concurrent.value is ServiceResult or concurrent.value.error_code != &"profile_upload_busy":
		_fail("Concurrent submission must reject instead of queueing another upload.")
		return
	upload.then(
		func(result: ServiceResult) -> void:
			if not result.is_success or _world.profiling_history(120)["samples"].is_empty():
				_fail("A receipt and sampled ticks are required.")
				return
			_finished = true
			print("PASS: local profiling upload received a validated stored receipt.")
			_cleanup()
			quit(0),
		func(reason: Variant) -> void:
			_fail(reason.message if reason is ServiceResult else "Local upload rejected.")
	)


func _fail(message: String) -> void:
	if _finished:
		return
	_finished = true
	push_error(message)
	_cleanup()
	quit(1)


func _cleanup() -> void:
	if is_instance_valid(_uploader):
		_uploader.free()
	if is_instance_valid(_world):
		_world.stop_simulation()
		_world.free()
