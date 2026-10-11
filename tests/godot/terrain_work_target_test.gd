extends SceneTree

var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func cell(mass: int, capacity: int = 2000000, ready: bool = true) -> Dictionary:
	return {"state": {"mass_milligrams": mass}, "capacity_milligrams": capacity,
		"work_ready": ready, "work_message": "" if ready else "Hold an operational component-backed shovel in the active unreserved hand.",
		"position_millimetres": [1250, -500, 2700]}

func run() -> void:
	var source := TerrainWorkTargetView.CELL_IDS[0]
	var fill := TerrainWorkTargetView.CELL_IDS[1]
	check(TerrainWorkTargetView.describe(source, cell(0)).contains("Depleted"), "zero source is depleted")
	check(TerrainWorkTargetView.describe(fill, cell(0)).contains("Empty"), "zero fill is empty rather than depleted")
	check(TerrainWorkTargetView.describe(fill, cell(2000000)).contains("Full"), "capacity equality is full")
	var partial := cell(1234567)
	var before := partial.duplicate(true)
	var text := TerrainWorkTargetView.describe(fill, partial)
	check(text.contains("Partially filled") and text.contains("1234567 mg (1.234567 kg)") and text.contains("2000000 mg (2.000000 kg)"), "exact partial mass and commissioned capacity")
	check(partial == before, "description cannot mutate observed matter")
	check(TerrainWorkTargetView.describe(source, cell(0, 0)).contains("Unavailable · no commissioned capacity"), "legacy zero budget does not imply replenishable depleted source")
	check(TerrainWorkTargetView.describe(source, cell(500000, 2000000, false)).contains("Work unavailable: Hold an operational"), "host capability reason is retained")
	check(TerrainWorkTargetView.describe(fill, cell(2000000, 2000000, false)).contains("Full"), "full and capability unavailable remain independent")
	var preview := TerrainCellPreview.new()
	root.add_child(preview)
	preview.observe({})
	check(preview._markers.is_empty() and not preview.visible, "no observation creates no fixture guesses")
	var record := {"cells": {source: cell(1500000), fill: partial}}
	var original := record.duplicate(true)
	preview.observe(record)
	check(preview._markers.size() == 2 and preview.get_child_count() == 2, "exact two marker bound")
	var marker: MeshInstance3D = preview._markers[fill]
	var label: WorldContextLabel = marker.get_child(0)
	var anchor := ProceduralWorldInventoryPreview.DISPLAY_ORIGIN + Vector3(1.25, -0.47, 2.7)
	check(marker.position.is_equal_approx(anchor) and label.position == Vector3.ZERO, "true observed anchor plus preserved 30mm marker offset")
	check(marker.get_child_count() == 1 and marker.mesh is BoxMesh, "no collision or selection surface added")
	record["cells"][fill] = cell(2000000)
	preview.observe(record)
	check(preview._markers[fill] == marker and label.text.contains("Full"), "updates reuse marker and refresh full state")
	check(original["cells"][fill] == partial, "observation remains detached and unmodified")
	preview.observe({"cells": {source: cell(0)}})
	check(preview._markers.size() == 1 and not preview._markers.has(fill), "missing cell retires feedback")
	preview.observe({})
	check(preview._markers.is_empty() and preview.get_child_count() == 0 and not preview.visible, "disconnect retires stale mass labels and anchors")
	preview.observe(original)
	check(preview._markers.size() == 2, "fresh reconnect restores observed cells")
	preview.free()
	await process_frame
	print("Terrain work feedback: %d failures" % failures)
	quit(1 if failures else 0)
