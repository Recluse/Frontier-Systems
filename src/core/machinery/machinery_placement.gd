extends RefCounted
class_name MachineryPlacement

## Server-owned millimetre AABBs. Position is the bottom-centre in both floor and
## freeform modes. Reserve module/socket space even when empty, disabled or broken.
const HALF: Vector3 = Vector3(650, 750, 650)
const EXPANDED_HALF: Vector3 = Vector3(1250, 750, 650)


static func half_size(workshop: Dictionary, machine: String) -> Vector3:
	var sockets: int = 0
	for part in workshop["mounts"]:
		if workshop["mounts"][part] != machine: continue
		if workshop["parts"][part]["kind"] == "expander": return EXPANDED_HALF
		if workshop["parts"][part]["kind"] == "socket": sockets += 1
	# A removed expander can leave sockets fitted; their geometry remains present.
	return Vector3(maxi(int(HALF.x), sockets * 300 - 550), HALF.y, HALF.z)


static func center(position: Array) -> Vector3:
	return SpatialWallConstruction.point(position) + Vector3(0, HALF.y, 0)


## Check only the proposed machine. Old restored overlaps are grandfathered until
## packing/redeployment or envelope growth; unrelated legacy equipment is untouched.
static func clear(workshop: Dictionary, walls: Dictionary, inventory: Dictionary, machine: String, position: Array) -> bool:
	var origin: Vector3 = center(position)
	var half: Vector3 = half_size(workshop, machine)
	if not SpatialWallConstruction.fixture_clear(origin, half): return false
	for other in workshop["placements"]:
		if other == machine: continue
		if SpatialWallConstruction.overlaps(origin, half, center(workshop["placements"][other]["position"]), half_size(workshop, other)): return false
	for wall in walls.values():
		if SpatialWallConstruction.overlaps(origin, half, SpatialWallConstruction.center(wall), SpatialWallConstruction.half_size(wall)): return false
	for body in inventory["bodies"]:
		if SpatialWallConstruction.overlaps(origin, half, SpatialWallConstruction.body_center(body["position_millimetres"]), SpatialWallConstruction.BODY_HALF): return false
	return true


## New wall commands must also respect expanded machinery. Restore continues using
## its established wall validation envelope for compatibility with trusted saves.
static func walls_clear(walls: Dictionary, workshop: Dictionary) -> bool:
	for wall in walls.values():
		for machine in workshop["placements"]:
			if SpatialWallConstruction.overlaps(SpatialWallConstruction.center(wall), SpatialWallConstruction.half_size(wall), center(workshop["placements"][machine]["position"]), half_size(workshop, machine)): return false
	return true
