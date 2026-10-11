extends Node3D
class_name TerrainCellPreview

## Two advisory markers. No collision, canonical matter or geometric excavation.
var _markers: Dictionary = {}


func observe(record: Dictionary) -> void:
	visible = not record.is_empty()
	if record.is_empty(): return
	for id in _markers.keys():
		if not record["cells"].has(id):
			remove_child(_markers[id])
			_markers[id].queue_free()
			_markers.erase(id)
	for id in record["cells"]:
		if not _markers.has(id):
			var marker := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			mesh.size = Vector3(0.4, 0.03, 0.4)
			marker.mesh = mesh
			var material := StandardMaterial3D.new()
			material.albedo_color = Color("#bf935b") if id == "terrain.dirt.source" else Color("#739bac")
			marker.material_override = material
			var label := WorldContextLabel.new()
			# Anchor to the advisory marker; screen layout never moves the cell.
			label.position = Vector3.ZERO
			marker.add_child(label)
			add_child(marker)
			_markers[id] = marker
		var cell: Dictionary = record["cells"][id]
		var coords: Array = cell["position_millimetres"]
		_markers[id].position = ProceduralWorldInventoryPreview.DISPLAY_ORIGIN + Vector3(float(coords[0]), float(coords[1]) + 30.0, float(coords[2])) / 1000.0
		(_markers[id].get_child(0) as WorldContextLabel).text = "%s [%s]\n%.3f kg\nDig/fill controls in Terrain overlay" % ["Dirt source" if id == "terrain.dirt.source" else "Dirt fill", id, float(cell["state"]["mass_milligrams"]) / 1000000.0]
