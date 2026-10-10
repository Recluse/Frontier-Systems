extends SceneTree

var _failures: int = 0


func _initialize() -> void:
	var volumes: Dictionary = {}
	for name in ["habitat-air", "oxygen-tank", "airlock-vacuum"]:
		var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/pressure/mixtures/%s.v1.json" % name))
		var parsed: ServiceResult = GasMixtureVolume.from_record(record)
		_check(parsed.is_success, "gas fixture must validate: " + name)
		if parsed.is_success:
			volumes[name] = parsed.value
	if volumes.size() != 3:
		quit(1)
		return
	var air: GasMixtureVolume = volumes["habitat-air"]
	var tank: GasMixtureVolume = volumes["oxygen-tank"]
	var chamber: GasMixtureVolume = volumes["airlock-vacuum"]
	_check(PrototypeBreathingPolicy.assess(air).value["prototype_breathing_compatible"], "prototype mixture must pass its fictional envelope")
	_check(not PrototypeBreathingPolicy.assess(tank).value["prototype_breathing_compatible"], "compressed oxygen must not be treated as a direct breathing volume")
	_check(not PrototypeBreathingPolicy.assess(chamber).value["prototype_breathing_compatible"], "vacuum must reject breathing")
	var before: Dictionary = air.to_record()
	var plan: ServiceResult = air.plan_transfer(chamber, 1000001, 150.0)
	_check(plan.is_success, "mixture transfer must plan")
	if not plan.is_success:
		quit(1)
		return
	var total: int = 0
	for id in GasMixtureVolume.SPECIES:
		total += int(plan.value["transferred_micromoles"][id])
		_check(int(plan.value["source_after"]["species_micromoles"][id]) + int(plan.value["destination_after"]["species_micromoles"][id]) == int(before["species_micromoles"].get(id, 0)), "each constituent must conserve exactly")
	_check(total == 1000001 and air.to_record() == before and chamber.total_micromoles() == 0, "transfer must conserve requested units without mutating volumes")
	_check(not tank.plan_transfer(chamber, 10000000, 20.0).is_success, "pressure limit must reject excessive regulated fill")
	var oxygen_plan: ServiceResult = tank.plan_transfer(chamber, 10000000, 30.0)
	_check(oxygen_plan.is_success, "bounded oxygen fill must plan")
	var regulated: GasMixtureVolume = GasMixtureVolume.from_record(oxygen_plan.value["destination_after"]).value
	var assessed: Dictionary = PrototypeBreathingPolicy.assess(regulated).value
	_check(assessed["prototype_breathing_compatible"] and assessed["hazards"].has("oxygen_enrichment_fire_risk") and assessed["hazards"].has("oxygen_exposure_monitor_required"), "low-pressure pure oxygen must retain its hazard flags")
	var invalid: Dictionary = before.duplicate(true)
	invalid["species_micromoles"]["gas.oxygen"] = 1.5
	_check(not GasMixtureVolume.from_record(invalid).is_success, "fractional micromoles must reject")
	invalid = before.duplicate(true)
	invalid["species_micromoles"]["unregistered-gas"] = 1
	_check(not GasMixtureVolume.from_record(invalid).is_success, "unregistered gas must reject")
	invalid = before.duplicate(true)
	invalid["temperature_kelvin"] = 250.0
	var cold: GasMixtureVolume = GasMixtureVolume.from_record(invalid).value
	_check(not cold.plan_transfer(chamber, 1, 150.0).is_success, "different temperature needs a thermal solver")
	var large_record := {"schema_version": 1, "volume_id": "large", "state_revision": 0, "volume_m3": 1.0, "temperature_kelvin": 293.15,
		"species_micromoles": {"gas.oxygen": 1, "gas.nitrogen": GasMixtureVolume.MAX_EXACT_INTEGER - 1}}
	var large: GasMixtureVolume = GasMixtureVolume.from_record(large_record).value
	var large_plan: ServiceResult = large.plan_transfer(chamber, GasMixtureVolume.MAX_EXACT_INTEGER - 1, 1.0e25)
	_check(large_plan.is_success, "large exact apportionment must avoid multiplying into int64 overflow")
	var received: GasMixtureVolume = GasMixtureVolume.from_record(large_plan.value["destination_after"]).value
	_check(received.total_micromoles() == GasMixtureVolume.MAX_EXACT_INTEGER - 1, "large transfer must preserve exact total")
	_check(GasMixtureVolume.from_record(JSON.parse_string(JSON.stringify(plan.value["source_after"]))).is_success, "species records must recover through JSON")
	if _failures == 0:
		print("Gas mixture conservation and prototype breathing scenarios passed.")
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
