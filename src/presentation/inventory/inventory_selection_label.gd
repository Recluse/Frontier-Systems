extends Control
class_name InventorySelectionLabel

## One bounded screen card; the leader terminates at the actual display proxy.
const MARGIN: float = 12.0
const CARD_SIZE := Vector2(320, 104)
var target: Node3D
var enabled: bool = true
var _card: PanelContainer
var _lines: Array[Label] = []
var _anchor := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card = PanelContainer.new()
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#18232f")
	style.border_color = Color("#ffe066")
	style.set_border_width_all(2)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	_card.add_theme_stylebox_override("panel", style)
	add_child(_card)
	var rows := VBoxContainer.new()
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(rows)
	for index in range(3):
		var line := Label.new()
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_theme_font_size_override("font_size", 18)
		line.add_theme_color_override("font_color", Color("#fff3be") if index == 0 else Color.WHITE)
		line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		line.clip_text = true
		rows.add_child(line)
		_lines.append(line)
	visible = false


func select_proxy(proxy: Node3D, item_id: String, container_id: String, distance_mm: int) -> void:
	target = proxy
	_lines[0].text = "Item: " + item_id
	_lines[1].text = "Root: " + container_id
	_lines[2].text = "Host observed: %.2f m" % (float(distance_mm) / 1000.0)
	_process(0.0)


func _process(_delta: float) -> void:
	var viewport: Viewport = get_viewport()
	var camera: Camera3D = viewport.get_camera_3d()
	var extent: Vector2 = viewport.get_visible_rect().size
	visible = enabled and is_instance_valid(target) and camera != null and extent.x >= 180 and extent.y >= 150
	if not visible:
		return
	if camera.is_position_behind(target.global_position):
		visible = false
		return
	_anchor = camera.unproject_position(target.global_position)
	if not Rect2(Vector2.ZERO, extent).has_point(_anchor):
		visible = false
		return
	size = extent
	_card.size = Vector2(minf(CARD_SIZE.x, extent.x - MARGIN * 2), CARD_SIZE.y)
	_card.position = Vector2(extent.x - _card.size.x - MARGIN, MARGIN)
	queue_redraw()


func _draw() -> void:
	if not visible:
		return
	var edge := Vector2(clampf(_anchor.x, _card.position.x, _card.position.x + _card.size.x), _card.position.y + _card.size.y)
	draw_line(edge, _anchor, Color("#18232f"), 5.0, true)
	draw_line(edge, _anchor, Color("#ffe066"), 2.0, true)
	draw_circle(_anchor, 5.0, Color("#18232f"))
	draw_arc(_anchor, 5.0, 0, TAU, 24, Color("#ffe066"), 2.0, true)
