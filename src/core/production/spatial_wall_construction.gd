extends RefCounted
class_name SpatialWallConstruction

## Trusted prototype: one conserved physical plate becomes a floor-mounted panel.
const MAX_WALLS: int = 32
const MASS: int = 1000000
const SIZE: Vector3 = Vector3(1.0, 2.0, 0.1)
const BODY_HALF: Vector3 = Vector3(350, 900, 350)


static func valid_pose(record: Variant) -> bool:
	if typeof(record) != TYPE_DICTIONARY or not ControlContractValidation.has_exact_fields(record, PackedStringArray(["position", "quarter_turn"])) or not InventorySpatialMath.is_position(record.get("position")) or not ControlContractValidation.is_integer(record.get("quarter_turn"), 0, 1): return false
	if int(record["position"][1]) != 0: return false
	for coordinate in record["position"]:
		if abs(int(coordinate)) > 100000 or int(coordinate) % 100 != 0: return false
	return true


static func half_size(record: Dictionary) -> Vector3:
	return Vector3(500, 1000, 50) if int(record["quarter_turn"]) == 0 else Vector3(50, 1000, 500)


static func center(record: Dictionary) -> Vector3:
	return point(record["position"]) + Vector3(0, 1000, 0)


static func point(position: Array) -> Vector3:
	return Vector3(int(position[0]), int(position[1]), int(position[2]))


## Network poses are capsule centres; legacy logical fixtures use floor anchors.
static func body_center(position: Array) -> Vector3:
	var result: Vector3 = point(position)
	result.y = maxf(BODY_HALF.y, result.y)
	return result


static func overlaps(a: Vector3, a_half: Vector3, b: Vector3, b_half: Vector3) -> bool:
	var gap: Vector3 = (a - b).abs()
	var extent: Vector3 = a_half + b_half
	return gap.x < extent.x and gap.y < extent.y and gap.z < extent.z


static func valid(walls: Variant) -> bool:
	if typeof(walls) != TYPE_DICTIONARY or walls.size() > MAX_WALLS: return false
	var previous: Array = []
	for id in walls:
		if not ControlContractValidation.is_id(id) or not valid_pose(walls[id]): return false
		for other in previous:
			if overlaps(center(walls[id]), half_size(walls[id]), center(other), half_size(other)): return false
		previous.append(walls[id])
	return true


## Canonical prototype keepouts, independent of presentation/physics nodes.
static func scene_clear(walls: Dictionary, machinery: Dictionary, inventory: Dictionary) -> bool:
	for wall in walls.values():
		var origin: Vector3 = center(wall)
		var half: Vector3 = half_size(wall)
		if not fixture_clear(origin, half): return false
		for placement in machinery["placements"].values():
			if overlaps(origin, half, point(placement["position"]) + Vector3(0, 750, 0), Vector3(650, 750, 650)): return false
		for body in inventory["bodies"]:
			if overlaps(origin, half, body_center(body["position_millimetres"]), BODY_HALF): return false
	return true


## Shared trusted fixture keepouts in millimetres; face contact is permitted.
static func fixture_clear(origin: Vector3, half: Vector3) -> bool:
	if overlaps(origin, half, Vector3(0, 850, 1000), Vector3(1750, 1000, 500)): return false
	for source in ProductionSimulationSystem.SOURCE_POSITIONS.values():
		if overlaps(origin, half, point(source) + Vector3(0, 250, 0), Vector3(300, 250, 300)): return false
	return true


## Swept body AABB avoids tunnelling through thin panels in network pose updates.
static func motion_clear(walls: Dictionary, from: Array, to: Array) -> bool:
	var start: Vector3 = body_center(from)
	var delta: Vector3 = body_center(to) - start
	for wall in walls.values():
		var low: Vector3 = center(wall) - half_size(wall) - BODY_HALF
		var high: Vector3 = center(wall) + half_size(wall) + BODY_HALF
		var enter: float = 0.0
		var leave: float = 1.0
		var intersecting: bool = true
		for axis in range(3):
			if delta[axis] == 0:
				if start[axis] <= low[axis] or start[axis] >= high[axis]: intersecting = false
			else:
				var first: float = (low[axis] - start[axis]) / delta[axis]
				var second: float = (high[axis] - start[axis]) / delta[axis]
				enter = maxf(enter, minf(first, second))
				leave = minf(leave, maxf(first, second))
		if intersecting and enter < leave: return false
	return true


static func plan(production: ProductionSimulationSystem, state: Dictionary, inventory: InventorySimulationSystem, context: AuthenticatedCommandContext, request: String, operation: String, payload: Dictionary) -> ServiceResult:
	var create: bool = operation == "wall_build"
	var fields: Array = ["expected_revision", "item_id", "position", "quarter_turn"] if create else ["expected_revision", "wall_id"]
	if not ControlContractValidation.has_exact_fields(payload, PackedStringArray(fields)): return failure("An exact wall construction intent is required.")
	if not ControlContractValidation.is_id(payload.get("item_id" if create else "wall_id")): return failure("Select a valid physical plate or wall ID.")
	var walls: Dictionary = state["walls"]
	var wall_id: String = "wall-%s" % request.sha256_text().substr(0, 24) if create else String(payload.get("wall_id", ""))
	var plate_id: String = String(payload.get("item_id", "")) if create else "plate-%s" % request.sha256_text().substr(0, 24)
	if not ControlContractValidation.is_id(wall_id) or not ControlContractValidation.is_id(plate_id): return failure("Select a stable physical plate or wall identity.")
	var pose: Dictionary
	if create:
		pose = {"position": payload["position"], "quarter_turn": payload["quarter_turn"]}
		if not valid_pose(pose) or walls.size() >= MAX_WALLS or walls.has(wall_id): return failure("Place a floor wall on the 0.1 m grid with a supported orientation and registry capacity.")
		if not state["cargo"].has(plate_id) or int(state["cargo"][plate_id]["plate"]) != MASS or ProductionSimulationSystem._mass(state["cargo"][plate_id]) != MASS: return failure("Construction consumes one owned physical kilogram plate.")
	else:
		if not walls.has(wall_id) or state["cargo"].size() >= 32: return failure("Select an existing wall; physical plate registry capacity is required for recovery.")
		pose = walls[wall_id]
	var reach: ServiceResult = inventory.production_capability(context, true, pose["position"])
	if not reach.is_success: return reach
	if create:
		walls[wall_id] = {"position": InventorySpatialMath.normalized(pose["position"]), "quarter_turn": int(pose["quarter_turn"])}
		if not valid(walls) or not scene_clear(walls, state["machinery"], inventory.capture_snapshot().value): return failure("The wall overlaps a panel, player, deployed machine or production fixture.")
		if not MachineryPlacement.walls_clear({wall_id: walls[wall_id]}, state["machinery"]): return failure("The wall overlaps an expanded deployed machine.")
		state["cargo"].erase(plate_id)
	else:
		walls.erase(wall_id)
		var stock: Dictionary = {}
		for material in state["store"]: stock[material] = 0
		stock["plate"] = MASS
		state["cargo"][plate_id] = stock
	return inventory.prepare_plate_change(context, "wall-factory-%s" % request.sha256_text().substr(0, 24), plate_id, not create, production.payload_masses(state))


static func failure(message: String) -> ServiceResult:
	return ServiceResult.failure(&"wall_construction_denied", message)
