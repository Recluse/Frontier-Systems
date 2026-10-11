extends "res://tests/godot/habitat_visual_details_test.gd"

## Ordinary local engine rendering of real in-memory observations. No network or media upload.
const DIRECTORY: String = "res://var/captures/habitat-visual-readability"


func capture(filename: String, eye: Vector3, target: Vector3) -> void:
	habitat.camera.position = eye
	habitat.camera.look_at(target)
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(DIRECTORY.path_join(RenderingServer.get_current_rendering_method() + "-" + filename)) == OK, "native capture " + filename)


func finish() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "graphical runner required")
	if failures == 0:
		root.size = Vector2i(1280, 900)
		habitat.production.observe(production_record)
		habitat.world_inventory.observe(inventory_record)
		habitat.world_inventory.player_facing_labels = true
		terrain.observe(terrain_record)
		details._process(0)
		habitat.focus_production()
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY))
		await capture("context.png", Vector3(-9, 8, -3), Vector3(-9, 0.4, 2))
		habitat.production.set_labels_visible(false)
		habitat.world_inventory.labels_visible = false
		for marker in terrain._markers.values(): marker.get_child(0).visible = false
		await capture("geometry.png", Vector3(-9, 8, -3), Vector3(-9, 0.4, 2))
		await capture("terrain.png", Vector3(-3, 3.5, 0), Vector3(-4.6, 0.1, 3))
		await capture("overview.png", Vector3(-1, 14, 18), Vector3(-9, 0, 0))
	print("Native renderer: %s; %d failures; captures remain local" % [RenderingServer.get_current_rendering_method(), failures])
	habitat.free()
	world.free()
	await process_frame
	quit(1 if failures else 0)
