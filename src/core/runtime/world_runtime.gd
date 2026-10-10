extends Node
class_name WorldRuntime

## Composition root for one active local or dedicated simulation region.
## Hosting mode changes deployment configuration, not world-system contracts.

signal command_completed(command: SimulationCommand, result: ServiceResult)

const PROTOTYPE_AIRLOCK_ID: StringName = &"habitat_airlock"
const DEFAULT_WORLD_ID: StringName = &"development-world"
const DEFAULT_REGION_ID: StringName = &"local-habitat"

@export var world_id: StringName = DEFAULT_WORLD_ID
@export var region_id: StringName = DEFAULT_REGION_ID
var _simulation_runner: SimulationRunner
var _local_request_sequence: int = 0
var _control_setup_result: ServiceResult
var _inventory_setup_result: ServiceResult


func _ready() -> void:
	_simulation_runner = SimulationRunner.new()
	_simulation_runner.name = "SimulationRunner"
	var pressure_system := PressureSystem.new()
	pressure_system.name = "PressureSystem"
	_simulation_runner.add_child(pressure_system)
	var access_control_system := AccessControlSystem.new()
	access_control_system.name = "AccessControlSystem"
	_simulation_runner.add_child(access_control_system)
	var control_system := MachineControlSystem.new()
	control_system.name = "MachineControlSystem"
	_control_setup_result = control_system.configure(access_control_system)
	_simulation_runner.add_child(control_system)
	var inventory_system := InventorySimulationSystem.new()
	inventory_system.name = "InventorySimulationSystem"
	_inventory_setup_result = inventory_system.configure_defaults()
	_simulation_runner.add_child(inventory_system)
	_simulation_runner.external_command_completed.connect(_on_external_command_completed)
	add_child(_simulation_runner)


func start_simulation() -> ServiceResult:
	if _inventory_setup_result == null or not _inventory_setup_result.is_success:
		return ServiceResult.failure(&"inventory_setup_failed", "Inventory catalogs and fixtures must initialize before starting.")
	if _control_setup_result == null or not _control_setup_result.is_success:
		return ServiceResult.failure(&"control_setup_failed", "Control catalogs and bindings must initialize before the world starts.")
	if _simulation_runner == null:
		return ServiceResult.failure(&"runtime_not_ready", "The world runtime is not ready to start simulation.")
	return _simulation_runner.start_simulation()


func stop_simulation() -> void:
	if _simulation_runner != null:
		_simulation_runner.stop_simulation()


func get_simulation_system(system_id: StringName) -> SimulationSystem:
	if _simulation_runner == null:
		return null
	return _simulation_runner.get_system(system_id)


func enqueue_command(command: SimulationCommand) -> ServiceResult:
	if _simulation_runner == null:
		return ServiceResult.failure(&"runtime_not_ready", "The world runtime is not ready to accept commands.")
	return _simulation_runner.enqueue_external_command(command)


func next_local_request_id() -> StringName:
	_local_request_sequence += 1
	return StringName("local-%d" % _local_request_sequence)


func current_tick_number() -> int:
	return _simulation_runner.tick_number if _simulation_runner != null else 0


func configure_profile_history(enabled: bool, capacity: int = 120) -> ServiceResult:
	if _simulation_runner == null:
		return ServiceResult.failure(&"runtime_not_ready", "Initialize the world before configuring profiling.")
	return _simulation_runner.configure_profile_history(enabled, capacity)


func profiling_snapshot() -> Dictionary:
	return _simulation_runner.profiling_snapshot() if _simulation_runner != null else {}


func profiling_history(limit: int = 120) -> Dictionary:
	return _simulation_runner.profiling_history(limit) if _simulation_runner != null else {}


## Produces detached telemetry for an asynchronous exporter; performs no I/O.
func capture_profiling(limit: int = 120) -> ServiceResult:
	if _simulation_runner == null:
		return ServiceResult.failure(&"runtime_not_ready", "Initialize the world before capturing profiling.")
	if String(world_id).strip_edges().is_empty() or String(region_id).strip_edges().is_empty():
		return ServiceResult.failure(&"invalid_profile_identity", "Profiling captures require world and region IDs.")
	var result: ServiceResult = _simulation_runner.capture_profiling(limit)
	if not result.is_success:
		return result
	var capture: Dictionary = result.value
	capture["schema_version"] = 1
	capture["world_id"] = String(world_id)
	capture["region_id"] = String(region_id)
	return ServiceResult.success(capture)


func capture_profiling_json(limit: int = 120) -> ServiceResult:
	var capture: ServiceResult = capture_profiling(limit)
	if not capture.is_success:
		return capture
	return ServiceResult.success(JSON.stringify(capture.value, "", true, true))


func pressure_snapshot(airlock_id: StringName = PROTOTYPE_AIRLOCK_ID) -> ServiceResult:
	var pressure_system := get_simulation_system(PressureSystem.SYSTEM_ID) as PressureSystem
	if pressure_system == null:
		return ServiceResult.failure(&"pressure_system_unavailable", "The pressure system is unavailable.")
	var pressure_result: ServiceResult = pressure_system.airlock_snapshot(airlock_id)
	if not pressure_result.is_success:
		return pressure_result
	var access_system := get_simulation_system(AccessControlSystem.SYSTEM_ID) as AccessControlSystem
	if access_system == null:
		return pressure_result
	var access_result: ServiceResult = access_system.device_snapshot(airlock_id)
	if access_result.is_success:
		var snapshot: Dictionary = pressure_result.value
		snapshot["access_control"] = access_result.value
		return ServiceResult.success(snapshot)
	return pressure_result


