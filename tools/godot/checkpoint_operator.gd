extends SceneTree

## Native Windows/Linux local CLI. No listener, simulation or automatic fallback.
func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var world := WorldRuntime.new()
	world.resource_carriers_enabled = true
	root.add_child(world)
	world.set_process(false)
	var adapter := WorldPersistenceAdapter.new()
	root.add_child(adapter)
	adapter.set_process(false)
	var report: Dictionary = CheckpointOperator.run(OS.get_cmdline_user_args(), world, adapter)
	print(JSON.stringify(report))
	# On any failure the disposable world is discarded, even after partial domain restore.
	adapter.free()
	world.free()
	quit(int(report["exit_status"]))