extends Node
class_name WorldSelectionInput

## Keyboard/controller counterpart to Godot's native mouse Area3D picking.
static func gameplay_allowed(viewport: Viewport) -> bool:
	return PlayerInputSettings.instance().accepts_gameplay_input() and viewport.gui_get_focus_owner() == null and (Engine.get_main_loop() as SceneTree).root.gui_get_focus_owner() == null


func _unhandled_input(event: InputEvent) -> void:
	# GUI controls receive their mouse activation first. Only leftover gameplay
	# selection is consumed here, before Godot's native physics picking stage.
	if event.is_action_pressed("world_select") and not gameplay_allowed(get_viewport()):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton or not event.is_action_pressed("world_select") or event.is_echo() or not gameplay_allowed(get_viewport()):
		return
	var viewport: Viewport = get_viewport()
	var camera: Camera3D = viewport.get_camera_3d()
	if camera == null or not viewport is SubViewport:
		return
	var pointer: Vector2 = viewport.get_mouse_position() if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED else Vector2(viewport.size) / 2.0
	if not Rect2(Vector2.ZERO, Vector2(viewport.size)).has_point(pointer):
		return
	var hit: Dictionary = ray_target(camera, pointer)
	if hit.is_empty() or not hit["collider"] is Area3D or not hit["collider"].input_ray_pickable:
		return
	hit["collider"].input_event.emit(camera, event, hit["position"], hit["normal"], hit["shape"])
	viewport.set_input_as_handled()


static func ray_target(camera: Camera3D, pointer: Vector2) -> Dictionary:
	var from: Vector3 = camera.project_ray_origin(pointer)
	var query := PhysicsRayQueryParameters3D.create(from, from + camera.project_ray_normal(pointer) * 50.0)
	query.collide_with_areas = true
	query.collision_mask = 5 # Habitat/production layer 1 and inventory layer 4.
	# Bodies occlude interaction; selecting never reaches through habitat walls.
	return camera.get_world_3d().direct_space_state.intersect_ray(query)
