extends RefCounted
class_name PrototypeBreathingPolicy

## Fictional prototype envelope, not physiology or real-world breathing guidance.
static func assess(volume: GasMixtureVolume) -> ServiceResult:
	if volume == null:
		return ServiceResult.failure(&"missing_breathing_volume", "A validated local breathing volume is required.")
	var pressure: float = volume.pressure_kpa()
	var oxygen: float = volume.partial_pressure_kpa("gas.oxygen")
	var carbon_dioxide: float = volume.partial_pressure_kpa("gas.carbon_dioxide")
	var oxygen_fraction: float = oxygen / pressure if pressure > 0.0 else 0.0
	var hazards: Array[String] = []
	if pressure < 20.0: hazards.append("pressure_low")
	if pressure > 150.0: hazards.append("pressure_high")
	if oxygen < 15.0: hazards.append("oxygen_partial_pressure_low")
	if oxygen > 30.0: hazards.append("oxygen_partial_pressure_high")
	if carbon_dioxide > 1.0: hazards.append("carbon_dioxide_partial_pressure_high")
	var compatible: bool = hazards.is_empty()
	if oxygen_fraction > 0.3:
		hazards.append("oxygen_enrichment_fire_risk")
		hazards.append("oxygen_exposure_monitor_required")
	return ServiceResult.success({"schema_version": 1, "prototype_breathing_compatible": compatible, "pressure_kpa_absolute": pressure,
		"oxygen_partial_pressure_kpa": oxygen, "carbon_dioxide_partial_pressure_kpa": carbon_dioxide,
		"oxygen_fraction": oxygen_fraction, "hazards": hazards})
