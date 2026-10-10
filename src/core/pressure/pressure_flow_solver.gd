extends RefCounted
class_name PressureFlowSolver

## Calculates isothermal flow between two fixed-volume gas compartments.
## Conductance is mol/(s*kPa); transferred matter is conserved between both volumes.

const EQUILIBRIUM_EPSILON_KPA: float = 0.001


static func calculate_transfer(
	first: PressureVolumeState,
	second: PressureVolumeState,
	conductance_mol_per_second_kpa: float,
	delta_seconds: float
) -> GasTransferResult:
	if first == null or second == null or not first.is_valid() or not second.is_valid():
		return GasTransferResult.failure(&"invalid_pressure_volume", "Both pressure volumes must be valid.")
	if first.volume_id == second.volume_id:
		return GasTransferResult.failure(&"same_pressure_volume", "A gas transfer requires two distinct volumes.")
	if not is_finite(conductance_mol_per_second_kpa) or conductance_mol_per_second_kpa < 0.0:
		return GasTransferResult.failure(&"invalid_conductance", "Conductance must be finite and non-negative.")
	if not is_finite(delta_seconds) or delta_seconds <= 0.0:
		return GasTransferResult.failure(&"invalid_delta", "The simulation delta must be finite and greater than zero.")
	if not is_equal_approx(first.temperature_kelvin, second.temperature_kelvin):
		return GasTransferResult.failure(&"temperature_model_mismatch", "This solver requires equal compartment temperatures.")
	if conductance_mol_per_second_kpa == 0.0:
		return GasTransferResult.no_transfer()

	var first_pressure_kpa: float = first.pressure_kpa()
	var second_pressure_kpa: float = second.pressure_kpa()
	var pressure_difference_kpa: float = absf(first_pressure_kpa - second_pressure_kpa)
	if pressure_difference_kpa <= EQUILIBRIUM_EPSILON_KPA:
		return GasTransferResult.no_transfer()

	var source: PressureVolumeState = first if first_pressure_kpa > second_pressure_kpa else second
	var receiver: PressureVolumeState = second if source == first else first
	var total_moles: float = first.gas_moles + second.gas_moles
	var total_volume_m3: float = first.volume_m3 + second.volume_m3
	var equilibrium_pressure_kpa: float = (
		total_moles
		* PressureVolumeState.GAS_CONSTANT_J_PER_MOL_K
		* first.temperature_kelvin
		/ total_volume_m3
		/ 1000.0
	)
	var equilibrium_source_moles: float = (
		equilibrium_pressure_kpa
		* source.volume_m3
		* 1000.0
		/ (PressureVolumeState.GAS_CONSTANT_J_PER_MOL_K * source.temperature_kelvin)
	)
	var maximum_transfer_moles: float = maxf(source.gas_moles - equilibrium_source_moles, 0.0)
	var requested_transfer_moles: float = pressure_difference_kpa * conductance_mol_per_second_kpa * delta_seconds
	var transferred_moles: float = minf(requested_transfer_moles, maximum_transfer_moles)
	if transferred_moles <= 0.0:
		return GasTransferResult.no_transfer()

	return GasTransferResult.transfer(source.volume_id, receiver.volume_id, transferred_moles)
