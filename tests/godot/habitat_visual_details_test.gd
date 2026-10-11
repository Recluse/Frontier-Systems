extends SceneTree

## In-memory canonical observations; no host, ports, service callbacks or saved state.
var failures: int = 0
var world: WorldRuntime
var habitat: ProceduralHabitatPreview
var terrain: TerrainCellPreview
var details: HabitatVisualDetails
var production_record: Dictionary
var inventory_record: Dictionary
var terrain_record: Dictionary


func _initialize() -> void:
	OS.set_environment("FRONTIER_EVENT_URL", "")
	OS.set_environment("FRONTIER_EVENT_TOKEN", "")
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func collision_count(node: Node) -> int:
	var count: int = 1 if node is CollisionObject3D else 0
	for child in node.get_children(): count += collision_count(child)
	return count


func run() -> void:
	world = WorldRuntime.new()
	world.resource_carriers_enabled = true
	root.add_child(world)
	check(world.start_simulation().is_success, "real local world starts")
	world.get_node("SimulationRunner").set_physics_process(false)
	var context := AuthenticatedCommandContext.from_authenticated_session(&"local-inventory-actor", &"visual-fixture", world.world_id, world.region_id, PackedStringArray(["inventory.operate", "terrain.operate"]))
	var inventory := world.get_simulation_system(InventorySimulationSystem.SYSTEM_ID) as InventorySimulationSystem
	production_record = world.production_observation(context).value
	inventory_record = inventory.world_inventory_observation(context).value
	terrain_record = world.terrain_observation(context).value
	var canonical: String = world.capture_world_snapshot_json().value
	habitat = ProceduralHabitatPreview.new()
	root.add_child(habitat)
	habitat.character.set_navigation_enabled(false)
	habitat.camera.set_process(false)
	terrain = TerrainCellPreview.new()
	habitat.add_child(terrain)
	for child in habitat.get_children():
		if child is HabitatVisualDetails: details = child
	habitat.production.observe(production_record)
	check(habitat.world_inventory.observe(inventory_record).is_success, "real scoped inventory observation")
	terrain.observe(terrain_record)
	details._process(0)
	check(details._trays.get_child_count() > 0, "real trays receive mesh details")
	habitat.world_inventory.visible = false
	details._process(0)
	check(not details._trays.visible, "hidden inventory hides decoration")
	habitat.world_inventory.visible = true
	details._process(0)
	check(details._trays.visible, "inventory visibility restores decoration")
	var tray_root := details._trays
	details._process(0)
	check(details._trays == tray_root, "unchanged observation does not allocate tray meshes")
	check(collision_count(details) == 0, "details add no collision or pick surfaces")
	check(collision_count(habitat.production.get_node("WorkbenchDetails")) == 0, "workbench details cannot occlude target rays")
	check(details._terrain_details.size() == 2, "only real observed terrain markers decorated")
	for id in terrain._markers:
		var marker: MeshInstance3D = terrain._markers[id]
		check(marker.get_child_count() == 1, "terrain preview and context children preserved")
		check(details._terrain_details[id].position == marker.position, "outline follows unchanged observed anchor")
	var production := habitat.production
	for id in production._deposits:
		var source: Area3D = production._source_areas[id]
		var coords: Array = ProductionSimulationSystem.SOURCE_POSITIONS[id]
		var origin := ProceduralWorldInventoryPreview.DISPLAY_ORIGIN + Vector3(coords[0], coords[1], coords[2]) / 1000.0 + Vector3(0, 0.25, 0)
		check(source.position == origin and production._deposits[id].position == origin, "source centre remains fixed")
		check((source.get_child(0).shape as BoxShape3D).size == Vector3(0.6, 0.6, 0.6), "source pick box preserved")
		check(production._source_labels[id].position == origin, "context source anchor preserved")
		check(collision_count(production._deposits[id]) == 0, "resource detail has no collision")
	var workstation_found: bool = false
	for child in production.get_children():
		if child is Area3D and child.position == Vector3(-6, 0.8, 3):
			workstation_found = true
			check((child.get_child(0).shape as BoxShape3D).size == Vector3(3.5, 0.3, 1), "workstation pick dimensions unchanged")
	check(workstation_found, "workstation original position preserved")
	var depleted := production_record.duplicate(true)
	depleted["deposits"]["deposit.iron"] = 0
	production.observe(depleted)
	check(not production._deposits["deposit.iron"].visible and not production._source_areas["deposit.iron"].input_ray_pickable, "depletion hides parent and all resource details")
	production.observe({})
	for id in production._deposits:
		check(not production._deposits[id].visible and not production._source_areas[id].input_ray_pickable, "unavailable resources cannot retain decorations or picking")
	terrain.observe({})
	details._process(0)
	check(details._terrain_details.is_empty(), "unavailable terrain retires outlines")
	var empty := inventory_record.duplicate(true)
	empty["containers"] = []
	habitat.world_inventory.observe(empty)
	details._process(0)
	check(details._trays.get_child_count() == 0, "removed trays retire decoration")
	check(world.capture_world_snapshot_json().value == canonical, "all display/lifecycle operations preserve canonical world")
	print("Habitat visual details: %d failures" % failures)
	await finish()


func finish() -> void:
	habitat.free()
	world.free()
	await process_frame
	quit(1 if failures else 0)
