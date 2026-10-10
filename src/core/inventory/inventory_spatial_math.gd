extends RefCounted
class_name InventorySpatialMath

## Integer millimetre coordinates avoid Vector3 float32 quantization in reach checks.
const MAX_COORDINATE: int = 10000000


static func is_position(value: Variant) -> bool:
	if typeof(value) != TYPE_ARRAY or value.size() != 3:
		return false
	for coordinate in value:
		if not ControlContractValidation.is_integer(coordinate, -MAX_COORDINATE, MAX_COORDINATE):
			return false
	return true


static func normalized(value: Array) -> Array:
	return [int(value[0]), int(value[1]), int(value[2])]


## Rounded upward so an item just outside the boundary is never treated as within reach.
## Inputs must already be validated; maximum squared distance fits exact int64/JSON.
static func distance_millimetres(first: Array, second: Array) -> int:
	var squared: int = 0
	for index in range(3):
		var difference: int = int(first[index]) - int(second[index])
		squared += difference * difference
	var root: int = int(sqrt(float(squared)))
	return root + 1 if root * root < squared else root
