extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var world := WorldRuntime.new()
	root.add_child(world)
	if not world.start_simulation().is_success:
		quit(1)
		return
	var runner: SimulationRunner = world.get_node("SimulationRunner")
	runner.set_physics_process(false)
	var before: String = world.capture_world_snapshot_json().value
	var outbox: WorldEventOutbox = world.event_outbox
	var settled: Dictionary = {"ok": false}
	var pending: GamePromise = outbox.publish_async("game.event","public","",{"text":"event-integration-public"})
	pending.then(func(result: ServiceResult) -> void: settled["ok"] = result.is_success)
	var good: bool = not settled["ok"]
	good = good and outbox.publish("llm.response","staff","",{"text":"event-integration-staff","agent":"station-ai"}).is_success
	good = good and not outbox.publish("game.event","public","",{"token":"never-log-this"}).is_success
	var deadline: int = Time.get_ticks_msec() + 8000
	while (outbox.counters()["accepted"] < 2 or not settled["ok"]) and Time.get_ticks_msec() < deadline:
		await process_frame
	good = good and settled["ok"] and outbox.counters()["accepted"] == 2 and outbox.counters()["queued"] == 0 and before == world.capture_world_snapshot_json().value
	world.free()
	if good: print("Game event HTTP integration: public/staff events accepted asynchronously, credential fields rejected and canonical snapshot unchanged.")
	else: push_error("Game event integration failed; receiver/configuration or canonical isolation check failed.")
	quit(0 if good else 1)
