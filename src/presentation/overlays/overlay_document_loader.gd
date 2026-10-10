extends RefCounted
class_name OverlayDocumentLoader

## Shared bounded local JSON loader for declarative overlay documents.
static func read_object(path: String, max_bytes: int) -> ServiceResult:
	if max_bytes <= 0 or max_bytes > 65536:
		return ServiceResult.failure(&"overlay_document_limit", "The document byte limit is invalid.")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > max_bytes:
		return ServiceResult.failure(&"overlay_document_file_limit", "A readable bounded document is required.")
	var bytes: PackedByteArray = file.get_buffer(max_bytes + 1)
	if bytes.size() > max_bytes:
		return ServiceResult.failure(&"overlay_document_file_limit", "The document exceeds its byte limit.")
	var decoded: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if typeof(decoded) != TYPE_DICTIONARY:
		return ServiceResult.failure(&"invalid_overlay_document_json", "An overlay document must contain one JSON object.")
	return ServiceResult.success(decoded)


static func load_directory(path: String, max_entries: int, max_bytes: int) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	if max_entries <= 0 or max_entries > 64:
		return records
	var directory := DirAccess.open(path)
	if directory == null:
		return records
	var examined: int = 0
	directory.list_dir_begin()
	var filename: String = directory.get_next()
	while filename != "" and examined < max_entries:
		examined += 1
		if not directory.current_is_dir() and filename.get_extension().to_lower() == "json":
			var loaded: ServiceResult = read_object(path.path_join(filename), max_bytes)
			if loaded.is_success:
				records.append(loaded.value)
			else:
				push_warning("An overlay document was skipped: %s" % loaded.error_code)
		filename = directory.get_next()
	directory.list_dir_end()
	return records
