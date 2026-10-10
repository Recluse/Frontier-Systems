extends RefCounted
class_name BodyInjuryState

## Human prototype anatomy. Severity is fictional integral permille, not hit energy.
const PARTS: Array[String] = ["head", "torso", "arm.left", "arm.right", "leg.left", "leg.right"]
const KINDS: Array[String] = ["blunt", "burn"]
const HEAD_CAUSE: String = "anatomy.head-trauma"
const OXYGEN_CAUSE: String = "anatomy.oxygen-injury"
var _record: Dictionary = {}


static func create(body_id: String) -> ServiceResult:
	var parts: Dictionary = {}
	for id in PARTS:
		parts[id] = {"blunt": 0, "burn": 0}
	return from_record({"schema_version": 1, "body_id": body_id, "state_revision": 0, "last_changed_tick": 0, "parts": parts, "oxygen_damage_permille": 0})


func to_record() -> Dictionary:
	return _record.duplicate(true)


## Separate accumulated oxygen injury from current breathing/oxygen delivery.
func consciousness_causes() -> Array:
	var causes: Array = []
	if int(_record["parts"]["head"]["blunt"]) > 0:
		causes.append({"cause_id": HEAD_CAUSE, "kind": "injury", "suppression_permille": _record["parts"]["head"]["blunt"]})
	if int(_record["oxygen_damage_permille"]) > 0:
		causes.append({"cause_id": OXYGEN_CAUSE, "kind": "injury", "suppression_permille": _record["oxygen_damage_permille"]})
	return causes


## Pure plan. Trusted injury/treatment adapters must authorize cause and resources.
func plan_change(operation: String, part_id: String, kind: String, amount: int, tick: int) -> ServiceResult:
	if operation not in ["damage", "heal"] or amount < 1 or amount > 1000 or tick <= int(_record["last_changed_tick"]) or tick > ConsciousnessState.MAX_INTEGER or int(_record["state_revision"]) >= ConsciousnessState.MAX_INTEGER:
		return ServiceResult.failure(&"invalid_injury_change", "A bounded fresh injury/treatment plan is required.")
	var systemic: bool = part_id == "systemic" and kind == "oxygen"
	if not systemic and (not PARTS.has(part_id) or not KINDS.has(kind)):
		return ServiceResult.failure(&"invalid_injury_target", "Select a registered part/kind or systemic oxygen injury.")
	var before: Dictionary = to_record()
	var after: Dictionary = before.duplicate(true)
	var current: int = before["oxygen_damage_permille"] if systemic else before["parts"][part_id][kind]
	var next: int = mini(1000, current + amount) if operation == "damage" else maxi(0, current - amount)
	if systemic:
		after["oxygen_damage_permille"] = next
	else:
		after["parts"][part_id][kind] = next
	after["state_revision"] = int(before["state_revision"]) + 1
	after["last_changed_tick"] = tick
	return ServiceResult.success({"before": before, "after": after, "applied_amount_permille": absi(next - current)})


static func from_record(record: Dictionary) -> ServiceResult:
	if not ControlContractValidation.has_exact_fields(record, PackedStringArray(["schema_version", "body_id", "state_revision", "last_changed_tick", "parts", "oxygen_damage_permille"])) or not ControlContractValidation.is_integer(record.get("schema_version"), 1, 1) or not ControlContractValidation.is_id(record.get("body_id")) or not ControlContractValidation.is_integer(record.get("state_revision"), 0, ConsciousnessState.MAX_INTEGER) or not ControlContractValidation.is_integer(record.get("last_changed_tick"), 0, ConsciousnessState.MAX_INTEGER) or not ControlContractValidation.is_integer(record.get("oxygen_damage_permille"), 0, 1000) or typeof(record.get("parts")) != TYPE_DICTIONARY or not ControlContractValidation.has_exact_fields(record["parts"], PackedStringArray(PARTS)):
		return ServiceResult.failure(&"invalid_body_injury", "Exact bounded anatomy/injury fields are required.")
	var normalized: Dictionary = record.duplicate(true)
	for field in ["schema_version", "state_revision", "last_changed_tick", "oxygen_damage_permille"]:
		normalized[field] = int(record[field])
	for id in PARTS:
		var values: Variant = record["parts"][id]
		if typeof(values) != TYPE_DICTIONARY or not ControlContractValidation.has_exact_fields(values, PackedStringArray(KINDS)):
			return ServiceResult.failure(&"invalid_part_injury", "Part injuries must declare the exact supported kinds.")
		for kind in KINDS:
			if not ControlContractValidation.is_integer(values[kind], 0, 1000):
				return ServiceResult.failure(&"invalid_part_injury", "Injury severity must be bounded integral permille.")
			normalized["parts"][id][kind] = int(values[kind])
	if normalized["state_revision"] == 0:
		if normalized["last_changed_tick"] != 0 or normalized["oxygen_damage_permille"] != 0:
			return ServiceResult.failure(&"invalid_body_injury", "Unchanged anatomy cannot contain prior injury.")
		for values in normalized["parts"].values():
			if values["blunt"] != 0 or values["burn"] != 0:
				return ServiceResult.failure(&"invalid_body_injury", "Unchanged anatomy starts healthy.")
	elif normalized["last_changed_tick"] == 0:
		return ServiceResult.failure(&"invalid_body_injury", "Changed anatomy requires a positive mutation tick.")
	var state := BodyInjuryState.new()
	state._record = normalized
	return ServiceResult.success(state)
