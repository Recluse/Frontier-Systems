extends RefCounted
class_name OverlayThemeDefinition

## Declarative appearance only; no resource paths, scripts or gameplay bindings.
var _record: Dictionary = {}


func to_record() -> Dictionary:
	return _record.duplicate(true)


func background_color() -> Color:
	return Color(_record["colors"]["background"])


func build_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = int(_record["font_size"])
	var colors: Dictionary = _record["colors"]
	for type_name in ["Label", "Button", "CheckButton", "CheckBox", "OptionButton", "LineEdit", "TextEdit", "ItemList"]:
		theme.set_color("font_color", type_name, Color(colors["text"]))
		theme.set_color("font_hover_color", type_name, Color(colors["text"]))
		theme.set_color("font_pressed_color", type_name, Color(colors["text"]))
		theme.set_color("font_focus_color", type_name, Color(colors["text"]))
		theme.set_color("font_disabled_color", type_name, Color(colors["text"]).lerp(Color(colors["panel"]), 0.35))
	for type_name in ["VBoxContainer", "HBoxContainer", "GridContainer"]:
		if type_name == "GridContainer":
			theme.set_constant("h_separation", type_name, int(_record["spacing"]))
			theme.set_constant("v_separation", type_name, int(_record["spacing"]))
		else:
			theme.set_constant("separation", type_name, int(_record["spacing"]))
	var panel: StyleBoxFlat = _style(Color(colors["panel"]), Color(colors["accent"]), 1)
	theme.set_stylebox("panel", "PanelContainer", panel)
	theme.set_stylebox("panel", "ItemList", panel.duplicate())
	theme.set_stylebox("selected", "ItemList", _style(Color(colors["panel"]).lerp(Color(colors["accent"]), 0.25), Color(colors["accent"]), 1))
	theme.set_stylebox("selected_focus", "ItemList", _style(Color(colors["panel"]).lerp(Color(colors["accent"]), 0.25), Color(colors["accent"]), 2))
	theme.set_color("font_selected_color", "ItemList", Color(colors["text"]))
	theme.set_stylebox("panel", "PopupMenu", panel.duplicate())
	theme.set_color("font_color", "PopupMenu", Color(colors["text"]))
	for type_name in ["Button", "OptionButton", "LineEdit"]:
		theme.set_stylebox("normal", type_name, _style(Color(colors["panel"]), Color(colors["accent"]), 1))
		theme.set_stylebox("hover", type_name, _style(Color(colors["panel"]).lerp(Color(colors["accent"]), 0.15), Color(colors["accent"]), 2))
		theme.set_stylebox("pressed", type_name, _style(Color(colors["panel"]).lerp(Color(colors["accent"]), 0.25), Color(colors["accent"]), 2))
		theme.set_stylebox("disabled", type_name, _style(Color(colors["panel"]), Color(colors["panel"]), 1))
		var focus: StyleBoxFlat = _style(Color.TRANSPARENT, Color(colors["accent"]), 2)
		theme.set_stylebox("focus", type_name, focus)
	return theme


func _style(fill: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(int(_record["corner_radius"]))
	style.content_margin_left = int(_record["spacing"])
	style.content_margin_right = int(_record["spacing"])
	style.content_margin_top = int(_record["spacing"])
	style.content_margin_bottom = int(_record["spacing"])
	return style


static func from_record(record: Dictionary) -> ServiceResult:
	var fields := PackedStringArray(["schema_version", "definition_id", "display_name", "colors", "font_size", "spacing", "corner_radius"])
	if not ControlContractValidation.has_exact_fields(record, fields) or not ControlContractValidation.is_integer(record.get("schema_version"), 1, 1):
		return ServiceResult.failure(&"invalid_overlay_theme", "A complete versioned theme record is required.")
	if not ControlContractValidation.is_id(record["definition_id"]) or not ControlContractValidation.is_id(record["display_name"]):
		return ServiceResult.failure(&"invalid_overlay_theme_identity", "Theme ID and display name must be non-empty bounded strings.")
	if not ControlContractValidation.is_integer(record["font_size"], 12, 32) or not ControlContractValidation.is_integer(record["spacing"], 4, 24) or not ControlContractValidation.is_integer(record["corner_radius"], 0, 16):
		return ServiceResult.failure(&"invalid_overlay_theme_dimensions", "Theme dimensions are outside the supported bounds.")
	if typeof(record["colors"]) != TYPE_DICTIONARY or not ControlContractValidation.has_exact_fields(record["colors"], PackedStringArray(["background", "panel", "text", "accent"])):
		return ServiceResult.failure(&"invalid_overlay_theme_colors", "A complete semantic color palette is required.")
	var pattern := RegEx.new()
	pattern.compile("^#[0-9a-fA-F]{6}$")
	for value in record["colors"].values():
		if typeof(value) != TYPE_STRING or pattern.search(value) == null:
			return ServiceResult.failure(&"invalid_overlay_theme_color", "Theme colors must be opaque six-digit hex values.")
	var definition := OverlayThemeDefinition.new()
	definition._record = record.duplicate(true)
	return ServiceResult.success(definition)
