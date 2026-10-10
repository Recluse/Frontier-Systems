extends RefCounted
class_name BypassJobState

## Persisted, server-owned staged security work.

const SCHEMA_VERSION: int = 1
const ROUTES := ["electrical", "mechanical", "combined"]
const STAGES := ["inspect", "access", "isolate", "stabilize", "perform", "verify", "restore"]
const STATUSES := ["queued", "active", "paused", "completed", "failed", "cancelled"]

var job_id: StringName
var request_id: StringName
var target_id: StringName
var route: StringName
var stage: StringName = &"inspect"
var status: StringName = &"active"
var actor_ids: Array[StringName] = []
var tool_ids: Array[StringName] = []
var progress: float = 0.0
var total_work_ticks: int = 180
var created_tick: int = 0
var updated_tick: int = 0
var result_code: StringName = &""


func to_record() -> Dictionary:
	var actors: Array[String] = []
	for actor_id in actor_ids:
		actors.append(String(actor_id))
	var tools: Array[String] = []
	for tool_id in tool_ids:
		tools.append(String(tool_id))
	return {
		"schema_version": SCHEMA_VERSION,
		"job_id": String(job_id),
		"request_id": String(request_id),
		"target_id": String(target_id),
		"route": String(route),
		"stage": String(stage),
		"status": String(status),
		"actor_ids": actors,
		"tool_ids": tools,
		"progress": progress,
		"total_work_ticks": total_work_ticks,
		"created_tick": created_tick,
		"updated_tick": updated_tick,
		"result_code": String(result_code),
	}


static func from_record(record: Dictionary) -> ServiceResult:
	if typeof(record.get("schema_version")) != TYPE_INT or record["schema_version"] != SCHEMA_VERSION:
		return ServiceResult.failure(&"unsupported_bypass_job_version", "The bypass-job record version is not supported.")
	if record.size() != 14:
		return ServiceResult.failure(&"invalid_bypass_job", "The bypass-job record has missing or unsupported fields.")
	for field_name in ["job_id", "request_id", "target_id", "route", "stage", "status", "result_code"]:
		if typeof(record.get(field_name)) != TYPE_STRING:
			return ServiceResult.failure(&"invalid_bypass_job", "Bypass-job identity and state fields must be strings.")
	var job := BypassJobState.new()
	job.job_id = StringName(record["job_id"])
	job.request_id = StringName(record["request_id"])
	job.target_id = StringName(record["target_id"])
	job.route = StringName(record["route"])
	job.stage = StringName(record["stage"])
	job.status = StringName(record["status"])
	job.result_code = StringName(record["result_code"])
	if typeof(record.get("actor_ids")) != TYPE_ARRAY or typeof(record.get("tool_ids")) != TYPE_ARRAY:
		return ServiceResult.failure(&"invalid_bypass_job", "Bypass-job actors and tools must be arrays.")
	if record["actor_ids"].is_empty() or record["actor_ids"].size() > 16 or record["tool_ids"].size() > 32:
		return ServiceResult.failure(&"invalid_bypass_job", "Bypass-job actor or tool count is outside supported limits.")
	for actor_value in record["actor_ids"]:
		if typeof(actor_value) != TYPE_STRING or String(actor_value).strip_edges().is_empty():
			return ServiceResult.failure(&"invalid_bypass_job", "Bypass-job actor IDs must be non-empty strings.")
		var actor_id := StringName(actor_value)
		if job.actor_ids.has(actor_id):
			return ServiceResult.failure(&"invalid_bypass_job", "Bypass-job actor IDs must be unique.")
		job.actor_ids.append(actor_id)
	for tool_value in record["tool_ids"]:
		if typeof(tool_value) != TYPE_STRING or String(tool_value).strip_edges().is_empty():
			return ServiceResult.failure(&"invalid_bypass_job", "Bypass-job tool IDs must be non-empty strings.")
		var tool_id := StringName(tool_value)
		if job.tool_ids.has(tool_id):
			return ServiceResult.failure(&"invalid_bypass_job", "Bypass-job tool IDs must be unique.")
		job.tool_ids.append(tool_id)
	var progress_value: Variant = record.get("progress")
	var integer_fields := ["total_work_ticks", "created_tick", "updated_tick"]
	if typeof(progress_value) != TYPE_INT and typeof(progress_value) != TYPE_FLOAT:
		return ServiceResult.failure(&"invalid_bypass_job", "Bypass-job progress must be numeric.")
	job.progress = float(progress_value)
	for field_name in integer_fields:
		if typeof(record.get(field_name)) != TYPE_INT:
			return ServiceResult.failure(&"invalid_bypass_job", "Bypass-job tick fields must be integers.")
	job.total_work_ticks = record["total_work_ticks"]
	job.created_tick = record["created_tick"]
	job.updated_tick = record["updated_tick"]
	if (
		String(job.job_id).is_empty()
		or String(job.request_id).is_empty()
		or String(job.target_id).is_empty()
		or not ROUTES.has(String(job.route))
		or not STAGES.has(String(job.stage))
		or not STATUSES.has(String(job.status))
		or not is_finite(job.progress) or job.progress < 0.0 or job.progress > 1.0
		or job.total_work_ticks < 1 or job.created_tick < 0 or job.updated_tick < job.created_tick
		or job.actor_ids.is_empty()
	):
		return ServiceResult.failure(&"invalid_bypass_job", "Bypass-job state is outside its supported range.")
	return ServiceResult.success(job)
