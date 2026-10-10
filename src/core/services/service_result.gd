extends RefCounted
class_name ServiceResult

## Value/error envelope for asynchronous integration boundaries.

var is_success: bool
var value: Variant
var error_code: StringName
var message: String


static func success(result: Variant = null) -> ServiceResult:
	var response := ServiceResult.new()
	response.is_success = true
	response.value = result
	response.error_code = &""
	response.message = ""
	return response


static func failure(code: StringName, description: String) -> ServiceResult:
	var response := ServiceResult.new()
	response.is_success = false
	response.value = null
	response.error_code = code
	response.message = description
	return response
