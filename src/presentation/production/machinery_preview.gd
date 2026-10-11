extends Node3D
class_name MachineryPreview
signal machine_selected(machine_id: String)

## Settled machinery uses one static compound body per physical frame. Its modules
## and canisters are child visuals, not independently simulated rigid bodies.
var _signature: String = ""
var _feedback_root: Node3D
var _feedback_signature: String = ""
var _labels: Dictionary = {}
var _socket_labels: Dictionary = {}
var _operation_feedback := MachineryOperationFeedback.new()
const ROLES: Dictionary = {"autolathe": "AUTOLATHE","solar": "SOLAR GENERATOR", "printhead": "3D PRINTER", "refinery": "REFINERY", "extractor": "RESOURCE EXTRACTOR", "router": "POWER ROUTER"}


func observe(record: Dictionary) -> void:
	if not _operation_feedback.observe(record): record = {}
	if record.is_empty():
		_signature = ""
		_labels.clear()
		_socket_labels.clear()
		for child in get_children():
			if child == _feedback_root: continue
			remove_child(child)
			child.queue_free()
		present_feedback({})
		return
	var workshop: Dictionary = record["machinery"]
	var poses: Dictionary = {}
	for id in workshop["placements"]: poses[id] = workshop["placements"][id]["position"]
	var signature: String = JSON.stringify([poses, workshop["mounts"], workshop["links"], workshop["inventory_items"]], "", true)
	if signature == _signature:
		_update_labels(workshop)
		return
	_signature = signature
	_labels.clear()
	_socket_labels.clear()
	for child in get_children():
		if child == _feedback_root: continue
		remove_child(child)
		child.queue_free()
	for id in poses:
		var body := StaticBody3D.new()
		body.position = _position(poses[id]) + Vector3(0, 0.4, 0)
		add_child(body)
		body.input_event.connect(func(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape: int) -> void:
			if PlayerInputSettings.instance().accepts_gameplay_input() and event.is_action_pressed("world_select"): machine_selected.emit(id)
		)
		_box(body, Vector3(0.7, 0.8, 0.6), Color(0.22, 0.29, 0.35), Vector3.ZERO)
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.7, 0.8, 0.6)
		collision.shape = shape
		body.add_child(collision)
		var fitted: Array = []
		for module in workshop["mounts"]:
			if workshop["mounts"][module] == id: fitted.append(workshop["parts"][module]["kind"])
		var height: float = 1.5 if fitted.has("printhead") else (1.35 if fitted.has("refinery") or fitted.has("extractor") else (1.0 if fitted.has("solar") else 0.8))
		shape.size = Vector3(1.25 if fitted.has("solar") else 0.8, height, 0.8)
		collision.position.y = height / 2.0 - 0.4
		if fitted.has("solar"):
			_box(body, Vector3(1.25, 0.05, 0.8), Color(0.06, 0.2, 0.48), Vector3(0, 0.55, 0))
			for line in range(5): _box(body, Vector3(0.015, 0.01, 0.8), Color(0.3, 0.6, 0.85), Vector3(-0.5 + line * 0.25, 0.585, 0))
		if fitted.has("printhead"):
			_box(body, Vector3(0.8, 0.06, 0.7), Color(0.75, 0.8, 0.85), Vector3(0, 0.45, 0))
			for x in [-0.35, 0.35]: _box(body, Vector3(0.06, 0.6, 0.06), Color(0.4, 0.5, 0.6), Vector3(x, 0.75, 0))
			_box(body, Vector3(0.8, 0.06, 0.08), Color(0.6, 0.7, 0.8), Vector3(0, 1.05, 0))
			_box(body, Vector3(0.16, 0.2, 0.15), Color(0.95, 0.55, 0.15), Vector3(0, 0.92, 0))
		if fitted.has("autolathe"):
			_box(body, Vector3(0.65, 0.25, 0.5), Color(0.6, 0.65, 0.7), Vector3(0, 0.48, 0))
			_cylinder(body, Vector3(-0.2, 0.7, 0), Color(0.85, 0.55, 0.1), 0.12, 0.18)
		if fitted.has("refinery"):
			for x in [-0.2, 0.2]: _cylinder(body, Vector3(x, 0.6, 0), Color(0.5, 0.65, 0.68), 0.15, 0.45)
		if fitted.has("extractor"):
			_box(body, Vector3(0.2, 0.65, 0.2), Color(0.95, 0.65, 0.1), Vector3(0, 0.6, 0))
		if fitted.has("router"):
			_box(body, Vector3(0.6, 0.08, 0.4), Color(0.2, 0.7, 0.45), Vector3(0, 0.45, 0))
		var index: int = 0
		for module in workshop["mounts"]:
			if workshop["mounts"][module] != id: continue
			var kind: String = workshop["parts"][module]["kind"]
			_box(body, Vector3(0.12, 0.12, 0.08), Color(0.2, 0.7, 0.75) if kind == "socket" else Color(0.85, 0.6, 0.2), Vector3(-0.25 + float(index % 4) * 0.16, 0.3 - float(index / 4) * 0.16, -0.33))
			index += 1
		var socket_index: int = 0
		for module in workshop["mounts"]:
			if workshop["mounts"][module] != id or workshop["parts"][module]["kind"] != "socket": continue
			for physical in workshop["inventory_items"]:
				if physical["container_id"] != InventorySimulationSystem.factory_storage_id(module): continue
				var offset := Vector3(-0.35 + socket_index * 0.3, 0.15, 0.48)
				_cylinder(body, offset, Color(0.1, 0.65, 0.7), 0.1, 0.4)
				var canister_collision := CollisionShape3D.new()
				var canister_shape := CylinderShape3D.new()
				canister_shape.radius = 0.1
				canister_shape.height = 0.4
				canister_collision.shape = canister_shape
				canister_collision.position = offset
				body.add_child(canister_collision)
				var cargo_label := Label3D.new()
				cargo_label.position = offset + Vector3(0, 0.35, 0)
				cargo_label.font_size = 30
				cargo_label.pixel_size = 0.0035
				cargo_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				body.add_child(cargo_label)
				_socket_labels[physical["item_id"]] = cargo_label
				socket_index += 1
		var title := Label3D.new()
		var outputs: int = 0
		if fitted.has("printhead") or fitted.has("autolathe"):
			for physical in workshop["inventory_items"]:
				if physical["container_id"] == InventorySimulationSystem.factory_storage_id(id) and not workshop["mounts"].has(physical["item_id"]) and not workshop["links"].has(physical["item_id"]):
					_box(body, Vector3(0.14, 0.12, 0.14), Color(0.9, 0.6, 0.2), Vector3(-0.2 + outputs * 0.18, 0.55, 0.15))
					outputs += 1
		title.position.y = 1.4
		title.font_size = 36
		title.pixel_size = 0.004
		title.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		body.add_child(title)
		_labels[id] = {"label": title, "fitted": fitted, "outputs": outputs}
	for link in workshop["links"].values():
		if not poses.has(link["a"]) or not poses.has(link["b"]): continue
		var a: Vector3 = _position(poses[link["a"]]) + Vector3(0, 0.08, 0)
		var b: Vector3 = _position(poses[link["b"]]) + Vector3(0, 0.08, 0)
		var cable := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.015
		mesh.bottom_radius = 0.015
		mesh.height = maxf(0.01, a.distance_to(b))
		cable.mesh = mesh
		add_child(cable)
		cable.position = (a + b) / 2.0
		if a.distance_to(b) > 0.01: cable.quaternion = Quaternion(Vector3.UP, (b - a).normalized())
	_update_labels(workshop)


