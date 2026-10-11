extends SceneTree

## Local nongenerative render/native input check. No host, ports or uploads.
var failures: int = 0
var selections: int = 0
var requests: int = 0


func _initialize() -> void:
	OS.set_environment("FRONTIER_EVENT_URL", "")
	OS.set_environment("FRONTIER_EVENT_TOKEN", "")
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func click(viewport: Viewport, mouse: InputEventMouseButton) -> void:
	viewport.push_input(mouse, true)
	var released := mouse.duplicate() as InputEventMouseButton
	released.pressed = false
	viewport.push_input(released, true)


func run() -> void:
	PlayerInputSettings.instance()._reset_map()
	root.size = Vector2i(1000, 700)
	var container := SubViewportContainer.new()
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	root.add_child(container)
	var viewport := SubViewport.new()
	viewport.size = root.size
	viewport.own_world_3d = true
	viewport.physics_object_picking = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)
	var habitat := ProceduralHabitatPreview.new()
	viewport.add_child(habitat)
	var feedback: HabitatTargetFeedback = habitat.get_child(habitat.get_child_count() - 1).get_child(0)
	var source: Area3D = habitat.production._source_areas["deposit.iron"]
	habitat.production.source_selected.connect(func(_id: String) -> void: selections += 1)
	habitat.production.extraction_requested.connect(func(_id: String) -> void: requests += 1)
	habitat.camera.position = source.global_position + Vector3(0, 1.4, 3)
	habitat.camera.look_at(source.global_position)
	habitat.camera.set_process(false)
	await create_timer(0.5).timeout
	# Explicitly mark synthetic pointer entry before push_input, as required by
	# Viewport's native GUI/physics picking contract; don't move the OS cursor.
	viewport.notify_mouse_entered()
	# Direct child injection starts its own event transaction; ordinary container
	# forwarding shares the parent Window's handled state instead.
	viewport.handle_input_locally = true
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(viewport.size) / 2.0
	motion.global_position = motion.position
	viewport.push_input(motion, true)
	var mouse := InputEventMouseButton.new()
	mouse.position = motion.position
	mouse.global_position = mouse.position
	mouse.window_id = root.get_window_id()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	click(viewport, mouse)
	await create_timer(0.2).timeout
	check(selections == 1 and requests == 0 and feedback.selected == source, "native single click selects without extraction")
	mouse.double_click = true
	click(viewport, mouse)
	await create_timer(0.2).timeout
	check(requests == 1, "native double click requests extraction")
	var edit := LineEdit.new()
	root.add_child(edit)
	edit.grab_focus()
	click(viewport, mouse)
	await create_timer(0.2).timeout
	check(requests == 1 and selections == 2 and not feedback.visible, "native mouse cannot leak gameplay through UI focus")
	var button := Button.new()
	var ui_layer := CanvasLayer.new()
	ui_layer.layer = 10
	root.add_child(ui_layer)
	# Exercise the same guard in the GUI viewport, before the overlapping world
	# viewport receives any unhandled mouse event from its container.
	var gui_guard := WorldSelectionInput.new()
	root.add_child(gui_guard)
	button.text = "Close help"
	button.position = Vector2(viewport.size) / 2.0 - Vector2(60, 30)
	button.size = Vector2(120, 60)
	ui_layer.add_child(button)
	var activations: Array[bool] = []
	button.pressed.connect(func() -> void: activations.append(true))
	await RenderingServer.frame_post_draw
	mouse.double_click = false
	root.push_input(motion, true)
	click(root, mouse)
	await create_timer(0.2).timeout
	check(activations.size() == 1 and button.has_focus() and requests == 1 and selections == 2, "native focused UI allows another button activation while world picking stays blocked")
	ui_layer.free()
	gui_guard.free()
	edit.release_focus()
	edit.free()
	await create_timer(0.2).timeout
	check(feedback.visible and feedback._lines[2].text.contains("deposit.iron"), "selected feedback resumes after UI focus release")
	await RenderingServer.frame_post_draw
	var directory: String = "res://var/ci/habitat-target-feedback/captures"
	DirAccess.make_dir_recursive_absolute(directory)
	check(viewport.get_texture().get_image().save_png(directory.path_join("selected-source.png")) == OK, "local render capture saved")
	print("Native habitat targeting: %d failures" % failures)
	PlayerInputSettings.instance()._reset_map()
	container.free()
	quit(1 if failures else 0)
