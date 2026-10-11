extends Node3D
class_name TerrainCellPreview

## At most two advisory markers. No collision, canonical matter or excavation.
var _markers: Dictionary = {}


func observe(record: Dictionary) -> void:
	visible = not record.is_empty()
	var cells: Dictionary = record.get("cells", {})
	for id in _markers.keys():
		if not cells.has(id):
			remove_child(_markers[id])
			_markers[id].queue_free()
			_markers.erase(id)
	for id in TerrainWorkTargetView.CELL_IDS:
		if not cells.has(id): continue
		if not _markers.has(id):
			var marker := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			mesh.size = Vector3(0.4, 0.03, 0.4)
			marker.mesh = mesh
			marker.material_override = StandardMaterial3D.new()
			var label := WorldContextLabel.new()
			# Anchor to the advisory marker; screen layout never moves the cell.
			label.position = Vector3.ZERO
			marker.add_child(label)
			add_child(marker)
			_markers[id] = marker
		var cell: Dictionary = cells[id]
		var marker: MeshInstance3D = _markers[id]
		var coords: Array = cell["position_millimetres"]
		marker.position = ProceduralWorldInventoryPreview.DISPLAY_ORIGIN + Vector3(float(coords[0]), float(coords[1]) + 30.0, float(coords[2])) / 1000.0
		(marker.material_override as StandardMaterial3D).albedo_color = TerrainWorkTargetView.color(id, cell)
		(marker.get_child(0) as WorldContextLabel).text = TerrainWorkTargetView.describe(id, cell)
