extends RefCounted
class_name TerrainWorkTargetView

## Detached advisory text from an already authenticated terrain observation.
## Readiness is a prerequisite signal, never an operation approval or matter owner.
const CELL_IDS: Array[String] = ["terrain.dirt.source", "terrain.dirt.fill"]


static func describe(id: String, cell: Dictionary) -> String:
	var title := "Dirt source · dig target" if id == CELL_IDS[0] else "Dirt fill · fill target"
	var mass: int = int(cell["state"]["mass_milligrams"])
	var capacity: int = int(cell["capacity_milligrams"])
	var state := "Empty" if mass == 0 else "Partially filled"
	if id == CELL_IDS[0]:
		state = "Depleted" if mass == 0 else "Source contains matter"
	elif mass == capacity and capacity > 0:
		state = "Full"
	if capacity == 0:
		state = "Unavailable · no commissioned capacity"
	var readiness := "Host work prerequisites ready; command still validated"
	if not cell["work_ready"]:
		readiness = "Work unavailable: " + String(cell["work_message"])
	return "%s [%s]\n%s\nMass %s\nCapacity %s\n%s\nDig/fill in Terrain overlay · advisory cell marker" % [
		title, id, state, TerrainParcelLifecycleView.mass(mass),
		TerrainParcelLifecycleView.mass(capacity), readiness]


static func color(id: String, cell: Dictionary) -> Color:
	if int(cell["capacity_milligrams"]) == 0 or not cell["work_ready"]:
		return Color("#85858d")
	var mass: int = int(cell["state"]["mass_milligrams"])
	if (id == CELL_IDS[0] and mass == 0) or (id == CELL_IDS[1] and mass == int(cell["capacity_milligrams"])):
		return Color("#a98762")
	return Color("#bf935b") if id == CELL_IDS[0] else Color("#739bac")
