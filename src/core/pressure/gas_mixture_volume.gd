extends RefCounted
class_name GasMixtureVolume

## Species-aware isothermal foundation. Canonical quantities are integer micromoles.
const MAX_EXACT_INTEGER: int = 9007199254740990
const SPECIES: Array[String] = ["gas.oxygen", "gas.nitrogen", "gas.carbon_dioxide", "gas.argon"]
var _record: Dictionary = {}


func to_record() -> Dictionary:
	return _record.duplicate(true)


func total_micromoles() -> int:
	var total: int = 0
	for quantity in _record["species_micromoles"].values():
		total += int(quantity)
	return total


func pressure_kpa() -> float:
	return float(total_micromoles()) / 1000000.0 * PressureVolumeState.GAS_CONSTANT_J_PER_MOL_K * float(_record["temperature_kelvin"]) / float(_record["volume_m3"]) / 1000.0


func partial_pressure_kpa(species_id: String) -> float:
	return float(_record["species_micromoles"].get(species_id, 0)) / 1000000.0 * PressureVolumeState.GAS_CONSTANT_J_PER_MOL_K * float(_record["temperature_kelvin"]) / float(_record["volume_m3"]) / 1000.0


## Exact constituent apportionment without multiplying two large int64 quantities.
## Plans never mutate either volume; a future owner must commit both revisions together.
func plan_transfer(destination: GasMixtureVolume, amount_micromoles: int, maximum_destination_kpa: float) -> ServiceResult:
	if destination == null or destination._record["volume_id"] == _record["volume_id"] or amount_micromoles <= 0 or amount_micromoles > total_micromoles() or not is_finite(maximum_destination_kpa) or maximum_destination_kpa <= 0.0:
		return _failure("A positive bounded transfer between distinct volumes and a pressure limit are required.")
	if _record["temperature_kelvin"] != destination._record["temperature_kelvin"]:
		return _failure("This prototype requires identical fixed temperatures.")
	if int(_record["state_revision"]) >= MAX_EXACT_INTEGER or int(destination._record["state_revision"]) >= MAX_EXACT_INTEGER or amount_micromoles > MAX_EXACT_INTEGER - destination.total_micromoles():
		return _failure("Transfer quantities or revisions would overflow.")
	var source_after: Dictionary = to_record()
	var destination_after: Dictionary = destination.to_record()
	var transferred: Dictionary = {}
	var remainders: Array = []
	var allocated: int = 0
	var total: int = total_micromoles()
	for id in SPECIES:
		var quantity: int = int(_record["species_micromoles"].get(id, 0))
		var divided: Array = _multiply_divide(quantity, amount_micromoles, total)
		transferred[id] = divided[0]
		allocated += int(divided[0])
		remainders.append({"id": id, "remainder": divided[1]})
	remainders.sort_custom(func(first: Dictionary, second: Dictionary) -> bool: return first["remainder"] > second["remainder"] or (first["remainder"] == second["remainder"] and first["id"] < second["id"]))
	for index in range(amount_micromoles - allocated):
		transferred[remainders[index]["id"]] += 1
	for id in SPECIES:
		source_after["species_micromoles"][id] = int(source_after["species_micromoles"].get(id, 0)) - int(transferred[id])
		destination_after["species_micromoles"][id] = int(destination_after["species_micromoles"].get(id, 0)) + int(transferred[id])
	source_after["state_revision"] = int(source_after["state_revision"]) + 1
	destination_after["state_revision"] = int(destination_after["state_revision"]) + 1
	var parsed: ServiceResult = from_record(destination_after)
	if not parsed.is_success or parsed.value.pressure_kpa() > maximum_destination_kpa:
		return _failure("The transfer would exceed destination pressure or quantity limits.")
	return ServiceResult.success({"schema_version": 1, "source_before": to_record(), "destination_before": destination.to_record(),
		"source_after": source_after, "destination_after": destination_after, "transferred_micromoles": transferred})


static func from_record(record: Dictionary) -> ServiceResult:
	var fields := PackedStringArray(["schema_version", "volume_id", "state_revision", "volume_m3", "temperature_kelvin", "species_micromoles"])
	if not ControlContractValidation.has_exact_fields(record, fields) or not ControlContractValidation.is_integer(record.get("schema_version"), 1, 1) or not ControlContractValidation.is_id(record.get("volume_id")) or not ControlContractValidation.is_integer(record.get("state_revision"), 0, MAX_EXACT_INTEGER):
		return _failure("A complete versioned mixture volume is required.")
	for field in ["volume_m3", "temperature_kelvin"]:
		if (typeof(record[field]) != TYPE_INT and typeof(record[field]) != TYPE_FLOAT) or not is_finite(float(record[field])) or float(record[field]) <= 0.0:
			return _failure("Volume and temperature must be positive finite quantities.")
	if float(record["volume_m3"]) < 0.000001 or float(record["volume_m3"]) > 1000000000.0 or float(record["temperature_kelvin"]) > 10000.0 or typeof(record["species_micromoles"]) != TYPE_DICTIONARY or record["species_micromoles"].size() > SPECIES.size():
		return _failure("Mixture volume, temperature or species count exceeds prototype bounds.")
	var total: int = 0
	for id in record["species_micromoles"]:
		if not SPECIES.has(id) or not ControlContractValidation.is_integer(record["species_micromoles"][id], 0, MAX_EXACT_INTEGER - total):
			return _failure("Species must be trusted with exact non-negative bounded quantities.")
		total += int(record["species_micromoles"][id])
	var volume := GasMixtureVolume.new()
	volume._record = record.duplicate(true)
	volume._record["state_revision"] = int(record["state_revision"])
	for id in volume._record["species_micromoles"]:
		volume._record["species_micromoles"][id] = int(volume._record["species_micromoles"][id])
	return ServiceResult.success(volume)


static func _multiply_divide(first: int, second: int, divisor: int) -> Array:
	var quotient: int = 0
	var remainder: int = 0
	for bit in range(53, -1, -1):
		quotient *= 2
		remainder = remainder * 2 + (first if ((second >> bit) & 1) == 1 else 0)
		quotient += remainder / divisor
		remainder %= divisor
	return [quotient, remainder]


static func _failure(message: String) -> ServiceResult:
	return ServiceResult.failure(&"invalid_gas_mixture", message)
