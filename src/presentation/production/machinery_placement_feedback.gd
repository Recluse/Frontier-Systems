extends RefCounted
class_name MachineryPlacementFeedback

## Volatile presentation data only. No commands, inventory records or persistence.
static func display_position(coords: Array) -> Vector3:
	return ProceduralWorldInventoryPreview.DISPLAY_ORIGIN + Vector3(float(coords[0]), float(coords[1]), float(coords[2])) / 1000.0


static func envelope(workshop: Dictionary, machine_id: String) -> Vector3:
	# Reuse the host's physical reservation; condition and contents do not shrink it.
	var observed: Dictionary = {"mounts": workshop.get("mounts", {}), "parts": workshop.get("parts", {})}
	return MachineryPlacement.half_size(observed, machine_id) * 2.0 / 1000.0


static func describe(record: Dictionary, machine_id: String, coords: Array, mode: String, shown: bool, pending: bool, held_size: Vector3 = Vector3.ZERO) -> Dictionary:
	var workshop: Dictionary = record.get("production", {}).get("machinery", {})
	var placements: Dictionary = workshop.get("placements", {})
	var exists: bool = workshop.get("parts", {}).get(machine_id, {}).get("kind", "") == "frame"
	var deployed: bool = placements.has(machine_id)
	var displayed: Array = placements[machine_id]["position"] if deployed and not pending else coords
	var valid_position: bool = InventorySpatialMath.is_position(displayed)
	var distance: float = 0.0
	var reachable: bool = false
	if valid_position and InventorySpatialMath.is_position(record.get("position", [])):
		distance = InventorySpatialMath.distance_millimetres(record["position"], displayed) / 1000.0
		reachable = distance <= float(InventorySimulationSystem.WORLD_REACH_MILLIMETRES) / 1000.0
	var floor_ok: bool = valid_position and (mode == "freeform" or int(displayed[1]) == 0)
	var advisory: String = "Within estimated reach; clearance has not been checked."
	if not reachable: advisory = "Outside estimated 1.5 m reach; approach the target."
	if not floor_ok: advisory = "Floor placement requires Y=0; change Y or choose Freeform."
	if deployed: advisory = "Selected frame is deployed; pack it before placing again."
	if not exists: advisory = "Select a packed machine frame."
	if pending: advisory = "Waiting for host command result; target held at submitted coordinates."
	var size: Vector3 = held_size if pending and held_size != Vector3.ZERO else envelope(workshop, machine_id)
	var text: String = "%s\nFixed orientation · +X red / +Y up green / +Z blue" % machine_id
	if valid_position:
		text += "\n%s X %.2f / Y %.2f / Z %.2f m · distance %.2f m\n%s" % ["Selected" if deployed and not pending else "Target", float(displayed[0]) / 1000.0, float(displayed[1]) / 1000.0, float(displayed[2]) / 1000.0, distance, advisory]
	text += "\nServer envelope %.2f × %.2f × %.2f m (X/Y/Z).\nIncludes empty/broken mounts and retained sockets.\nAdvisory only; host decides overlap, ownership, hands and revision." % [size.x, size.y, size.z]
	return {
		"selected_id": machine_id if exists else "",
		"selected_position": placements.get(machine_id, {}).get("position", []).duplicate() if exists else [],
		"ghost_visible": shown and exists and (pending or not deployed) and valid_position,
		"position": coords.duplicate(), "size": size, "selected_size": envelope(workshop, machine_id), "machine_envelope": true,
		"pending": pending, "advisory_ok": reachable and floor_ok, "text": text
	}
