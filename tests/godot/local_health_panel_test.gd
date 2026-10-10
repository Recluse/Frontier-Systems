extends SceneTree

var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var world := WorldRuntime.new()
	root.add_child(world)
	_check(world.start_simulation().is_success, "world starts")
	var runner := world.get_node("SimulationRunner") as SimulationRunner
	runner.set_physics_process(false)
	var actor := AuthenticatedCommandContext.for_local_development(&"local-inventory-actor", world.world_id, world.region_id)
	var observed: ServiceResult = world.own_health_observation(actor)
	_check(observed.is_success and observed.value["body_id"] == "body.human-2", "identity selects own body")
	_check(not observed.value.has("causes") and not observed.value.has("source_revision"), "projection omits internal source data")
	observed.value["parts"]["head"]["blunt"] = 999
	_check(world.own_health_observation(actor).value["parts"]["head"]["blunt"] == 0, "observations cannot mutate canonical injuries")
	_check(not world.own_health_observation(null).is_success, "null context fails closed")
	var wrong_scope := AuthenticatedCommandContext.for_local_development(&"local-inventory-actor", &"other-world", world.region_id)
	_check(not world.own_health_observation(wrong_scope).is_success, "foreign world denied")
	wrong_scope = AuthenticatedCommandContext.for_local_development(&"local-inventory-actor", world.world_id, &"other-region")
	_check(not world.own_health_observation(wrong_scope).is_success, "foreign region denied")
	var stranger := AuthenticatedCommandContext.for_local_development(&"unknown", world.world_id, world.region_id)
	_check(not world.own_health_observation(stranger).is_success, "unbound principal denied")
	actor.permissions.clear()
	_check(not world.own_health_observation(actor).is_success, "missing grant denied")
	actor = AuthenticatedCommandContext.for_local_development(&"local-inventory-actor", world.world_id, world.region_id)
	var panel := LocalHealthPanel.new()
	root.add_child(panel)
	_check(panel.configure(world).is_success and not panel.configure(world).is_success, "panel configures once")
	var health := world.get_simulation_system(HealthSimulationSystem.SYSTEM_ID) as HealthSimulationSystem
	_check(health.queue_injury_change("body.human-2", 0, 1, "damage", "head", "blunt", 800).is_success, "trusted injury queues")
	_check(world.own_health_observation(actor).value["parts"]["head"]["blunt"] == 0, "queued injury remains invisible before commit")
	runner._physics_process(1.0 / 60.0)
	panel.refresh()
	observed = world.own_health_observation(actor)
	_check(observed.is_success and observed.value["consciousness"] == "unconscious" and not observed.value["voluntary_actions_available"], "own observation remains readable while unconscious")
	_check(_text(panel).contains("Unconscious") and _text(panel).contains("blunt 800/1000"), "panel displays committed injury and consciousness")
	var other := AuthenticatedCommandContext.for_local_development(&"local-inventory-target", world.world_id, world.region_id)
	_check(world.own_health_observation(other).value["parts"]["head"]["blunt"] == 0, "second binding receives only its own health")
	var before: String = world.capture_world_snapshot_json().value
	panel.refresh()
	_check(world.capture_world_snapshot_json().value == before, "refresh leaves persistence unchanged")
	world.free()
	_check(_text(panel).contains("world closed") and not _text(panel).contains("800/1000"), "world closure clears cached injury text")
	panel.free()
	if _failures == 0:
		print("Local health scope, detached observations, unconscious display and cleanup passed.")
	quit(0 if _failures == 0 else 1)


func _text(panel: LocalHealthPanel) -> String:
	var lines: PackedStringArray = []
	for child in panel.get_children():
		if child is Label:
			lines.append(child.text)
	return "\n".join(lines)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
