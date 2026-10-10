extends SceneTree

## Opt-in real desktop rendering run. Opens the prototype and exits after 20 seconds.
var _start: int = 0
var _last_frame: int = 0
var _frames: Array = []
var _cpu: Array = []
var _gpu: Array = []
var _physics: Array = []
var _viewports: Array[Viewport] = []
var _scene: Node
var _rate: int = 60


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
	Engine.physics_ticks_per_second = _rate
	if DisplayServer.get_name() == "headless":
		push_error("Client benchmark requires real rendering.")
		quit(1)
		return
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(_scene)
	var runner: SimulationRunner = _scene.get_node("WorldRuntime/SimulationRunner")
	runner.tick_budget_usec = options.value["tick_budget_usec"]
	await process_frame
	_collect_viewports(root)
	_start = Time.get_ticks_usec()
	_last_frame = _start
	process_frame.connect(_sample)


func _collect_viewports(node: Node) -> void:
	if node is Viewport:
		_viewports.append(node)
		RenderingServer.viewport_set_measure_render_time(node.get_viewport_rid(), true)
	for child in node.get_children():
		_collect_viewports(child)


func _sample() -> void:
	var now: int = Time.get_ticks_usec()
	var frame_usec: int = now - _last_frame
	_last_frame = now
	if now - _start < 5000000:
		return
	var cpu_ms: float = RenderingServer.get_frame_setup_time_cpu()
	var gpu_ms: float = 0.0
	for viewport in _viewports:
		cpu_ms += RenderingServer.viewport_get_measured_render_time_cpu(viewport.get_viewport_rid())
		gpu_ms += RenderingServer.viewport_get_measured_render_time_gpu(viewport.get_viewport_rid())
	_frames.append(frame_usec)
	_cpu.append(roundi(cpu_ms * 1000.0))
	_gpu.append(roundi(gpu_ms * 1000.0))
	_physics.append(roundi(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000000.0))
	if now - _start >= 20000000:
		process_frame.disconnect(_sample)
		var viewport_sizes: Array = []
		for viewport in _viewports:
			viewport_sizes.append({"path": String(viewport.get_path()), "size": str(viewport.get_visible_rect().size)})
		var report := {"schema_version": 1, "utc": Time.get_datetime_string_from_system(true), "engine": Engine.get_version_info(),
			"adapter": RenderingServer.get_video_adapter_name(), "rendering_method": RenderingServer.get_current_rendering_method(),
			"driver": RenderingServer.get_current_rendering_driver_name(), "viewports": viewport_sizes, "warmup_seconds": 5,
			"physics_ticks_per_second": _rate, "tick_budget_usec": ceili(1000000.0 / float(_rate)),
			"measured_seconds": float(now - _start - 5000000) / 1000000.0, "vsync": DisplayServer.window_get_vsync_mode(),
			"frame_interval_usec": TickProfileReport._statistics(_frames), "render_cpu_usec": TickProfileReport._statistics(_cpu),
			"render_gpu_usec": TickProfileReport._statistics(_gpu), "physics_monitor_usec": TickProfileReport._statistics(_physics),
			"objects": Performance.get_monitor(Performance.OBJECT_COUNT), "nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
			"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), "primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
			"memory_static_bytes": Performance.get_monitor(Performance.MEMORY_STATIC), "video_memory_bytes": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),
			"scope": "Stationary default desktop client, real GPU rendering, debug executable, no combat/VR/populated world. CPU/GPU viewport timings are summed; physics monitor is a periodically updated gauge, not a per-tick trace."}
		var path: String = "res://reports/performance/client-%s-%dhz.json" % [report["rendering_method"], _rate]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://reports/performance"))
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			push_error("Cannot write client benchmark report.")
			quit(1)
			return
		file.store_string(JSON.stringify(report, "\t") + "\n")
		file.close()
		print("Client benchmark saved: " + path)
		_scene.free()
		quit(0)
