extends RefCounted
class_name WallPlacementFeedback

## Read-only floor-panel advice from scoped observations and volatile UI intent.
static func describe(record: Dictionary, plate_id: String, wall_id: String, coords: Array, turn: int, shown: bool, pending: Dictionary) -> Dictionary:
	var walls: Dictionary = record.get("production", {}).get("walls", {})
	var removing: bool = pending.get("operation", "") == "wall_remove"
	var selected: Dictionary = pending if removing else walls.get(wall_id, {})
	var selected_id: String = String(pending.get("wall_id", wall_id)) if removing else wall_id
	var owned: bool = false
	for item in record.get("inventory", {}).get("items", []):
		if item["item_id"] == plate_id and item["definition_id"] == "item.plate.prototype": owned = true
	var building: bool = pending.get("operation", "") == "wall_build"
	var waiting: bool = not pending.is_empty()
	var selecting: bool = removing or (not selected.is_empty() and not shown and not building)
	var displayed: Array = selected.get("position", []) if selecting else coords
	var displayed_turn: int = int(selected.get("quarter_turn", 0)) if selecting else turn
	var valid_position: bool = InventorySpatialMath.is_position(displayed)
	var floor_ok: bool = valid_position and int(displayed[1]) == 0
	var grid_ok: bool = valid_position
	if valid_position:
		for coordinate in displayed:
			if abs(int(coordinate)) > 100000 or int(coordinate) % 100 != 0: grid_ok = false
	var distance: float = 0.0
	var reach_known: bool = valid_position and InventorySpatialMath.is_position(record.get("position", []))
	var reachable: bool = false
	if reach_known:
		distance = InventorySpatialMath.distance_millimetres(record["position"], displayed) / 1000.0
		reachable = distance <= float(InventorySimulationSystem.WORLD_REACH_MILLIMETRES) / 1000.0
	var advisory: String = "Within estimated 1.5 m reach."
	if not reachable: advisory = "Outside estimated 1.5 m reach; approach the target."
	if not reach_known: advisory = "Current reach unavailable; waiting for a scoped body observation."
	if not grid_ok: advisory = "Wall coordinates require the 0.1 m grid within ±100 m."
	if not floor_ok: advisory = "Floor placement requires Y=0; walls have no Freeform mode."
	if not owned and not selecting: advisory = "Select an owned physical plate in the module / canister selector."
	var text: String = "Wall along %s · 1 × 2 × 0.1 m · 0.1 m grid" % ("X" if displayed_turn == 0 else "Z")
	if valid_position:
		text += "\n%s X %.2f / Y %.2f / Z %.2f m" % ["Selected" if selecting else "Target", float(displayed[0]) / 1000.0, float(displayed[1]) / 1000.0, float(displayed[2]) / 1000.0]
		text += " · distance %.2f m" % distance if reach_known else ""
	text += "\n" + advisory
	if not selected.is_empty():
		text += "\n%s wall %s · along %s." % ["Pending removal of" if removing else "Selected", selected_id, "X" if int(selected.get("quarter_turn", 0)) == 0 else "Z"]
		text += "\nHost checks current wall, hands, revision, reach and carried capacity."
		text += "\nRemoval returns one physical plate only after host acceptance. Panels do not seal rooms."
	elif not wall_id.is_empty() and not shown:
		text += "\nWall %s is no longer observed; select a current wall." % wall_id
	else:
		text += "\nHost checks plate, hands, revision and overlap."
	if not selecting and (wall_id.is_empty() or shown or building):
		text = ("Pending wall placement" if building else "Unsubmitted wall preview") + " · along " + ("X" if turn == 0 else "Z") + " · 1 × 2 × 0.1 m"
		if valid_position: text += "\nDraft pose [X, Y, Z] %s mm · quarter-turn %d." % [str(displayed), displayed_turn]
		if not owned and not building: text += "\nSelect an owned physical plate in the module / canister selector."
		text += "\nGeometry only; reach, collision, capacity and acceptance are determined by the host."
		text += "\nFloor placement requires Y=0 on the 100 mm grid; walls have no Freeform mode."
	if waiting:
		text += "\nWaiting for host command result; submitted identity and pose held. No plate return confirmed."
	if record.is_empty() and not waiting: text = "Wall observation unavailable."
	return {
		"selected_id": selected_id if not selected.is_empty() else "",
		"selected_position": selected.get("position", []).duplicate() if not record.is_empty() else [],
		"selected_size": envelope(int(selected.get("quarter_turn", 0))),
		"ghost_visible": not record.is_empty() and shown and (owned or building) and valid_position and not removing,
		"position": coords.duplicate(), "size": envelope(turn), "wall_draft": true,
		"pending": waiting, "advisory_ok": selecting and reachable and floor_ok and grid_ok,
		"text": text
	}


## The command result is evidence of host acceptance, never a local matter grant.
static func removal_result(wall_id: String, result: ServiceResult) -> String:
	if result.is_success:
		return "Host accepted removal of wall %s; returned one physical plate to your inventory. Panels do not seal rooms." % wall_id
	if result.error_code == &"remote_disconnected":
		return "Wall %s removal outcome unconfirmed: host disconnected before acknowledgment. Check fresh wall and inventory observations after reconnecting; no plate return confirmed." % wall_id
	return "Host rejected removal of wall %s: %s. No plate return confirmed." % [wall_id, result.message.trim_suffix(".")]


static func envelope(turn: int) -> Vector3:
	return SpatialWallConstruction.SIZE if turn == 0 else Vector3(SpatialWallConstruction.SIZE.z, SpatialWallConstruction.SIZE.y, SpatialWallConstruction.SIZE.x)
