extends RefCounted
class_name CheckpointFileIO

## Worker-side filesystem boundary. Override only for isolated fault injection.
func ensure_directory(path: String) -> ServiceResult:
	var parent: String = path
	while not parent.is_empty():
		if FileAccess.file_exists(parent):
			return ServiceResult.failure(&"save_directory", "A file blocks the configured save directory.")
		var next: String = parent.get_base_dir()
		if next == parent:
			break
		parent = next
	return ServiceResult.success() if DirAccess.make_dir_recursive_absolute(path) == OK else ServiceResult.failure(&"save_directory", "Cannot create the configured save directory.")


func exists(path: String) -> bool:
	return FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path)


func read_text(path: String, max_bytes: int) -> ServiceResult:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ServiceResult.failure(&"save_read", "Cannot read a checkpoint file.")
	var length: int = file.get_length()
	if length > max_bytes:
		file.close()
		return ServiceResult.failure(&"save_bounds", "Checkpoint file exceeds its byte bound.")
	var bytes: PackedByteArray = file.get_buffer(length)
	var error: Error = file.get_error()
	file.close()
	if bytes.size() != length or error != OK:
		return ServiceResult.failure(&"save_read", "Checkpoint read was incomplete.")
	return ServiceResult.success(bytes.get_string_from_utf8())


func write_text(path: String, text: String) -> ServiceResult:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return ServiceResult.failure(&"save_open", "Cannot open the checkpoint staging file.")
	file.store_buffer(text.to_utf8_buffer())
	file.flush()
	var error: Error = file.get_error()
	file.close()
	return ServiceResult.success() if error == OK else ServiceResult.failure(&"save_write", "Checkpoint write or flush failed.")


func remove_file(path: String) -> ServiceResult:
	if not exists(path):
		return ServiceResult.success()
	return ServiceResult.success() if DirAccess.remove_absolute(path) == OK else ServiceResult.failure(&"save_cleanup", "Cannot remove an inactive checkpoint file.")


func promote(source: String, destination: String) -> ServiceResult:
	return ServiceResult.success() if DirAccess.rename_absolute(source, destination) == OK else ServiceResult.failure(&"save_promote", "Cannot promote the verified checkpoint staging file.")