func _update_labels(workshop: Dictionary) -> void:
	for id in _labels:
		var roles: PackedStringArray = []
		for kind in _labels[id]["fitted"]:
			if ROLES.has(kind): roles.append(ROLES[kind])
		_labels[id]["label"].text = "%s\n%s" % ["\n".join(roles) if not roles.is_empty() else "MACHINE FRAME", _operation_feedback.machines[id]["text"]]
		if _labels[id]["fitted"].has("autolathe"):
			_labels[id]["label"].text += "\nHOPPER %.3f kg IRON" % (float(workshop["cargo"].get(id, {}).get("iron", 0)) / 1000000.0)
		if int(_labels[id]["outputs"]) > 0: _labels[id]["label"].text += "\n%d PRINTED OUTPUT" % _labels[id]["outputs"]
	for carrier in _socket_labels:
		var lines: PackedStringArray = []
		for material in workshop["cargo"].get(carrier, {}):
			var amount: int = int(workshop["cargo"][carrier][material])
			if amount > 0: lines.append("%s %.3f kg" % [material, float(amount) / 1000000.0])
		_socket_labels[carrier].text = "\n".join(lines) if not lines.is_empty() else "EMPTY CANISTER"


static func _cylinder(parent: Node3D, offset: Vector3, color: Color, radius: float, height: float) -> void:
	var visual := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	visual.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	visual.material_override = material
	visual.position = offset
	parent.add_child(visual)


static func _position(coords: Array) -> Vector3:
	return MachineryPlacementFeedback.display_position(coords)


static func _box(parent: Node3D, size: Vector3, color: Color, offset: Vector3) -> void:
	var visual := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	visual.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	visual.material_override = material
	visual.position = offset
	parent.add_child(visual)



