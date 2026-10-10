extends RefCounted
class_name MachineModuleSlotDefinition

## A host mounting interface. Occupancy belongs to the circuit's installed instance.

const SCHEMA_VERSION: int = 1

var slot_id: String = ""
var interface_id: String = ""
var capacity_units: int = 1
var allowed_module_families := PackedStringArray()


func to_record() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"slot_id": slot_id,
		"interface_id": interface_id,
		"capacity_units": capacity_units,
		"allowed_module_families": Array(allowed_module_families),
	}


## Physical fit only. Missing functional prerequisites do not prevent mounting.
## A universal family bay still requires the correct physical interface and size.
func accepts(module: MachineModuleDefinition) -> ServiceResult:
	if module == null:
		return ServiceResult.failure(&"missing_machine_module", "A module definition is required.")
	var slot_check: ServiceResult = from_record(to_record())
	if not slot_check.is_success:
		return slot_check
	var module_check: ServiceResult = MachineModuleDefinition.from_record(module.to_record())
	if not module_check.is_success:
		return module_check
	if interface_id != module.interface_id:
		return ServiceResult.failure(&"module_interface_mismatch", "The module and slot use different interface versions.")
	if not allowed_module_families.has("*") and not allowed_module_families.has(module.module_family):
		return ServiceResult.failure(&"module_family_mismatch", "The slot does not accept this module family.")
	if module.size_units > capacity_units:
		return ServiceResult.failure(&"module_capacity_exceeded", "The module exceeds the slot's size capacity.")
	return ServiceResult.success({"slot_id": slot_id, "definition_id": module.definition_id, "revision": module.revision})


## Reports dormant installations without rejecting a physically compatible module.
func evaluate_operability(module: MachineModuleDefinition, host_capabilities: PackedStringArray) -> ServiceResult:
	var fit: ServiceResult = accepts(module)
	if not fit.is_success:
		return fit
	var missing := PackedStringArray()
	for capability in module.required_host_capabilities:
		if not host_capabilities.has(capability):
			missing.append(capability)
	return ServiceResult.success({
		"slot_id": slot_id,
		"definition_id": module.definition_id,
		"operable": missing.is_empty(),
		"missing_host_capabilities": Array(missing),
	})


static func from_record(record: Dictionary) -> ServiceResult:
	var fields := PackedStringArray(["schema_version", "slot_id", "interface_id", "capacity_units", "allowed_module_families"])
	if not ControlContractValidation.has_exact_fields(record, fields):
		return ServiceResult.failure(&"invalid_module_slot", "The module slot has missing or unsupported fields.")
	if not ControlContractValidation.is_integer(record["schema_version"], SCHEMA_VERSION, SCHEMA_VERSION):
		return ServiceResult.failure(&"unsupported_module_slot_version", "The module-slot schema version is not supported.")
	if not ControlContractValidation.is_id(record["slot_id"]) or not ControlContractValidation.is_id(record["interface_id"]):
		return ServiceResult.failure(&"invalid_module_slot_id", "Slot and interface IDs must be non-empty strings up to 128 characters.")
	if not ControlContractValidation.is_integer(record["capacity_units"], 1, 1024):
		return ServiceResult.failure(&"invalid_module_slot_capacity", "Slot capacity must be between one and 1,024 units.")
	var families: ServiceResult = ControlContractValidation.decode_ids(record["allowed_module_families"], 1, 64)
	if not families.is_success:
		return families
	var slot := MachineModuleSlotDefinition.new()
	slot.slot_id = record["slot_id"]
	slot.interface_id = record["interface_id"]
	slot.capacity_units = int(record["capacity_units"])
	slot.allowed_module_families = families.value
	return ServiceResult.success(slot)
