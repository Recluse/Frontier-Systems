extends RefCounted
class_name CheckpointHistoryPolicy

## Opt-in operator retention. One spare entry and staging have bounded transient space.
const MAX_ENTRIES: int = 8
const MAX_RETAINED_BYTES: int = 67108864
var entries: int
var retained_bytes: int


func _init(count: int = 3, bytes: int = 33554432) -> void:
	entries = count
	retained_bytes = bytes


func validate() -> ServiceResult:
	if entries < 1 or entries > MAX_ENTRIES or retained_bytes < 1 or retained_bytes > MAX_RETAINED_BYTES:
		return ServiceResult.failure(&"backup_configuration", "History requires 1-8 entries and 1 byte through 64 MiB retained bytes.")
	return ServiceResult.success()


func detached() -> CheckpointHistoryPolicy:
	return CheckpointHistoryPolicy.new(entries, retained_bytes)