## Decorative geometry never has collision, input picking, inventory or save data.
func present_feedback(feedback: Dictionary) -> void:
	var signature: String = var_to_str(feedback)
	if signature == _feedback_signature: return
	_feedback_signature = signature
	if is_instance_valid(_feedback_root):
		remove_child(_feedback_root)
		_feedback_root.queue_free()
	_feedback_root = Node3D.new()
	_feedback_root.name = "ClientPlacementFeedback"
	add_child(_feedback_root)
	if feedback.is_empty(): return
	var size: Vector3 = feedback["size"]
	var selected: Array = feedback["selected_position"]
	if not selected.is_empty():
		var selected_size: Vector3 = feedback.get("selected_size", size)
		_footprint(_feedback_root, MachineryPlacementFeedback.display_position(selected), selected_size, Color(1.0, 0.85, 0.2))
		if feedback.get("machine_envelope", false): _envelope_edges(_feedback_root, MachineryPlacementFeedback.display_position(selected), selected_size, Color(1.0, 0.85, 0.2))
		_feedback_label(_feedback_root, MachineryPlacementFeedback.display_position(selected) + Vector3(0, selected_size.y + 0.75, 0), ("SELECTED ENVELOPE · " if feedback.get("machine_envelope", false) else "SELECTED · ") + String(feedback["selected_id"]).right(8), Color(1.0, 0.85, 0.2))
	if not feedback["ghost_visible"]: return
	var target: Vector3 = MachineryPlacementFeedback.display_position(feedback["position"])
	var color := Color(0.2, 0.85, 0.95, 0.24) if feedback["advisory_ok"] else Color(1.0, 0.35, 0.2, 0.24)
	if feedback["pending"]: color = Color(1.0, 0.8, 0.2, 0.24)
	_feedback_box(_feedback_root, size, color, target + Vector3(0, size.y / 2.0, 0))
	var ghost: MeshInstance3D = _feedback_root.get_child(_feedback_root.get_child_count() - 1)
	ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material: StandardMaterial3D = ghost.material_override
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_footprint(_feedback_root, target, size, Color(color, 1.0))
	var axes: Array[Vector3] = [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	var colors: Array[Color] = [Color(1, 0.2, 0.2), Color(0.2, 1, 0.2), Color(0.2, 0.45, 1)]
	for index in range(3):
		var extent: Vector3 = Vector3(0.018, 0.018, 0.018) + axes[index] * 0.9
		_feedback_box(_feedback_root, extent, colors[index], target + Vector3(0, 0.04, 0) + axes[index] * 0.45)
		_feedback_label(_feedback_root, target + Vector3(0, 0.1, 0) + axes[index], ["+X", "+Y", "+Z"][index], colors[index])
	_feedback_label(_feedback_root, target + Vector3(0, size.y + 0.35, 0), "PENDING HOST" if feedback["pending"] else ("ADVISORY ENVELOPE" if feedback.get("machine_envelope", false) else "PLACEMENT PREVIEW"), Color(color, 1.0))


static func _footprint(parent: Node3D, base: Vector3, size: Vector3, color: Color) -> void:
	for side in [-1.0, 1.0]:
		_feedback_box(parent, Vector3(size.x, 0.025, 0.025), color, base + Vector3(0, 0.02, side * size.z / 2.0))
		_feedback_box(parent, Vector3(0.025, 0.025, size.z), color, base + Vector3(side * size.x / 2.0, 0.02, 0))


static func _feedback_label(parent: Node3D, at: Vector3, text: String, color: Color) -> void:
	var label := Label3D.new()
	label.position = at
	label.text = text
	label.modulate = color
	label.font_size = 28
	label.pixel_size = 0.003
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	parent.add_child(label)



static func _feedback_box(parent: Node3D, size: Vector3, color: Color, at: Vector3) -> void:
	_box(parent, size, color, at)
	var visual: MeshInstance3D = parent.get_child(parent.get_child_count() - 1)
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material: StandardMaterial3D = visual.material_override
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED


## Complete selected machine AABB; the existing floor footprint supplies four edges.
static func _envelope_edges(parent: Node3D, base: Vector3, size: Vector3, color: Color) -> void:
	for x in [-1.0, 1.0]:
		for z in [-1.0, 1.0]:
			_feedback_box(parent, Vector3(0.025, size.y, 0.025), color, base + Vector3(x * size.x / 2.0, size.y / 2.0, z * size.z / 2.0))
	for side in [-1.0, 1.0]:
		_feedback_box(parent, Vector3(size.x, 0.025, 0.025), color, base + Vector3(0, size.y, side * size.z / 2.0))
		_feedback_box(parent, Vector3(0.025, 0.025, size.z), color, base + Vector3(side * size.x / 2.0, size.y, 0))
