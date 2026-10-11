extends Node3D
class_name HabitatVisualDetails

## MIT authored mesh-only decoration. No picking, commands or persistent state.
var habitat: ProceduralHabitatPreview
var _tray_revision: int = -1
var _trays: Node3D
var _terrain_details: Dictionary = {}


static func box(parent: Node3D, size: Vector3, location: Vector3, color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	instance.mesh = mesh
	instance.material_override = material
	instance.position = location
	parent.add_child(instance)
	return instance


static func resource(mesh: MeshInstance3D, index: int, color: Color) -> void:
	# Existing centre/pick box stay fixed; children inherit depletion scale/visibility.
	var sizes: Array[Vector3] = [Vector3(0.24, 0.23, 0.23), Vector3(0.16, 0.38, 0.18), Vector3(0.3, 0.12, 0.28)]
	for side in [-1.0, 1.0]:
		var chunk := box(mesh, sizes[index], Vector3(side * 0.18, -0.08, side * 0.12), color.lightened(0.12))
		chunk.rotation = Vector3(0, side * 0.35, side * 0.2)
	if index == 1:
		var prism := PrismMesh.new()
		prism.size = Vector3(0.5, 0.5, 0.5)
		mesh.mesh = prism
	elif index == 2:
		(mesh.mesh as BoxMesh).size = Vector3(0.5, 0.25, 0.5)


static func workstation(parent: Node3D) -> void:
	var details := Node3D.new()
	details.name = "WorkbenchDetails"
	parent.add_child(details)
	for x in [-7.45, -4.55]:
		for z in [2.65, 3.35]:
			box(details, Vector3(0.12, 0.72, 0.12), Vector3(x, 0.36, z), Color("#34454e"))
	box(details, Vector3(3.5, 0.08, 0.06), Vector3(-6, 0.88, 2.53), Color("#7ca5aa"))
	box(details, Vector3(0.65, 0.38, 0.32), Vector3(-7.1, 1.04, 3.2), Color("#34454e"))
	box(details, Vector3(0.48, 0.2, 0.02), Vector3(-7.1, 1.08, 3.025), Color("#7ca5aa"))
	for x in [-6.1, -5.2]:
		box(details, Vector3(0.6, 0.025, 0.6), Vector3(x, 0.865, 3), Color("#cad0c6"))


func _process(_delta: float) -> void:
	if habitat == null or habitat.world_inventory == null: return
	var inventory := habitat.world_inventory
	if _tray_revision != inventory._rebuilds:
		_tray_revision = inventory._rebuilds
		if _trays != null:
			remove_child(_trays)
			_trays.queue_free()
		_trays = Node3D.new()
		add_child(_trays)
		if inventory._rendered != null:
			var count: int = 0
			for child in inventory._rendered.get_children():
				if child is MeshInstance3D and child.mesh is BoxMesh and child.mesh.size == Vector3(1, 0.08, 0.6):
					if count >= 32: break
					count += 1
					var origin: Vector3 = child.position
					for side in [-1.0, 1.0]:
						box(_trays, Vector3(1.05, 0.09, 0.025), origin + Vector3(0, 0.06, side * 0.3), Color("#91a8af"))
						box(_trays, Vector3(0.025, 0.09, 0.6), origin + Vector3(side * 0.51, 0.06, 0), Color("#91a8af"))
					box(_trays, Vector3(0.82, 0.66, 0.38), origin + Vector3(0, -0.37, 0), Color("#34454e"))
	_trays.visible = inventory.visible
	var live: Dictionary = {}
	for child in habitat.get_children():
		if not child is TerrainCellPreview: continue
		for id in child._markers:
			var marker: MeshInstance3D = child._markers[id]
			live[id] = true
			if not _terrain_details.has(id):
				var detail := Node3D.new()
				add_child(detail)
				_terrain_details[id] = detail
				for side in [-1.0, 1.0]:
					box(detail, Vector3(0.56, 0.018, 0.035), Vector3(0, 0, side * 0.28), Color("#c1b394"))
					box(detail, Vector3(0.035, 0.018, 0.56), Vector3(side * 0.28, 0, 0), Color("#c1b394"))
			var detail: Node3D = _terrain_details[id]
			detail.position = marker.position
			detail.visible = child.visible and marker.visible
	for id in _terrain_details.keys():
		if live.has(id): continue
		remove_child(_terrain_details[id])
		_terrain_details[id].queue_free()
		_terrain_details.erase(id)
