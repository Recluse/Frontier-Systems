extends RefCounted
class_name OverlayPanelRegistry

## Trusted host registers existing controls. JSON cannot supply factories or scene paths.
const MAX_PANELS: int = 16
var _panels: Dictionary = {}


func register_panel(panel_id: String, panel: Control) -> ServiceResult:
	if not ControlContractValidation.is_id(panel_id) or not is_instance_valid(panel) or _panels.has(panel_id) or _panels.size() >= MAX_PANELS:
		return ServiceResult.failure(&"invalid_overlay_panel", "Panel registration requires a unique ID and live control within capacity.")
	if panel.get_parent() != null:
		return ServiceResult.failure(&"overlay_panel_already_parented", "Register panels before adding them to the layout host.")
	for registered in _panels.values():
		if registered == panel:
			return ServiceResult.failure(&"overlay_panel_alias", "A control must have one registered panel ID.")
	_panels[panel_id] = panel
	return ServiceResult.success()


func resolve_layout(definition: OverlayLayoutDefinition) -> ServiceResult:
	if definition == null:
		return ServiceResult.failure(&"invalid_overlay_layout", "A validated layout is required.")
	var ids: Array = definition.to_record()["panel_ids"]
	# v1 arranges the complete two-panel prototype; neither required panel can disappear.
	if _panels.size() != ids.size():
		return ServiceResult.failure(&"overlay_layout_incomplete", "The layout must include every registered panel.")
	var resolved: Array[Control] = []
	for panel_id in ids:
		if not _panels.has(panel_id) or not is_instance_valid(_panels[panel_id]):
			return ServiceResult.failure(&"unknown_overlay_panel", "The layout references an unavailable panel.")
		resolved.append(_panels[panel_id])
	return ServiceResult.success(resolved)
