extends RefCounted
class_name BoardReplacementJob

## One reserved spare board, with tick-based work and explicit pause/resume.
const WORK_TICKS: int = 180
var job_id: String = ""
var actor_id: String = ""
var target_board_id: String = ""
var created_tick: int = 0
var updated_tick: int = 0
var completed_work_ticks: int = 0
var status: String = "active"


func to_record() -> Dictionary:
	return {"schema_version": 1, "job_id": job_id, "actor_id": actor_id,
		"target_board_id": target_board_id, "created_tick": created_tick,
		"updated_tick": updated_tick, "completed_work_ticks": completed_work_ticks,
		"status": status}


static func from_record(record: Dictionary, snapshot_tick: int) -> ServiceResult:
	var fields := PackedStringArray(["schema_version", "job_id", "actor_id", "target_board_id", "created_tick", "updated_tick", "completed_work_ticks", "status"])
	if not ControlContractValidation.has_exact_fields(record, fields) or not ControlContractValidation.is_integer(record.get("schema_version"), 1, 1):
		return ServiceResult.failure(&"invalid_board_job", "The board job record is invalid.")
	for field in ["job_id", "actor_id", "target_board_id"]:
		if not ControlContractValidation.is_id(record[field]):
			return ServiceResult.failure(&"invalid_board_job_id", "Board job IDs must be stable strings.")
	if not ControlContractValidation.is_integer(record["created_tick"], 0, snapshot_tick) or not ControlContractValidation.is_integer(record["updated_tick"], int(record["created_tick"]), snapshot_tick) or not ControlContractValidation.is_integer(record["completed_work_ticks"], 0, WORK_TICKS - 1):
		return ServiceResult.failure(&"invalid_board_job_progress", "Saved board work lies outside its tick bounds.")
	if record["completed_work_ticks"] > int(record["updated_tick"]) - int(record["created_tick"]) or not ["active", "paused"].has(record["status"]):
		return ServiceResult.failure(&"invalid_board_job_status", "Board progress or status is inconsistent.")
	var job := BoardReplacementJob.new()
	job.job_id = record["job_id"]
	job.actor_id = record["actor_id"]
	job.target_board_id = record["target_board_id"]
	job.created_tick = int(record["created_tick"])
	job.updated_tick = int(record["updated_tick"])
	job.completed_work_ticks = int(record["completed_work_ticks"])
	job.status = record["status"]
	return ServiceResult.success(job)
