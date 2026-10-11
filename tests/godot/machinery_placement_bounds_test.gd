extends SceneTree

var failures: int = 0


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func run() -> void:
	# Detached scoped display fixtures, never installed as authoritative state.
	var workshop: Dictionary = {"parts": {"frame": {"kind": "frame", "condition": 0}}, "mounts": {}, "placements": {}}
	verify(workshop, Vector3(1.3, 1.5, 1.3), "empty broken frame")
	workshop["parts"]["expander"] = {"kind": "expander", "condition": 0}
	workshop["mounts"]["expander"] = "frame"
	verify(workshop, Vector3(2.5, 1.5, 1.3), "empty broken expander")
	for index in range(6):
		var id: String = "socket-%d" % index
		workshop["parts"][id] = {"kind": "socket", "condition": 0}
		workshop["mounts"][id] = "frame"
	verify(workshop, Vector3(2.5, 1.5, 1.3), "six empty broken sockets")
	workshop["mounts"].erase("expander")
	verify(workshop, Vector3(2.5, 1.5, 1.3), "removed expander with six retained sockets")
	workshop["mounts"].erase("socket-5")
	verify(workshop, Vector3(1.9, 1.5, 1.3), "five retained sockets")
	workshop["mounts"].erase("socket-4")
	verify(workshop, Vector3(1.3, 1.5, 1.3), "four retained sockets")
	for kind in ["solar", "printhead", "refinery", "extractor"]:
		workshop["parts"][kind] = {"kind": kind, "condition": 0}
		workshop["mounts"][kind] = "frame"
	verify(workshop, Vector3(1.3, 1.5, 1.3), "broken ordinary mounted heads")
	for index in range(4, 8):
		var id: String = "socket-%d" % index
		workshop["parts"][id] = {"kind": "socket", "condition": 0}
		workshop["mounts"][id] = "frame"
	verify(workshop, Vector3(3.7, 1.5, 1.3), "grandfathered eight sockets")
	var record: Dictionary = {"production": {"machinery": workshop}, "position": [0, 0, 0]}
	var pending: Dictionary = MachineryPlacementFeedback.describe(record, "frame", [0, 100, -1000], "freeform", true, true, Vector3(2.5, 1.5, 1.3))
	check(pending["size"] == Vector3(2.5, 1.5, 1.3) and pending["text"].contains("2.50 × 1.50 × 1.30"), "pending dimensions and text freeze together")
	check(pending["text"].contains("Waiting for host") and pending["text"].contains("Advisory only"), "pending is not host approval")
	var absent: Dictionary = MachineryPlacementFeedback.describe({}, "", [0, 0, 0], "surface", true, false)
	check(not absent["ghost_visible"] and absent["selected_position"].is_empty(), "missing observation retires feedback")
	print("Machinery placement bounds: %d failures" % failures)
	quit(1 if failures else 0)


func verify(workshop: Dictionary, expected: Vector3, title: String) -> void:
	var original: String = JSON.stringify(workshop)
	var record: Dictionary = {"production": {"machinery": workshop}, "position": [0, 0, 0]}
	var feedback: Dictionary = MachineryPlacementFeedback.describe(record, "frame", [0, 100, -1000], "freeform", true, false)
	check(feedback["size"].is_equal_approx(expected), title + " dimensions")
	check(feedback["size"] == MachineryPlacement.half_size(workshop, "frame") * 2.0 / 1000.0, title + " exactly reuses authority geometry")
	check(feedback["text"].contains("Advisory only") and feedback["text"].contains("clearance has not been checked"), title + " does not promise overlap clearance")
	var preview := MachineryPreview.new()
	root.add_child(preview)
	preview.present_feedback(feedback)
	var ghost: MeshInstance3D = preview._feedback_root.get_child(0)
	check((ghost.mesh as BoxMesh).size.is_equal_approx(expected), title + " actual ghost mesh")
	check(ghost.position.is_equal_approx(MachineryPlacementFeedback.display_position([0, 100, -1000]) + Vector3(0, expected.y / 2.0, 0)), title + " bottom-centre positioning")
	var instance: int = preview._feedback_root.get_instance_id()
	preview.present_feedback(feedback)
	check(preview._feedback_root.get_instance_id() == instance, title + " unchanged feedback caches decorations")
	workshop["placements"]["frame"] = {"position": [0, 0, -1000]}
	feedback = MachineryPlacementFeedback.describe(record, "frame", [10000, 10000, 10000], "surface", true, false)
	preview.present_feedback(feedback)
	check(preview._feedback_root.get_child_count() == 13, title + " selected envelope has twelve edges and label")
	var bottom: Vector3 = MachineryPlacementFeedback.display_position([0, 0, -1000])
	for node in preview._feedback_root.get_children():
		if node is MeshInstance3D:
			var half: Vector3 = (node.mesh as BoxMesh).size / 2.0
			check(absf(node.position.x - bottom.x) + half.x <= expected.x / 2.0 + 0.026, title + " edge X extent")
			check(absf(node.position.z - bottom.z) + half.z <= expected.z / 2.0 + 0.026, title + " edge Z extent")
			check(node.position.y - half.y >= bottom.y - 0.026 and node.position.y + half.y <= bottom.y + expected.y + 0.026, title + " edge Y extent")
	check(feedback["text"].contains("Selected X 0.00 / Y 0.00 / Z -1.00"), title + " selection uses observed pose")
	check(preview._feedback_root.find_children("*", "CollisionObject3D", true, false).is_empty(), title + " decorations carry no collision or picking")
	preview.present_feedback({})
	check(preview._feedback_root.get_child_count() == 0, title + " explicit cleanup")
	preview.free()
	workshop["placements"].erase("frame")
	check(JSON.stringify(workshop) == original, title + " read-only observation derivation")
