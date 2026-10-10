extends SceneTree

var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var world := WorldRuntime.new()
	root.add_child(world)
	_check(world.start_simulation().is_success, "health-integrated world must start")
	var runner: SimulationRunner = world.get_node("SimulationRunner")
	runner.set_physics_process(false)
	var health: HealthSimulationSystem = world.get_simulation_system(HealthSimulationSystem.SYSTEM_ID)
	var causes: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/health/suppression.combined.v1.json"))
	_check(health.queue_observation("body.human-1", causes, 0, 1).is_success, "trusted next-tick observation must queue")
	_check(health.body_observation("body.human-1").value["state"]["state"] == "alert", "queue must not immediately alter consciousness")
	_check(not world.capture_world_snapshot().is_success, "pending health inputs must prevent an incomplete checkpoint")
	_check(not health.queue_observation("body.human-1", [], 0, 1).is_success, "duplicate pending body observation must reject")
	runner._physics_process(1.0 / 60.0)
	_check(health.body_observation("body.human-1").value["state"]["state"] == "unconscious", "fixed tick must apply knockout")
	_check(health.body_observation("body.human-2").value["state"]["state_revision"] == 0, "healthy bodies must use staggered phase")
	_check(not health.queue_observation("body.human-1", [], 0, 2).is_success, "stale source revision must reject")
	_check(not health.queue_observation("body.human-1", [], 1, 1).is_success, "stale observation tick must reject")
	_check(health.queue_observation("body.human-1", [], 1, 2).is_success, "clearing a trusted source must queue")
	runner._physics_process(1.0 / 60.0)
	_check(health.body_observation("body.human-1").value["state"]["recovery_since_tick"] == 2, "safe source starts recovery on its accepting tick")
	var saved: ServiceResult = world.capture_world_snapshot_json()
	_check(saved.is_success, "integrated health must checkpoint")
	var restored := WorldRuntime.new()
	root.add_child(restored)
	_check(restored.restore_world_snapshot_json(saved.value).is_success and restored.start_simulation().is_success, "world JSON must restore health owners and schedule")
	var restored_runner: SimulationRunner = restored.get_node("SimulationRunner")
	restored_runner.set_physics_process(false)
	var restored_health: HealthSimulationSystem = restored.get_simulation_system(HealthSimulationSystem.SYSTEM_ID)
	_check(restored_health.body_observation("body.human-1").value == health.body_observation("body.human-1").value, "saved body observation must recover exactly")
	for index in range(60):
		runner._physics_process(1.0 / 60.0)
		restored_runner._physics_process(1.0 / 60.0)
	_check(restored_health.body_observation("body.human-1").value["state"]["state"] == "alert", "scheduled safe interval must recover consciousness")
	var restored_records: Dictionary = restored.capture_world_snapshot().value.to_dictionary()["systems"]
	var original_records: Dictionary = world.capture_world_snapshot().value.to_dictionary()["systems"]
	_check(restored_records["health"] == original_records["health"], "restored health scheduler must continue identically")
	var malformed: Dictionary = world.capture_world_snapshot().value.to_dictionary()
	malformed["systems"]["health"]["entries"][0]["next_assessment_tick"] = 99999
	var bad := WorldRuntime.new()
	root.add_child(bad)
	_check(not bad.restore_world_snapshot(WorldSnapshot.from_dictionary(malformed).value).is_success, "future due schedule must reject")
	malformed = world.capture_world_snapshot().value.to_dictionary()
	malformed["systems"]["health"]["entries"][0]["owner"]["state"]["body_id"] = "body.unregistered"
	_check(not bad.restore_world_snapshot(WorldSnapshot.from_dictionary(malformed).value).is_success, "orphaned health body must reject")
	malformed = world.capture_world_snapshot().value.to_dictionary()
	malformed["systems"].erase("health")
	_check(bad.restore_world_snapshot(WorldSnapshot.from_dictionary(malformed).value).is_success, "legacy worlds without health must initialize known bodies")
	_check(bad.get_simulation_system(HealthSimulationSystem.SYSTEM_ID).body_observation("body.human-1").value["state"]["state_revision"] == 0, "legacy migration must not invent prior assessments")
	var standalone := HealthSimulationSystem.new()
	root.add_child(standalone)
	var ids: Array = []
	for index in range(64):
		ids.append("benchmark.body-%d" % index)
	_check(standalone.configure_bodies(ids).is_success, "maximum bounded population must configure")
	_check(not standalone.configure_bodies([]).is_success, "body registry must not be silently reconfigured")
	for tick in range(1, 13):
		standalone.simulate_tick(tick, 1.0 / 60.0)
		_check(standalone.profiling_counters()["assessments_last_tick"] <= 12 and standalone.profiling_counters()["assessment_failures"] == 0, "scheduler work must remain bounded")
	_check(standalone.profiling_counters()["overdue_bodies"] == 0, "phased population should not build backlog")
	for id in ids:
		_check(standalone.queue_observation(id, causes, 0, 13).is_success, "urgent maximum-population observations must queue")
	standalone.simulate_tick(13, 1.0 / 60.0)
	_check(standalone.profiling_counters()["assessments_last_tick"] == 12 and standalone.profiling_counters()["overdue_bodies"] == 52, "urgent burst must defer excess work within bound")
	for tick in range(14, 19):
		standalone.simulate_tick(tick, 1.0 / 60.0)
	_check(standalone.profiling_counters()["overdue_bodies"] == 0, "deferred population must drain without starvation")
	var record: Dictionary = standalone.capture_snapshot().value
	Engine.physics_ticks_per_second = 72
	_check(not standalone.validate_snapshot_record(record, 18).is_success and not standalone.capture_snapshot().is_success, "timebase changes require migration")
	Engine.physics_ticks_per_second = 60
	standalone.free()
	bad.free()
	restored.free()
	world.free()
	if _failures == 0:
		print("Health fixed ticks, phased scheduling, world recovery and legacy migration scenarios passed.")
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
