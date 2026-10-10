extends SceneTree

var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var state: BodyInjuryState = BodyInjuryState.create("body.human-1").value
	var before: Dictionary = state.to_record()
	var planned: ServiceResult = state.plan_change("damage", "arm.left", "burn", 400, 1)
	_check(planned.is_success and state.to_record() == before and planned.value["after"]["parts"]["arm.left"]["burn"] == 400, "localized injury plans must be detached and pure")
	state = BodyInjuryState.from_record(planned.value["after"]).value
	_check(state.consciousness_causes().is_empty(), "prototype limb burns must not automatically knock out")
	_check(not state.plan_change("damage", "wing", "blunt", 100, 2).is_success and not state.plan_change("damage", "head", "blunt", 1001, 2).is_success, "unknown anatomy and out-of-bounds severity must reject")
	planned = state.plan_change("heal", "arm.left", "burn", 1000, 2)
	_check(planned.value["applied_amount_permille"] == 400 and planned.value["after"]["parts"]["arm.left"]["burn"] == 0, "healing must not exceed existing injury")
	var invalid: Dictionary = before.duplicate(true)
	invalid["parts"]["head"]["blunt"] = 750
	_check(not BodyInjuryState.from_record(invalid).is_success, "zero revision cannot invent prior damage")
	var world := WorldRuntime.new()
	root.add_child(world)
	_check(world.start_simulation().is_success, "world must start")
	(world.get_node("SimulationRunner") as SimulationRunner).set_physics_process(false)
	var health: HealthSimulationSystem = world.get_simulation_system(HealthSimulationSystem.SYSTEM_ID)
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/health/injury.default.v1.json"))
	_check(BodyInjuryState.from_record(fixture).value.to_record() == health.injury_observation("body.human-2").value, "default fixture must match runtime healthy anatomy")
	_check(not health.queue_observation("body.human-2", [{"cause_id": BodyInjuryState.HEAD_CAUSE, "kind": "injury", "suppression_permille": 800}], 0, 1).is_success, "external observations cannot impersonate anatomy-owned causes")
	_check(health.queue_injury_change("body.human-2", 0, 1, "damage", "head", "blunt", 800).is_success, "trusted head injury must queue")
	_check(health.injury_observation("body.human-2").value["parts"]["head"]["blunt"] == 0 and not world.capture_world_snapshot().is_success, "pending injury must not apply early or enter a partial checkpoint")
	_check(not health.queue_injury_change("body.human-2", 0, 1, "damage", "head", "blunt", 1).is_success, "duplicate per-tick injury must reject")
	_step(world)
	_check(not health.consciousness_allows_actions("body.human-2") and health.injury_observation("body.human-2").value["parts"]["head"]["blunt"] == 800, "injury must drive canonical knockout at its accepting tick")
	var inventory: InventorySimulationSystem = world.get_simulation_system(InventorySimulationSystem.SYSTEM_ID)
	var context := AuthenticatedCommandContext.for_local_development(&"local-inventory-actor", world.world_id, world.region_id)
	_check(not inventory.authorize(context, true).is_success, "injury knockout must block existing inventory gameplay")
	_check(not health.queue_injury_change("body.human-2", 0, 2, "damage", "head", "blunt", 1).is_success, "old injury revision must not replay")
	var saved: String = world.capture_world_snapshot_json().value
	var restored := WorldRuntime.new()
	root.add_child(restored)
	_check(restored.restore_world_snapshot_json(saved).is_success, "injuries must restore through world JSON")
	var restored_health: HealthSimulationSystem = restored.get_simulation_system(HealthSimulationSystem.SYSTEM_ID)
	_check(restored_health.injury_observation("body.human-2").value == health.injury_observation("body.human-2").value and not restored_health.consciousness_allows_actions("body.human-2"), "restore must retain injury and knockout")
	_check(health.queue_observation("body.human-2", [{"cause_id": "chemical.fixture", "kind": "chemical", "suppression_permille": 800}], 0, 2).is_success, "separate chemical suppression must queue")
	_check(health.queue_injury_change("body.human-2", 1, 2, "heal", "head", "blunt", 800).is_success, "trusted treatment must queue alongside source observations")
	_step(world, 61)
	_check(not health.consciousness_allows_actions("body.human-2") and health.injury_observation("body.human-2").value["parts"]["head"]["blunt"] == 0, "head healing must not clear continuing sedation")
	_check(health.queue_observation("body.human-2", [], 1, world.current_tick_number() + 1).is_success, "clearance observation must queue")
	_step(world, 61)
	_check(health.consciousness_allows_actions("body.human-2"), "cleared sources and healed injury must permit sustained recovery")
	var revision: int = health.injury_observation("body.human-2").value["state_revision"]
	_check(health.queue_injury_change("body.human-2", revision, world.current_tick_number() + 1, "damage", "systemic", "oxygen", 800).is_success, "accumulated oxygen injury must queue")
	_step(world)
	_check(not health.consciousness_allows_actions("body.human-2"), "oxygen injury must independently suppress consciousness")
	var legacy: Dictionary = restored.capture_world_snapshot().value.to_dictionary()
	legacy["systems"]["health"]["schema_version"] = 1
	for entry in legacy["systems"]["health"]["entries"]:
		entry.erase("injuries")
	# A genuine v1 source-only snapshot has no new anatomy-owned cause IDs.
	legacy["systems"]["health"]["entries"][1]["owner"]["state"]["causes"] = [{"cause_id": "legacy.trauma", "kind": "injury", "suppression_permille": 800}]
	legacy["systems"]["health"]["entries"][1]["causes"] = [{"cause_id": "legacy.trauma", "kind": "injury", "suppression_permille": 800}]
	legacy["systems"]["health"]["entries"][1]["source_revision"] = 1
	var migrated := WorldRuntime.new()
	root.add_child(migrated)
	_check(migrated.restore_world_snapshot(WorldSnapshot.from_dictionary(legacy).value).is_success, "v1 source causes must migrate without inventing anatomy damage")
	var migrated_health: HealthSimulationSystem = migrated.get_simulation_system(HealthSimulationSystem.SYSTEM_ID)
	_check(migrated_health.injury_observation("body.human-2").value["parts"]["head"]["blunt"] == 0 and not migrated_health.consciousness_allows_actions("body.human-2"), "migration must preserve old suppression independently")
	invalid = BodyInjuryState.create("body.human-1").value.to_record()
	invalid["parts"]["head"]["blunt"] = NAN
	_check(not BodyInjuryState.from_record(invalid).is_success, "nonfinite injury severity must reject")
	var invalid_world: Dictionary = world.capture_world_snapshot().value.to_dictionary()
	invalid_world["systems"]["health"]["entries"][1]["injuries"]["last_changed_tick"] = world.current_tick_number() + 1
	var reject := WorldRuntime.new()
	root.add_child(reject)
	_check(not reject.restore_world_snapshot(WorldSnapshot.from_dictionary(invalid_world).value).is_success, "future injury mutation ticks must reject without restoring")
	reject.free()
	migrated.free()
	restored.free()
	world.free()
	if _failures == 0:
		print("Localized injuries, canonical knockout, treatment isolation and world migration scenarios passed.")
	quit(0 if _failures == 0 else 1)


func _step(world: WorldRuntime, count: int = 1) -> void:
	for _index in range(count):
		(world.get_node("SimulationRunner") as SimulationRunner)._physics_process(1.0 / 60.0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
