extends VBoxContainer
class_name FirstPlayableTaskGuidePanel

## Read-only, bounded wrapping rows inside its own scrollable tab.
var _rows: Array[Label] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title := Label.new()
	title.text = "Gather → transport → refine → print → collect → recycle → reprint"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)
	var scope := Label.new()
	scope.text = "Current host observations only. Shared stock and walls do not prove your past actions. Values can decrease after use, transfer or removal. These are steps to try, not a completion checklist. Use Workstation for the paid loop and confirmed session steps; Construction is optional."
	scope.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scope.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scope)
	for index in range(9):
		var row := Label.new()
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		add_child(row)
		_rows.append(row)
	observe({})


func observe(record: Dictionary) -> void:
	var production: Dictionary = record.get("production", {}) if typeof(record.get("production")) == TYPE_DICTIONARY else {}
	var lines: PackedStringArray = FirstPlayableTaskGuide.describe(production)
	for index in range(_rows.size()):
		_rows[index].text = lines[index] if index < lines.size() else ""
		_rows[index].visible = index < lines.size()
