extends InventoryControllerOwner
class_name InventoryRuntimeControllerOwner

## Explicit adapter; construction alone never installs admission or lifecycle lanes.
var _inventory: InventorySimulationSystem


func _init(inventory: InventorySimulationSystem) -> void:
	_inventory = inventory


func controller_candidate() -> ServiceResult:
	return _inventory.controller_candidate() if is_instance_valid(_inventory) else super.controller_candidate()


func commit_control_epoch(expected: Dictionary, next_epoch: int) -> ServiceResult:
	return _inventory.commit_control_epoch(expected, next_epoch) if is_instance_valid(_inventory) else super.commit_control_epoch(expected, next_epoch)


func controller_restore_generation() -> ServiceResult:
	if not is_instance_valid(_inventory):
		return ServiceResult.failure(&"invalid_candidate", "Canonical runtime is unavailable.")
	return ServiceResult.success(_inventory.controller_restore_generation())
