extends SceneTree

var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func verify(layout: WorldContextLabel.Layout, extent: Vector2) -> void:
	check(layout.shown.size() <= 8, "context card count bounded")
	for id in layout.shown:
		var card: Panel = layout.cards[id]
		var rect := Rect2(card.position, card.size)
		check(Rect2(Vector2.ZERO, extent).encloses(rect), "complete card fits viewport")
		check(card.mouse_filter == Control.MOUSE_FILTER_IGNORE, "cards pass native input")
		var label: Label = card.get_child(0)
		check(label.get_minimum_size().y <= card.size.y - 20, "all wrapped text fits card")
		for other in layout.shown:
			if other == id: continue
			check(not rect.intersects(Rect2(layout.cards[other].position, layout.cards[other].size)), "cards never overlap")

func run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1100, 700)
	root.add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.position = Vector3(0, 2, 6)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	var targets: Array[WorldContextLabel] = []
	for index in range(12):
		var target := WorldContextLabel.new()
		target.position = Vector3(index * 0.02, 0, 0)
		target.text = "True target %d\n%.3f kg\nDouble-click to extract into a carried canister" % [index, index * 0.01]
		viewport.add_child(target)
		targets.append(target)
	await process_frame
	var layout: WorldContextLabel.Layout = viewport.get_node("_WorldContextLabels").get_child(0)
	layout._process(0)
	check(layout.shown.size() >= 3, "cluster has readable separated context")
	verify(layout, Vector2(viewport.size))
	var id: int = targets[0].get_instance_id()
	var old_anchor: Vector2 = layout.anchors[id]
	camera.position.x += 0.7
	layout._process(0)
	check(layout.anchors[id].distance_to(old_anchor) > 1, "camera movement updates anchors without rebuild")
	check(layout.anchors[id].distance_to(camera.unproject_position(targets[0].global_position)) < 0.1, "leader uses true projected target")
	targets[0].visible = false
	layout._process(0)
	check(not layout.shown.has(id), "explicitly hidden labels disappear")
	targets[0].visible = true
	targets[0].position = camera.position + camera.global_basis.z
	layout._process(0)
	check(not layout.anchors.has(id), "behind-camera labels disappear")
	targets[0].position = Vector3(100, 0, 0)
	layout._process(0)
	check(not layout.anchors.has(id), "offscreen targets do not get clamped surrogate anchors")
	viewport.size = Vector2i(460, 320)
	layout._process(0)
	verify(layout, Vector2(viewport.size))
	check(layout.shown.size() < 8, "narrow viewport suppresses crowded labels")
	viewport.size = Vector2i(200, 140)
	layout._process(0)
	check(layout.shown.is_empty(), "too-small viewport hides complete context")
	viewport.size = Vector2i(1100, 700)
	targets[0].free()
	await process_frame
	layout._process(0)
	check(not layout.cards.has(id), "removed/rebuilt target retires card")
	var terrain := TerrainCellPreview.new()
	viewport.add_child(terrain)
	var record: Dictionary = {"cells": {"terrain.dirt.source": {"position_millimetres": [0, 0, 0], "state": {"mass_milligrams": 1234567}, "capacity_milligrams": 2000000, "work_ready": true, "work_message": ""}}}
	terrain.observe(record)
	var label: WorldContextLabel = terrain._markers["terrain.dirt.source"].get_child(0)
	check(label.text.contains("terrain.dirt.source") and label.text.contains("1.234567 kg"), "terrain preserves identity and observed units")
	terrain.observe({})
	check(not terrain.is_visible_in_tree(), "empty observation hides terrain labels")
	terrain.observe({"cells": {}})
	check(terrain._markers.is_empty(), "removed terrain cells retire markers and labels")
	viewport.free()
	print("World context labels: %d failures" % failures)
	quit(1 if failures else 0)
