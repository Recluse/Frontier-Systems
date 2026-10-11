extends RefCounted
class_name WallPlacementFeedback

## Read-only floor-panel advice from scoped observations and volatile UI intent.
static func describe(record: Dictionary, plate_id: String, wall_id: String, coords: Array, turn: int, shown: bool, pending: Dictionary) -> Dictionary:
	var walls: Dictionary = record.get("production", {}).get("walls", {})
	var selected: Dictionary = walls.get(wall_id, {})
	var owned: bool = false
	for item in record.get("inventory", {}).get("items", []):
		if item["item_id"] == plate_id and item["definition_id"] == "item.plate.prototype":
			owned = true
	var building: bool = pending.get("operation", "") == "wall_build"
	var waiting: bool = not pending.is_empty()
	var valid_position: bool = InventorySpatialMath.is_position(coords)
	var floor_ok: bool = valid_position and int(coords[1]) == 0
	var grid_ok: bool = valid_position
	if valid_position:
		for coordinate in coords:
			if abs(int(coordinate)) > 100000 or int(coordinate) % 100 != 0: grid_ok = false
	var distance: float = 0.0
	var reachable: bool = false
	var advice_target: Array = selected.get("position", coords) if pending.get("operation", "") == "wall_remove" else coords
	if InventorySpatialMath.is_position(advice_target) and InventorySpatialMath.is_position(record.get("position", [])):
		distance = InventorySpatialMath.distance_millimetres(record["position"], advice_target) / 1000.0
		reachable = distance <= float(InventorySimulationSystem.WORLD_REACH_MILLIMETRES) / 1000.0
	var advisory: String = "Within estimated reach; host checks ownership, hands, revision and overlap."
	if not reachable: advisory = "Outside estimated 1.5 m reach; approach the target."
	if not grid_ok: advisory = "Wall coordinates require the 0.1 m grid within ±100 m."
	if not floor_ok: advisory = "Floor placement requires Y=0; walls have no Freeform mode."
	if not owned: advisory = "Select an owned physical plate in the module / canister selector."
	if waiting: advisory = "Waiting for host command result; target held at submitted coordinates."
	var text: String = "Wall along %s · 1 × 2 × 0.1 m · 0.1 m grid" % ("X" if turn == 0 else "Z")
	if valid_position:
		text += "\nTarget X %.2f / Y %.2f / Z %.2f m · distance %.2f m\n%s" % [float(coords[0]) / 1000.0, float(coords[1]) / 1000.0, float(coords[2]) / 1000.0, distance, advisory]
	if not selected.is_empty():
		text += "\nSelected wall %s · along %s · remove to recover a physical plate." % [wall_id, "X" if int(selected["quarter_turn"]) == 0 else "Z"]
	return {
		"selected_id": wall_id if not selected.is_empty() else "",
		"selected_position": selected.get("position", []).duplicate(),
		"selected_size": envelope(int(selected.get("quarter_turn", 0))),
		"ghost_visible": not record.is_empty() and shown and (owned or building) and valid_position and pending.get("operation", "") != "wall_remove",
		"position": coords.duplicate(), "size": envelope(turn),
		"pending": waiting, "advisory_ok": owned and reachable and floor_ok and grid_ok,
		"text": text if not record.is_empty() else "Wall observation unavailable."
	}


static func envelope(turn: int) -> Vector3:
	return SpatialWallConstruction.SIZE if turn == 0 else Vector3(SpatialWallConstruction.SIZE.z, SpatialWallConstruction.SIZE.y, SpatialWallConstruction.SIZE.x)
