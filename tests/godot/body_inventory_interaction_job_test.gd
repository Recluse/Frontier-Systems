extends SceneTree

var _failures: int = 0


func _initialize() -> void:
	var rules: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/inventory/body-interactions.default.v1.json"))
	for action in BodyInventoryInteractionPolicy.ACTIONS:
		rules["duration_ticks"][action] = 2
	var policy: BodyInventoryInteractionPolicy = BodyInventoryInteractionPolicy.from_record(rules).value
	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/inventory/interaction-job.default.v1.json"))
	var context := {"actor_control_epoch": 0, "target_action_epoch": 0, "actor_inventory_revision": 0, "target_inventory_revision": 0}
	var observation := {"distance_millimetres": 1000, "actor_can_manipulate": true, "target_available": true, "target_resisting": false, "target_moved": false, "path_accessible": true}
	var started: ServiceResult = BodyInventoryInteractionJob.start(record, policy, observation)
	_check(started.is_success, "trusted default job must start")
	if not started.is_success:
		quit(1)
		return
	var job: BodyInventoryInteractionJob = started.value
	_check(not job.completion_candidate(0, context, observation).is_success, "new job must not complete instantly")
	_check(job.advance(1, context, observation).is_success and job.to_record()["state"] == "active", "first consecutive tick must progress")
	var before: Dictionary = job.to_record()
	_check(not job.advance(1, context, observation).is_success and job.to_record() == before, "duplicate tick must not duplicate progress")
	_check(not job.advance(3, context, observation).is_success and job.to_record() == before, "skipped tick must not fast-forward")
	_check(job.advance(2, context, observation).is_success and job.to_record()["state"] == "ready", "exact duration must reach readiness")
	_check(job.completion_candidate(2, context, observation).is_success, "fresh ready state must produce candidate")
	_check(not job.completion_candidate(3, context, observation).is_success, "candidate cannot authorize a later tick")
	var ready_record: Dictionary = job.to_record()
	var restored: BodyInventoryInteractionJob = BodyInventoryInteractionJob.from_record(JSON.parse_string(JSON.stringify(ready_record)), policy).value
	_check(restored.to_record()["state"] == "paused", "restored ready job must pause")
	_check(not restored.advance(3, context, observation).is_success, "restore must not auto-progress")
	_check(restored.resume(100, context, observation).is_success, "explicit fresh resume must succeed")
	_check(restored.to_record()["progress_ticks"] == 1, "ready restore must require one new validated tick")
	_check(restored.advance(101, context, observation).is_success and restored.completion_candidate(101, context, observation).is_success, "resumed readiness must use fresh tick")
	for field in BodyInventoryInteractionJob.CONTEXT_FIELDS:
		var interrupted: BodyInventoryInteractionJob = BodyInventoryInteractionJob.start(record, policy, observation).value
		var changed: Dictionary = context.duplicate(true)
		changed[field] = 1
		_check(not interrupted.advance(1, changed, observation).is_success and interrupted.to_record()["state"] == "cancelled", "changed epoch/revision must cancel: " + field)
	var reacted: BodyInventoryInteractionJob = BodyInventoryInteractionJob.start(record, policy, observation).value
	reacted.advance(1, context, observation)
	var moved: Dictionary = observation.duplicate(true)
	moved["target_moved"] = true
	_check(not reacted.advance(2, context, moved).is_success and reacted.to_record()["state"] == "cancelled", "same-completion-tick movement must cancel before readiness")
	var ready_changed: BodyInventoryInteractionJob = BodyInventoryInteractionJob.start(record, policy, observation).value
	ready_changed.advance(1, context, observation)
	ready_changed.advance(2, context, observation)
	var resisted: Dictionary = context.duplicate(true)
	resisted["target_action_epoch"] = 1
	_check(not ready_changed.completion_candidate(2, resisted, observation).is_success and ready_changed.to_record()["state"] == "cancelled", "late same-tick resistance epoch must invalidate candidate")
	var stale_restore: BodyInventoryInteractionJob = BodyInventoryInteractionJob.from_record(before, policy).value
	_check(not stale_restore.resume(20, resisted, observation).is_success and stale_restore.to_record()["state"] == "cancelled", "restored job must not rebaseline resistance epoch")
	var cancelled: BodyInventoryInteractionJob = BodyInventoryInteractionJob.start(record, policy, observation).value
	cancelled.cancel()
	_check(BodyInventoryInteractionJob.from_record(cancelled.to_record(), policy).value.to_record()["state"] == "cancelled", "cancelled restore must remain terminal")
	var invalid: Dictionary = record.duplicate(true)
	invalid["actor_body_id"] = invalid["target_body_id"]
	_check(not BodyInventoryInteractionJob.start(invalid, policy, observation).is_success, "other-body job cannot target self")
	invalid = record.duplicate(true)
	invalid["progress_ticks"] = 2
	_check(not BodyInventoryInteractionJob.start(invalid, policy, observation).is_success, "new job cannot contain fabricated progress")
	invalid = record.duplicate(true)
	invalid["policy_revision"] = 2
	_check(not BodyInventoryInteractionJob.from_record(invalid, policy).is_success, "unknown policy revision must reject")
	var detached: Dictionary = job.to_record()
	detached["progress_ticks"] = 0
	_check(job.to_record()["progress_ticks"] == 2, "job snapshots must be detached")
	if _failures == 0:
		print("Timed body inventory interaction and recovery scenarios passed.")
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
