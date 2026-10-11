extends RefCounted
class_name EngineeringFailureGuidance

## Presentation only: broad codes remain broad; unknown codes get no guessed advice.
const ADVICE: Dictionary = {
	"inventory_revision_conflict": "Wait for a current host inventory view, then reselect the item and destination. A fresh view may not resolve an exhausted revision.",
	"body_inventory_revision_conflict": "Wait for a current host inventory view, then reselect the item and slot. A fresh view may not resolve an exhausted revision.",
	"inventory_source_conflict": "Review the item's location in the latest host inventory view and select its current source.",
	"equipment_slot_capacity": "Review the item's loaded size and the selected slot's limits; choose a compatible slot with sufficient capacity.",
	"shared_inventory_conflict": "Review the latest host inventory view: item location, ownership, destination capacity and nearby storage access. This code covers several causes.",
	"inventory_development_rejected": "Review current host inventory and reach observations. If reach is the reported reason, approach the target and wait for the host view to update.",
	"production_rejected": "Review current Workstation prerequisites: shared stock, power, energy, receiving capacity and access. Wait for a current host view before choosing another action.",
	"invalid_machinery_intent": "Review the selected machine, parts, materials and capacity in the latest host view; check the placement draft if placing equipment.",
	"wall_construction_denied": "Review the selected plate or wall and the placement draft: floor Y=0, grid, orientation and overlap. Check host reach and inventory capacity observations."
}


static func describe(result: ServiceResult, original_text: String) -> String:
	if result.is_success:
		return original_text
	var text: String = original_text + "\nCode: " + String(result.error_code)
	var advice: String = ADVICE.get(String(result.error_code), "")
	if not advice.is_empty():
		text += "\nNext: " + advice + " The host rechecks any new request; nothing is retried automatically."
	return text
