extends RefCounted
class_name LocomotionEnvironmentPolicy

## Pure local-frame gravity and equipment assessment; no forces or resource consumption.
const MAX_ACCELERATION: int = 100000


static func resolve(environment: Dictionary, equipment: Dictionary) -> ServiceResult:
	var validated: ServiceResult = validate_environment(environment)
	if not validated.is_success:
		return validated
	var fields := PackedStringArray(["surface_contact", "magnetic_surface", "mag_boots_enabled", "mag_boots_powered", "mag_boots_condition_permille", "jetpack_enabled", "jetpack_powered", "jetpack_condition_permille", "propellant_milligrams"])
	if not ControlContractValidation.has_exact_fields(equipment, fields):
		return _failure("Complete trusted equipment and contact observations are required.")
	for field in ["surface_contact", "magnetic_surface", "mag_boots_enabled", "mag_boots_powered", "jetpack_enabled", "jetpack_powered"]:
		if typeof(equipment[field]) != TYPE_BOOL:
			return _failure("Contact and equipment conditions must be boolean.")
	for field in ["mag_boots_condition_permille", "jetpack_condition_permille"]:
		if not ControlContractValidation.is_integer(equipment[field], 0, 1000):
			return _failure("Equipment condition must be integral permille.")
	if not ControlContractValidation.is_integer(equipment["propellant_milligrams"], 0, 9007199254740990):
		return _failure("Propellant must be a bounded non-negative mass.")
	var acceleration: Array = [0, 0, 0]
	var source: String = "none"
	var generator_id: String = ""
	if not environment["frame_in_freefall"] and _nonzero(environment["natural_acceleration_mm_s2"]):
		var natural: Array = environment["natural_acceleration_mm_s2"]
		acceleration = [int(natural[0]), int(natural[1]), int(natural[2])]
		source = "natural"
	else:
		var selected: Dictionary = {}
		for generator in environment["generators"]:
			if not generator["enabled"] or not generator["powered"] or not generator["inside_field"] or int(generator["condition_permille"]) == 0 or not _nonzero(generator["acceleration_mm_s2"]):
				continue
			if selected.is_empty() or int(generator["priority"]) > int(selected["priority"]) or (int(generator["priority"]) == int(selected["priority"]) and generator["generator_id"] < selected["generator_id"]):
				selected = generator
		if not selected.is_empty():
			for index in range(3):
				acceleration[index] = int(float(selected["acceleration_mm_s2"][index]) * float(selected["condition_permille"]) / 1000.0)
			if _nonzero(acceleration):
				source = "generated"
				generator_id = selected["generator_id"]
	var boots: bool = equipment["surface_contact"] and equipment["magnetic_surface"] and equipment["mag_boots_enabled"] and equipment["mag_boots_powered"] and int(equipment["mag_boots_condition_permille"]) > 0
	var thrust: bool = equipment["jetpack_enabled"] and equipment["jetpack_powered"] and int(equipment["jetpack_condition_permille"]) > 0 and int(equipment["propellant_milligrams"]) > 0
	var mode: String = "magnetic_attachment" if boots else ("gravity_supported" if source != "none" and equipment["surface_contact"] else "free_motion")
	return ServiceResult.success({"schema_version": 1, "frame_id": environment["frame_id"], "gravity_source": source, "generator_id": generator_id,
		"acceleration_mm_s2": acceleration, "locomotion_mode": mode, "magnetic_attachment_available": boots, "jetpack_thrust_available": thrust})


static func validate_environment(record: Dictionary) -> ServiceResult:
	var fields := PackedStringArray(["schema_version", "frame_id", "frame_in_freefall", "natural_acceleration_mm_s2", "generators"])
	if not ControlContractValidation.has_exact_fields(record, fields) or not ControlContractValidation.is_integer(record.get("schema_version"), 1, 1) or not ControlContractValidation.is_id(record.get("frame_id")) or typeof(record.get("frame_in_freefall")) != TYPE_BOOL or not _vector(record.get("natural_acceleration_mm_s2")) or typeof(record.get("generators")) != TYPE_ARRAY or record["generators"].size() > 16:
		return _failure("A complete bounded local-frame gravity observation is required.")
	var ids: Dictionary = {}
	for raw in record["generators"]:
		if typeof(raw) != TYPE_DICTIONARY or not ControlContractValidation.has_exact_fields(raw, PackedStringArray(["generator_id", "enabled", "powered", "inside_field", "condition_permille", "priority", "acceleration_mm_s2"])) or not ControlContractValidation.is_id(raw.get("generator_id")) or ids.has(raw["generator_id"]) or not ControlContractValidation.is_integer(raw.get("condition_permille"), 0, 1000) or not ControlContractValidation.is_integer(raw.get("priority"), 0, 255) or not _vector(raw.get("acceleration_mm_s2")):
			return _failure("Generator fields require unique identity and bounded quantities.")
		for field in ["enabled", "powered", "inside_field"]:
			if typeof(raw[field]) != TYPE_BOOL:
				return _failure("Generator availability must be boolean.")
		ids[raw["generator_id"]] = true
	return ServiceResult.success()


static func _vector(value: Variant) -> bool:
	if typeof(value) != TYPE_ARRAY or value.size() != 3:
		return false
	for coordinate in value:
		if not ControlContractValidation.is_integer(coordinate, -MAX_ACCELERATION, MAX_ACCELERATION):
			return false
	return true


static func _nonzero(value: Array) -> bool:
	return int(value[0]) != 0 or int(value[1]) != 0 or int(value[2]) != 0


static func _failure(message: String) -> ServiceResult:
	return ServiceResult.failure(&"invalid_locomotion_environment", message)
