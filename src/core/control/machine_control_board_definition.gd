extends RefCounted
class_name MachineControlBoardDefinition

## Replaceable board slot layout and a pure planner that preserves fitted modules.
## Planning does not consume materials, rewire, or mutate installed equipment.

const SCHEMA_VERSION: int = 1

var definition_id: String = ""
var revision: int = 1
var mount_interface_id: String = ""
var slots: Dictionary = {}


func to_record() -> Dictionary:
	var slot_records: Array[Dictionary] = []
	var ids: Array = slots.keys()
	ids.sort()
	for id in ids:
		var slot := slots[id] as MachineModuleSlotDefinition
		slot_records.append(slot.to_record())
	return {
		"schema_version": SCHEMA_VERSION,
		"definition_id": definition_id,
		"revision": revision,
		"mount_interface_id": mount_interface_id,
		"slots": slot_records,
	}


func plan_replacement(
	replacement: MachineControlBoardDefinition,
	installed_modules: Dictionary,
	host_capabilities: PackedStringArray,
	slot_moves: Dictionary = {}
) -> ServiceResult:
	if replacement == null:
		return ServiceResult.failure(&"missing_control_board", "A replacement control board is required.")
	if installed_modules.size() > 64 or slot_moves.size() > 64:
		return ServiceResult.failure(&"board_installation_limit", "A board replacement plan may transfer at most 64 modules.")
	for board in [self, replacement]:
		for slot_id in board.slots:
			if not ControlContractValidation.is_id(slot_id) or not board.slots[slot_id] is MachineModuleSlotDefinition:
				return ServiceResult.failure(&"invalid_control_board_slot", "A board slot must contain a valid typed slot definition.")
	var source_check: ServiceResult = from_record(to_record())
	if not source_check.is_success:
		return source_check
	var target_check: ServiceResult = from_record(replacement.to_record())
	if not target_check.is_success:
		return target_check
	if mount_interface_id != replacement.mount_interface_id:
		return ServiceResult.failure(&"board_mount_mismatch", "The replacement board does not fit this board mount.")
	for source_id in slot_moves:
		if not installed_modules.has(source_id):
			return ServiceResult.failure(&"invalid_board_slot_move", "A slot move refers to a module that is not installed.")
	var assignments: Dictionary = {}
	var occupied_targets: Dictionary = {}
	var diagnostics: Array[Dictionary] = []
	var source_ids: Array = installed_modules.keys()
	for source_id in source_ids:
		if not ControlContractValidation.is_id(source_id):
			return ServiceResult.failure(&"invalid_installed_slot", "Installed modules must be keyed by stable slot IDs.")
	source_ids.sort()
	for source_id in source_ids:
		var source_slot := slots.get(source_id) as MachineModuleSlotDefinition
		if not installed_modules[source_id] is MachineModuleDefinition:
			return ServiceResult.failure(&"invalid_installed_module", "A fitted module requires a typed module definition.")
		var module := installed_modules[source_id] as MachineModuleDefinition
		if source_slot == null or module == null:
			return ServiceResult.failure(&"invalid_installed_module", "A fitted module or its current slot is missing.")
		var current_fit: ServiceResult = source_slot.accepts(module)
		if not current_fit.is_success:
			return current_fit
		var target_id: Variant = slot_moves.get(source_id, source_id)
		if not ControlContractValidation.is_id(target_id):
			return ServiceResult.failure(&"invalid_board_slot_move", "Replacement slot IDs must be non-empty strings.")
		var target_slot := replacement.slots.get(target_id) as MachineModuleSlotDefinition
		if target_slot == null:
			return ServiceResult.failure(&"module_relocation_required", "A fitted module needs an explicit compatible destination or removal job.")
		if occupied_targets.has(target_id):
			return ServiceResult.failure(&"board_slot_collision", "Two fitted modules cannot occupy the same replacement slot.")
		var target_fit: ServiceResult = target_slot.accepts(module)
		if not target_fit.is_success:
			return target_fit
		assignments[source_id] = target_id
		occupied_targets[target_id] = true
		var operability: ServiceResult = target_slot.evaluate_operability(module, host_capabilities)
		diagnostics.append(operability.value)
	return ServiceResult.success({
		"source_definition_id": definition_id,
		"source_revision": revision,
		"target_definition_id": replacement.definition_id,
		"target_revision": replacement.revision,
		"slot_assignments": assignments,
		"module_operability": diagnostics,
	})


static func from_record(record: Dictionary) -> ServiceResult:
	var fields := PackedStringArray(["schema_version", "definition_id", "revision", "mount_interface_id", "slots"])
	if not ControlContractValidation.has_exact_fields(record, fields):
		return ServiceResult.failure(&"invalid_control_board", "The control board has missing or unsupported fields.")
	if not ControlContractValidation.is_integer(record["schema_version"], SCHEMA_VERSION, SCHEMA_VERSION):
		return ServiceResult.failure(&"unsupported_control_board_version", "The control-board schema version is not supported.")
	if not ControlContractValidation.is_id(record["definition_id"]) or not ControlContractValidation.is_id(record["mount_interface_id"]):
		return ServiceResult.failure(&"invalid_control_board_id", "Board and mount IDs must be stable non-empty strings.")
	if not ControlContractValidation.is_integer(record["revision"], 1, 9007199254740991):
		return ServiceResult.failure(&"invalid_control_board_revision", "The board requires a positive integer revision.")
	if typeof(record["slots"]) != TYPE_ARRAY or record["slots"].is_empty() or record["slots"].size() > 64:
		return ServiceResult.failure(&"invalid_control_board_slots", "A board must declare between one and 64 slots.")
	var board := MachineControlBoardDefinition.new()
	board.definition_id = record["definition_id"]
	board.revision = int(record["revision"])
	board.mount_interface_id = record["mount_interface_id"]
	for slot_record in record["slots"]:
		if typeof(slot_record) != TYPE_DICTIONARY:
			return ServiceResult.failure(&"invalid_control_board_slot", "Board slots must be record objects.")
		var decoded: ServiceResult = MachineModuleSlotDefinition.from_record(slot_record)
		if not decoded.is_success:
			return decoded
		var slot: MachineModuleSlotDefinition = decoded.value
		if board.slots.has(slot.slot_id):
			return ServiceResult.failure(&"duplicate_control_board_slot", "Board slot IDs must be unique.")
		board.slots[slot.slot_id] = slot
	return ServiceResult.success(board)
