extends SceneTree

## Opt-in synthetic benchmark; isolated fixtures, no live persistence or services.
const REPEATS: int = 5
var _failed: bool = false
var _rate: int = 60
var _budget_usec: int = 16667


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var options: ServiceResult = BenchmarkRateOptions.parse(OS.get_cmdline_user_args())
	if not options.is_success:
		push_error(options.message)
		quit(1)
		return
	if options.value["configuration_only"]:
		print(JSON.stringify(options.value))
		quit(0)
		return
	_rate = options.value["physics_hz"]
	_budget_usec = options.value["tick_budget_usec"]
	Engine.physics_ticks_per_second = _rate
	var rows: Array = []
	for repeat in range(REPEATS):
		rows.append(_world_case("idle", false, 0, 2000, repeat))
		rows.append(_world_case("idle_history", true, 0, 2000, repeat))
		rows.append(_world_case("commands_64", true, 64, 200, repeat))
		rows.append(_world_case("commands_256", true, 256, 200, repeat))
		rows.append(_snapshot_case(repeat))
		rows.append(_consciousness_case(false, repeat))
		rows.append(_consciousness_case(true, repeat))
		rows.append(_motion_case(repeat))
		print("Runtime benchmark repeat %d/%d complete" % [repeat + 1, REPEATS])
	var report := {"schema_version": 1, "utc": Time.get_datetime_string_from_system(true),
		"engine": Engine.get_version_info(), "os": OS.get_name(), "cpu": OS.get_processor_name(),
		"physics_ticks_per_second": Engine.physics_ticks_per_second, "build": "debug" if OS.is_debug_build() else "release",
		"memory_static_bytes_end": Performance.get_monitor(Performance.MEMORY_STATIC), "rows": rows,
		"scope": "Headless synthetic CPU microbenchmarks. Manual ticks run faster than real time. No GPU, networking, external services or population capacity claim."}
	_write(report, "res://reports/performance/runtime-%dhz.json" % _rate)
	quit(1 if _failed else 0)


func _world_case(label: String, history: bool, commands: int, count: int, repeat: int) -> Dictionary:
	var world := WorldRuntime.new()
	root.add_child(world)
	_require(world.start_simulation())
	var runner: SimulationRunner = world.get_node("SimulationRunner")
	runner.set_physics_process(false)
	runner.tick_budget_usec = _budget_usec
	_require(world.configure_profile_history(history, 2048))
	var samples: Array = []
	var setup: Array = []
	var over_budget: int = 0
	for index in range(count + 100):
		var started: int = Time.get_ticks_usec()
		for command_index in range(commands):
			var command := AirlockCommand.new()
			command.command_id = StringName("benchmark-%d-%d" % [index, command_index])
			command.source = &"benchmark-development"
			command.airlock_id = WorldRuntime.PROTOTYPE_AIRLOCK_ID
			command.action = AirlockState.Action.CLOSE_VENT
			command.authenticated_context = AuthenticatedCommandContext.for_local_development(&"benchmark", world.world_id, world.region_id)
			_require(world.enqueue_command(command))
		var setup_usec: int = Time.get_ticks_usec() - started
		started = Time.get_ticks_usec()
		runner._physics_process(1.0 / float(_rate))
		var elapsed: int = Time.get_ticks_usec() - started
		if index >= 100:
			samples.append(elapsed)
			setup.append(setup_usec)
			if elapsed > _budget_usec:
				over_budget += 1
	var diagnostics: Dictionary = world.profiling_snapshot()
	if int(diagnostics["rejected_external_commands"]) != 0 or int(diagnostics["dropped_external_commands"]) != 0 or int(diagnostics["queued_external_commands"]) != 0:
		_failed = true
	var system_report: Dictionary = world.capture_profiling(2048).value["report"] if history else {}
	world.free()
	return {"scenario": label, "repeat": repeat, "unit": "one tick including history observer", "timing_usec": _stats(samples),
		"command_setup_usec": _stats(setup), "commands_per_tick": commands, "tick_budget_usec": _budget_usec, "over_budget_samples": over_budget,
		"runner_diagnostics": diagnostics, "internal_report": system_report}


