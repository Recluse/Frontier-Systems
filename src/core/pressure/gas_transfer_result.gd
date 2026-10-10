extends RefCounted
class_name GasTransferResult

## Result of one bounded gas transfer calculation.

var is_valid: bool = true
var source_volume_id: StringName = &""
var receiver_volume_id: StringName = &""
var transferred_moles: float = 0.0
var error_code: StringName = &""
var message: String = ""


static func no_transfer() -> GasTransferResult:
	return GasTransferResult.new()


static func transfer(source_id: StringName, receiver_id: StringName, amount_moles: float) -> GasTransferResult:
	var result := GasTransferResult.new()
	result.source_volume_id = source_id
	result.receiver_volume_id = receiver_id
	result.transferred_moles = amount_moles
	return result


static func failure(code: StringName, description: String) -> GasTransferResult:
	var result := GasTransferResult.new()
	result.is_valid = false
	result.error_code = code
	result.message = description
	return result
