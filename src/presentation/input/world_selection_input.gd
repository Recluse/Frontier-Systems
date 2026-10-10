extends Node
class_name WorldSelectionInput

## Keyboard/controller counterpart to Godot's native mouse Area3D picking.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton or not event.is_action_pressed("world_select") or event.is_echo() or not PlayerInputSettings.instance().accepts_gameplay_input():
		return
	var viewport: Viewport = get_viewport()
	var camera: Camera3D = viewport.get_camera_3d()
	if camera == null or not viewport is SubViewport:
		return
	var pointer: Vector2 = viewport.get_mouse_position() if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED else Vector2(viewport.size) / 2.0
	if not Rect2(Vector2.ZERO, Vector2(viewport.size)).has_point(pointer):
		return
	var from: Vector3 = camera.project_ray_origin(pointer)
	var query := PhysicsRayQueryParameters3D.create(from, from + camera.project_ray_normal(pointer) * 50.0)
	query.collide_with_areas = true
	query.collision_mask = 5 # Habitat/production layer 1 and inventory layer 4.
	# Bodies occlude interaction; selecting never reaches through habitat walls.
	var hit: Dictionary = camera.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or not hit["collider"] is Area3D or not hit["collider"].input_ray_pickable:
		return
	hit["collider"].input_event.emit(camera, event, hit["position"], hit["normal"], hit["shape"])
	viewport.set_input_as_handled()