func _snapshot_case(repeat: int) -> Dictionary:
	var world := WorldRuntime.new()
	root.add_child(world)
	_require(world.start_simulation())
	var runner: SimulationRunner = world.get_node("SimulationRunner")
	runner.set_physics_process(false)
	runner.tick_budget_usec = _budget_usec
	runner._physics_process(1.0 / float(_rate))
	var samples: Array = []
	var bytes: int = 0
	for index in range(220):
		var start: int = Time.get_ticks_usec()
		var result: ServiceResult = world.capture_world_snapshot_json()
		var elapsed: int = Time.get_ticks_usec() - start
		_require(result)
		if result.is_success:
			bytes = result.value.to_utf8_buffer().size()
		if index >= 20:
			samples.append(elapsed)
	world.free()
	return {"scenario": "world_snapshot_json", "repeat": repeat, "unit": "one validated snapshot capture and serialization", "timing_usec": _stats(samples), "snapshot_bytes": bytes}


func _consciousness_case(owned: bool, repeat: int) -> Dictionary:
	var owners: Array = []
	var states: Array = []
	for index in range(64):
		owners.append(ConsciousnessOwner.create("benchmark.body-%d" % index).value)
		states.append(ConsciousnessState.create_alert("benchmark.body-%d" % index).value)
	var causes: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/health/suppression.combined.v1.json"))
	var samples: Array = []
	for iteration in range(120):
		var current_causes: Array = causes if iteration % 30 < 15 else []
		var started: int = Time.get_ticks_usec()
		for index in range(64):
			var result: ServiceResult
			if owned:
				result = owners[index].assess({"schema_version": 1, "request_id": "assessment-%d" % iteration,
					"body_id": "benchmark.body-%d" % index, "expected_state_revision": iteration,
					"observed_tick": (iteration + 1) * 6, "causes": current_causes}, (iteration + 1) * 6)
			else:
				result = ConsciousnessPolicy.plan(states[index], current_causes, (iteration + 1) * 6)
			_require(result)
		var elapsed: int = Time.get_ticks_usec() - started
		if iteration >= 70:
			samples.append(elapsed)
	return {"scenario": "consciousness_64_owners" if owned else "consciousness_64_pure_plans", "repeat": repeat,
		"unit": "batch of 64 assessments; owner history saturated after warmup; pure plans use uncommitted alert inputs", "timing_usec": _stats(samples)}


func _motion_case(repeat: int) -> Dictionary:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/locomotion/push-off.default.v1.json"))
	var owner: LinearMotionOwner = LinearMotionOwner.create("benchmark.motion", [fixture["actor"], fixture["target"]]).value
	var samples: Array = []
	for index in range(340):
		var request := {"schema_version": 1, "request_id": "motion-%d" % index, "actor_body_id": "body.human-1",
			"target_body_id": "assembly.salvage-crate", "expected_owner_revision": index,
			"expected_actor_revision": index, "expected_target_revision": index, "impulse_micro_ns": [1, 0, 0]}
		var started: int = Time.get_ticks_usec()
		_require(owner.push_off(request, fixture["contact"], index + 1, index + 1))
		var elapsed: int = Time.get_ticks_usec() - started
		if index >= 140:
			samples.append(elapsed)
	return {"scenario": "linear_motion_saturated_owner", "repeat": repeat, "unit": "one paired impulse commit with 128 retained receipts", "timing_usec": _stats(samples)}


func _require(result: ServiceResult) -> void:
	if not result.is_success:
		_failed = true
		push_error("Benchmark operation failed: " + result.message)


static func _stats(values: Array) -> Dictionary:
	return TickProfileReport._statistics(values)


static func _write(report: Dictionary, path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://reports/performance"))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot save benchmark report.")
		return
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	print("Benchmark saved: " + path)
