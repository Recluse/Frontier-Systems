extends SceneTree

var _failures: int = 0


func _initialize() -> void:
	var equipment := {"surface_contact": true, "magnetic_surface": true, "mag_boots_enabled": false, "mag_boots_powered": true,
		"mag_boots_condition_permille": 1000, "jetpack_enabled": false, "jetpack_powered": true, "jetpack_condition_permille": 1000, "propellant_milligrams": 1000}
	var fixtures: Dictionary = {}
	for name in ["mars-surface", "moon-surface", "station-space"]:
		var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/locomotion/%s.v1.json" % name))
		_check(LocomotionEnvironmentPolicy.validate_environment(record).is_success, "fixture must validate")
		fixtures[name] = record
	_check(LocomotionEnvironmentPolicy.resolve(fixtures["mars-surface"], equipment).value["gravity_source"] == "natural", "surface frame must use natural gravity")
	_check(LocomotionEnvironmentPolicy.resolve(fixtures["moon-surface"], equipment).value["acceleration_mm_s2"] == [0, -1620, 0], "moon fixture must retain its own gravity")
	var station: Dictionary = fixtures["station-space"].duplicate(true)
	_check(LocomotionEnvironmentPolicy.resolve(station, equipment).value["gravity_source"] == "generated", "space habitat must use a working generator")
	station["generators"][0]["condition_permille"] = 500
	_check(LocomotionEnvironmentPolicy.resolve(station, equipment).value["acceleration_mm_s2"] == [0, -4905, 0], "generator damage must degrade output")
	station["generators"][0]["powered"] = false
	var result: Dictionary = LocomotionEnvironmentPolicy.resolve(station, equipment).value
	_check(result["gravity_source"] == "none" and result["locomotion_mode"] == "free_motion", "generator outage must remove supported gravity")
	equipment["mag_boots_enabled"] = true
	result = LocomotionEnvironmentPolicy.resolve(station, equipment).value
	_check(result["locomotion_mode"] == "magnetic_attachment" and result["acceleration_mm_s2"] == [0, 0, 0], "boots must attach without generating gravity")
	equipment["magnetic_surface"] = false
	_check(not LocomotionEnvironmentPolicy.resolve(station, equipment).value["magnetic_attachment_available"], "boots must not attach to incompatible terrain")
	equipment["magnetic_surface"] = true
	equipment["surface_contact"] = false
	_check(not LocomotionEnvironmentPolicy.resolve(station, equipment).value["magnetic_attachment_available"], "boots must not attach in empty space")
	equipment["jetpack_enabled"] = true
	var before: Dictionary = equipment.duplicate(true)
	_check(LocomotionEnvironmentPolicy.resolve(station, equipment).value["jetpack_thrust_available"], "working fueled jetpack must provide propulsion availability")
	_check(equipment == before, "assessment must not consume or create propellant")
	equipment["propellant_milligrams"] = 0
	_check(not LocomotionEnvironmentPolicy.resolve(station, equipment).value["jetpack_thrust_available"], "empty propellant must disable thrust availability")
	station["natural_acceleration_mm_s2"] = [0, -3710, 0]
	_check(LocomotionEnvironmentPolicy.resolve(station, equipment).value["gravity_source"] == "none", "freefall local frame must not turn celestial acceleration into walking weight")
	station = fixtures["station-space"].duplicate(true)
	station["generators"][0]["inside_field"] = false
	_check(LocomotionEnvironmentPolicy.resolve(station, equipment).value["gravity_source"] == "none", "generator outside coverage must not affect this body")
	station = fixtures["station-space"].duplicate(true)
	var other: Dictionary = station["generators"][0].duplicate(true)
	other["generator_id"] = "generator.aaa"
	station["generators"].append(other)
	result = LocomotionEnvironmentPolicy.resolve(station, equipment).value
	_check(result["generator_id"] == "generator.aaa" and result["acceleration_mm_s2"] == [0, -9810, 0], "overlapping equal-priority generators must select deterministically without stacking")
	var invalid: Dictionary = station.duplicate(true)
	invalid["generators"].append(other.duplicate(true))
	_check(not LocomotionEnvironmentPolicy.validate_environment(invalid).is_success, "duplicate generators must reject")
	equipment["propellant_milligrams"] = -1
	_check(not LocomotionEnvironmentPolicy.resolve(station, equipment).is_success, "negative propellant must reject")
	if _failures == 0:
		print("Gravity generator and EVA locomotion policy scenarios passed.")
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
