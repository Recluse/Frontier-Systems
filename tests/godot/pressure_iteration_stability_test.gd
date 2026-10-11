extends SceneTree

## Accepted shared-volume topologies must advance identically after restore.
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func fixture(reverse: bool) -> PressureSystem:
	var pressure := PressureSystem.new()
	var extra := PressureVolumeState.from_pressure(&"other_chamber", 10.0, 293.15, 0.0)
	pressure.volumes[extra.volume_id] = extra
	pressure.sensors[&"other_sensor"] = PressureSensorState.new(&"other_sensor", extra.volume_id)
	var second := AirlockState.new(&"aaa_airlock", PressureSystem.PROTOTYPE_HABITAT_ID, extra.volume_id, PressureSystem.PROTOTYPE_EXTERIOR_ID)
	second.equalization_valve_open = true
	var first: AirlockState = pressure.airlocks[&"habitat_airlock"]
	first.equalization_valve_open = true
	pressure.airlocks.clear()
	if reverse:
		pressure.airlocks[second.airlock_id] = second
		pressure.airlocks[first.airlock_id] = first
	else:
		pressure.airlocks[first.airlock_id] = first
		pressure.airlocks[second.airlock_id] = second
	return pressure

func run() -> void:
	var original: PressureSystem = fixture(false)
	var reordered: PressureSystem = fixture(true)
	var restored := PressureSystem.new()
	var saved: Dictionary = original.capture_snapshot().value
	check(saved == reordered.capture_snapshot().value, "insertion order does not alter canonical snapshot")
	check(restored.restore_snapshot_record(saved, 0).is_success, "shared-volume topology is accepted by restore")
	var initial_moles: float = total_moles(original)
	for tick in range(1, 21):
		original.simulate_tick(tick, 1.0 / 60.0)
		reordered.simulate_tick(tick, 1.0 / 60.0)
		restored.simulate_tick(tick, 1.0 / 60.0)
		check(original.capture_snapshot().value == restored.capture_snapshot().value, "restored full state matches uninterrupted tick %d" % tick)
		check(original.capture_snapshot().value == reordered.capture_snapshot().value, "insertion order does not change tick %d" % tick)
	check(original.total_transferred_moles > 0.0, "test exercises actual gas flow")
	check(is_equal_approx(initial_moles, total_moles(original)), "stable ordering preserves conserved gas")
	original.free()
	reordered.free()
	restored.free()
	print("Pressure iteration stability: %d failures" % failures)
	quit(1 if failures else 0)

func total_moles(pressure: PressureSystem) -> float:
	var total: float = 0.0
	for volume in pressure.volumes.values(): total += volume.gas_moles
	return total
