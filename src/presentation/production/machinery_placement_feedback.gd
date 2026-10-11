extends RefCounted
class_name MachineryPlacementFeedback

## Volatile presentation data only. No commands, inventory records or persistence.
static func display_position(coords: Array) -> Vector3:
	return ProceduralWorldInventoryPreview.DISPLAY_ORIGIN + Vector3(float(coords[0]), float(coords[1]), float(coords[2])) / 1000.0


static func envelope(workshop: Dictionary, machine_id: String) -> Vector3:
	var kinds: Array = []
	for module in workshop.get("mounts", {}):
		if workshop["mounts"][module] == machine_id:
			kinds.append(workshop["parts"][module]["kind"])
	var height: float = 1.5 if kinds.has("printhead") else (1.35 if kinds.has("refinery") or kinds.has("extractor") else (1.0 if kinds.has("solar") else 0.8))
	return Vector3(1.25 if kinds.has("solar") else 0.8, height, 0.8)


static func describe(record: Dictionary, machine_id: String, coords: Array, mode: String, shown: bool, pending: bool) -> Dictionary:
	var workshop: Dictionary = record.get("production", {}).get("machinery", {})
	var placements: Dictionary = workshop.get("placements", {})
	var exists: bool = workshop.get("parts", {}).get(machine_id, {}).get("kind", "") == "frame"
	var deployed: bool = placements.has(machine_id)
	var displayed: Array = placements[machine_id]["position"] if deployed else coords
	var valid_position: bool = InventorySpatialMath.is_position(displayed)
	var distance: float = 0.0
	var reachable: bool = false
	if valid_position and InventorySpatialMath.is_position(record.get("position", [])):
		distance = InventorySpatialMath.distance_millimetres(record["position"], displayed) / 1000.0
		reachable = distance <= float(InventorySimulationSystem.WORLD_REACH_MILLIMETRES) / 1000.0
	var floor_ok: bool = valid_position and (mode == "freeform" or int(coords[1]) == 0)
	var advisory: String = "Within estimated reach; host checks ownership, hands and revision."
	if not reachable: advisory = "Outside estimated 1.5 m reach; approach the target."
	if not floor_ok: advisory = "Floor placement requires Y=0; change Y or choose Freeform."
	if deployed: advisory = "Selected frame is deployed; pack it before placing again."
	if not exists: advisory = "Select a packed machine frame."
	if pending: advisory = "Waiting for host command result; target held at submitted coordinates."
	var text: String = "%s\nFixed orientation · +X red / +Y up green / +Z blue" % machine_id
	if valid_position:
		text += "\n%s X %.2f / Y %.2f / Z %.2f m · distance %.2f m\n%s" % ["Selected" if deployed else "Target", float(displayed[0]) / 1000.0, float(displayed[1]) / 1000.0, float(displayed[2]) / 1000.0, distance, advisory]
	return {
		"selected_id": machine_id if exists else "",
		"selected_position": placements.get(machine_id, {}).get("position", []).duplicate(),
		"ghost_visible": shown and exists and not deployed and valid_position,
		"position": coords.duplicate(), "size": envelope(workshop, machine_id),
		"pending": pending, "advisory_ok": reachable and floor_ok, "text": text
	}
