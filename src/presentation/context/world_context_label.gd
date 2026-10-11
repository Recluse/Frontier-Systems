extends Node3D
class_name WorldContextLabel

## Presentation-only anchor and text; no collision, reach, persistence or commands.
const GROUP: String = "world_context_labels"
var text: String = ""

func _ready() -> void:
	add_to_group(GROUP)
	_ensure_layout.call_deferred()


func _ensure_layout() -> void:
	# Nested viewport/overlay construction may still be adding children in _ready.
	if not is_inside_tree(): return
	var viewport: Viewport = get_viewport()
	if viewport.get_node_or_null("_WorldContextLabels") == null:
		var layer := CanvasLayer.new()
		layer.name = "_WorldContextLabels"
		layer.layer = -1
		viewport.add_child(layer)
		layer.add_child(Layout.new())


class Layout extends Control:
	const MAX_TARGETS: int = 40
	const MAX_CARDS: int = 8
	const WIDTH: float = 264.0
	const MARGIN: float = 12.0
	const MAX_OFFSET: float = 320.0
	var cards: Dictionary = {}
	var anchors: Dictionary = {}
	var shown: Array[int] = []

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(_delta: float) -> void:
		var viewport: Viewport = get_viewport()
		var camera: Camera3D = viewport.get_camera_3d()
		var extent: Vector2 = viewport.get_visible_rect().size
		var live: Dictionary = {}
		var candidates: Array[WorldContextLabel] = []
		anchors.clear()
		shown.clear()
		for node in get_tree().get_nodes_in_group(WorldContextLabel.GROUP):
			if node.get_viewport() != viewport: continue
			var id: int = node.get_instance_id()
			live[id] = true
			if candidates.size() >= MAX_TARGETS: continue
			if camera == null or not node.is_visible_in_tree() or node.text.is_empty(): continue
			if camera.is_position_behind(node.global_position): continue
			var anchor: Vector2 = camera.unproject_position(node.global_position)
			if not Rect2(Vector2.ZERO, extent).has_point(anchor): continue
			anchors[id] = anchor
			candidates.append(node)
		for id in cards.keys():
			cards[id].visible = false
			if not live.has(id):
				cards[id].queue_free()
				cards.erase(id)
		if extent.x < WIDTH + MARGIN * 2 or extent.y < 180:
			queue_redraw()
			return
		size = extent
		var center: Vector2 = extent / 2.0
		candidates.sort_custom(func(a: WorldContextLabel, b: WorldContextLabel) -> bool:
			var da: float = anchors[a.get_instance_id()].distance_squared_to(center)
			var db: float = anchors[b.get_instance_id()].distance_squared_to(center)
			return da < db if not is_equal_approx(da, db) else a.text < b.text
		)
		# Reserve the existing inventory selection card's maximum rectangle.
		var occupied: Array[Rect2] = [Rect2(Vector2(extent.x - 332, 12), Vector2(320, 104)).grow(6)]
		var bounds := Rect2(Vector2.ONE * MARGIN, extent - Vector2.ONE * MARGIN * 2)
		for target in candidates:
			if shown.size() >= MAX_CARDS: break
			var id: int = target.get_instance_id()
			if not cards.has(id): cards[id] = _make_card()
			var card: Panel = cards[id]
			var label: Label = card.get_child(0)
			label.text = target.text
			label.size = Vector2(WIDTH - 20, 0)
			var height: float = maxf(52, label.get_minimum_size().y + 20)
			card.size = Vector2(WIDTH, height)
			var anchor: Vector2 = anchors[id]
			var placed: bool = false
			for row in [0, -1, 1, -2, 2, -3, 3]:
				for side in [1, -1]:
					var x: float = anchor.x + 18 if side == 1 else anchor.x - WIDTH - 18
					var pos := Vector2(clampf(x, bounds.position.x, bounds.end.x - WIDTH), clampf(anchor.y - height / 2 + row * (height + 8), bounds.position.y, bounds.end.y - height))
					var rect := Rect2(pos, card.size)
					if height > bounds.size.y or rect.get_center().distance_to(anchor) > MAX_OFFSET: continue
					var blocked: bool = false
					for other in occupied:
						if rect.grow(4).intersects(other): blocked = true; break
					if blocked: continue
					card.position = pos
					card.visible = true
					occupied.append(rect.grow(4))
					shown.append(id)
					placed = true
					break
				if placed: break
		queue_redraw()

	func _make_card() -> Panel:
		var panel := Panel.new()
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#18232f")
		style.border_color = Color("#91bbc9")
		style.set_border_width_all(1)
		panel.add_theme_stylebox_override("panel", style)
		add_child(panel)
		var label := Label.new()
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.position = Vector2(10, 10)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", 16)
		panel.add_child(label)
		return panel

	func _draw() -> void:
		for id in shown:
			var rect := Rect2(cards[id].position, cards[id].size)
			var anchor: Vector2 = anchors[id]
			var edge := Vector2(clampf(anchor.x, rect.position.x, rect.end.x), clampf(anchor.y, rect.position.y, rect.end.y))
			draw_line(edge, anchor, Color("#18232f"), 4.0, true)
			draw_line(edge, anchor, Color("#91bbc9"), 1.5, true)
			draw_circle(anchor, 3.0, Color("#91bbc9"))
