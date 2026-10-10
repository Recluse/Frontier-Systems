extends SceneTree

var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var world := WorldRuntime.new()
	root.add_child(world)
	world.start_simulation()
	var runner: SimulationRunner = world.get_node("SimulationRunner")
	runner.set_physics_process(false)
	var character := LocalHabitatCharacter.new()
	root.add_child(character)
	character.read_local_keyboard = false
	character.position = ProceduralWorldInventoryPreview.DISPLAY_ORIGIN + Vector3(0, 0.95, 0)
	var adapter := LocalInventoryBodyAdapter.new()
	root.add_child(adapter)
	_check(adapter.configure(world, character, ProceduralWorldInventoryPreview.DISPLAY_ORIGIN).is_success, "local pose bridge must configure")
	var before: String = world.capture_world_snapshot_json().value
	_check(not adapter.sample().is_success and world.capture_world_snapshot_json().value == before, "disabled bridge must remain read-only")
	adapter.set_enabled(true)
	_check(not adapter.sample().is_success, "inactive inspection capsule must not send poses")
	character.set_navigation_enabled(true)
	character.set_physics_process(false)
	_check(adapter.sample().is_success, "active opted-in capsule must enqueue pose")
	_check(not adapter.sample().is_success, "bridge must admit only one outstanding pose")
	runner._physics_process(1.0 / 60.0)
	var inventory: InventorySimulationSystem = world.get_simulation_system(InventorySimulationSystem.SYSTEM_ID)
	var body: Dictionary = inventory.capture_snapshot().value["bodies"][1]
	_check(body["position_millimetres"] == [0, 950, 0], "queued capsule pose must update integer 3D logical body")
	var epoch: int = body["action_epoch"]
	_check(adapter.sample().is_success, "stationary pose must return without another command")
	runner._physics_process(1.0 / 60.0)
	_check(inventory.capture_snapshot().value["bodies"][1]["action_epoch"] == epoch, "stationary sampling must not invent target movement epochs")
	character.position += Vector3(0, 0, 2)
	adapter.sample()
	runner._physics_process(1.0 / 60.0)
	var context: AuthenticatedCommandContext = AuthenticatedCommandContext.for_local_development(&"local-inventory-actor", world.world_id, world.region_id)
	_check(inventory.world_inventory_observation(context).value["containers"].is_empty(), "walking pose outside 3D reach must hide the tray")
	adapter.set_enabled(false)
	character.position = ProceduralWorldInventoryPreview.DISPLAY_ORIGIN
	before = world.capture_world_snapshot_json().value
	adapter.sample()
	_check(world.capture_world_snapshot_json().value == before, "turning bridge off must stop new pose commands")
	adapter.queue_free()
	character.queue_free()
	world.queue_free()
	await process_frame
	if _failures == 0:
		print("Local inventory capsule bridge and spatial access scenarios passed.")
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