## Captures domain records tagged with this runtime's world and region identity.
func capture_world_snapshot() -> ServiceResult:
	if _simulation_runner == null:
		return ServiceResult.failure(&"runtime_not_ready", "The world runtime is not ready to capture a snapshot.")
	if String(world_id).strip_edges().is_empty() or String(region_id).strip_edges().is_empty():
		return ServiceResult.failure(&"invalid_world_identity", "World and region IDs must be set before capturing a snapshot.")

	var simulation_state: ServiceResult = _simulation_runner.capture_snapshot()
	if not simulation_state.is_success:
		return simulation_state
	var state: Dictionary = simulation_state.value
	var link_validation: ServiceResult = _validate_cross_system_state(state["systems"], state["tick_number"])
	if not link_validation.is_success:
		return link_validation
	var snapshot := WorldSnapshot.new(world_id, region_id, state["tick_number"], state["systems"])
	return ServiceResult.success(snapshot)


## Produces versioned JSON for an asynchronous persistence adapter to store.
func capture_world_snapshot_json() -> ServiceResult:
	var result: ServiceResult = capture_world_snapshot()
	if not result.is_success:
		return result
	var snapshot: WorldSnapshot = result.value
	return ServiceResult.success(snapshot.to_json())


## Restores matching world state before simulation has started; performs no storage I/O.
func restore_world_snapshot(snapshot: WorldSnapshot) -> ServiceResult:
	if _simulation_runner == null:
		return ServiceResult.failure(&"runtime_not_ready", "The world runtime is not ready to restore a snapshot.")
	if snapshot == null:
		return ServiceResult.failure(&"invalid_world_snapshot", "A world snapshot is required.")
	if snapshot.world_id != world_id or snapshot.region_id != region_id:
		return ServiceResult.failure(&"world_snapshot_identity_mismatch", "The snapshot belongs to a different world or region.")

	var validated: ServiceResult = WorldSnapshot.from_dictionary(snapshot.to_dictionary())
	if not validated.is_success:
		return validated
	var normalized: WorldSnapshot = validated.value
	var system_records: Dictionary = normalized.systems.duplicate(true)
	if not system_records.has("access_control"):
		var pressure_record: Variant = system_records.get("pressure")
		var access_system := get_simulation_system(AccessControlSystem.SYSTEM_ID) as AccessControlSystem
		if typeof(pressure_record) != TYPE_DICTIONARY or access_system == null:
			return ServiceResult.failure(&"legacy_snapshot_migration_failed", "A legacy world snapshot lacks pressure data needed to initialize access-control state.")
		var migration: ServiceResult = access_system.migrate_legacy_pressure_snapshot(pressure_record)
		if not migration.is_success:
			return migration
		system_records["access_control"] = migration.value
	if not system_records.has("machine_control"):
		var controls := get_simulation_system(MachineControlSystem.SYSTEM_ID) as MachineControlSystem
		if controls == null:
			return ServiceResult.failure(&"control_system_missing", "Control migration requires an initialized control system.")
		var migration: ServiceResult = controls.migrate_legacy_snapshot(normalized.tick_number)
		if not migration.is_success:
			return migration
		system_records["machine_control"] = migration.value
	if not system_records.has("inventory"):
		var inventory := get_simulation_system(InventorySimulationSystem.SYSTEM_ID) as InventorySimulationSystem
		if inventory == null:
			return ServiceResult.failure(&"inventory_system_missing", "Legacy migration requires initialized inventory catalogs.")
		system_records["inventory"] = inventory.legacy_empty_snapshot(normalized.tick_number)
	var link_validation: ServiceResult = _validate_cross_system_state(system_records, normalized.tick_number)
	if not link_validation.is_success:
		return link_validation
	return _simulation_runner.restore_snapshot(normalized.tick_number, system_records)


## Decodes and restores a snapshot before the runner starts.
func restore_world_snapshot_json(json_text: String) -> ServiceResult:
	var parsed: ServiceResult = WorldSnapshot.from_json(json_text)
	if not parsed.is_success:
		return parsed
	return restore_world_snapshot(parsed.value)


func _on_external_command_completed(command: SimulationCommand, result: ServiceResult) -> void:
	command_completed.emit(command, result)


func _validate_cross_system_state(system_records: Dictionary, snapshot_tick_number: int) -> ServiceResult:
	var access_system := get_simulation_system(AccessControlSystem.SYSTEM_ID) as AccessControlSystem
	if access_system == null or not system_records.has("access_control"):
		return ServiceResult.failure(&"access_system_missing", "World snapshots must include the access-control system.")
	var pressure_record: Variant = system_records.get("pressure")
	var access_record: Variant = system_records.get("access_control")
	if typeof(pressure_record) != TYPE_DICTIONARY or typeof(access_record) != TYPE_DICTIONARY:
		return ServiceResult.failure(&"invalid_cross_system_state", "Pressure and access-control system records must be objects.")
	var pressure_links: ServiceResult = access_system.validate_pressure_links(pressure_record, access_record, snapshot_tick_number)
	if not pressure_links.is_success:
		return pressure_links
	var controls := get_simulation_system(MachineControlSystem.SYSTEM_ID) as MachineControlSystem
	if controls == null or not system_records.has("machine_control"):
		return ServiceResult.failure(&"control_system_missing", "World snapshots require machine-control state.")
	var control_record: Variant = system_records["machine_control"]
	if typeof(control_record) != TYPE_DICTIONARY:
		return ServiceResult.failure(&"invalid_control_state", "Machine-control snapshots must contain a record object.")
	return controls.validate_access_links(access_record, control_record)
