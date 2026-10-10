extends SimulationSystem
class_name HealthSimulationSystem

## Bounded consciousness scheduler; sources are trusted adapter observations,
## not injuries/chemical quantities and never a player-supplied cause endpoint.
const SYSTEM_ID: StringName = &"health"
const MAX_BODIES: int = 64
const MAX_ASSESSMENTS_PER_TICK: int = 12
const INTERVAL_TICKS: int = 6
var _entries: Dictionary = {}
var _pending: Dictionary = {}
var _pending_injuries: Dictionary = {}
var _last_tick: int = 0
var _last_assessments: int = 0
var _failures: int = 0
var _timebase_hz: int = 60
var _configured: bool = false


func _init() -> void:
	system_id = SYSTEM_ID
	tick_priority = 100


func configure_bodies(body_ids: Array) -> ServiceResult:
	if _configured:
		return ServiceResult.failure(&"health_already_configured", "Configure the fixed body registry once; use explicit snapshot restore for recovery.")
	var record: ServiceResult = initial_record(body_ids, 0)
	return restore_snapshot_record(record.value, 0) if record.is_success else record


static func initial_record(body_ids: Array, tick: int) -> ServiceResult:
	var ids: ServiceResult = ControlContractValidation.decode_ids(body_ids, 0, MAX_BODIES)
	if not ids.is_success or tick < 0 or tick > ConsciousnessState.MAX_INTEGER - INTERVAL_TICKS:
		return ServiceResult.failure(&"invalid_health_bodies", "Health initialization requires bounded unique body IDs and tick capacity.")
	var sorted_ids: Array = body_ids.duplicate()
	sorted_ids.sort()
	var entries: Array = []
	for index in range(sorted_ids.size()):
		var owner: ServiceResult = ConsciousnessOwner.create(sorted_ids[index])
		entries.append({"owner": owner.value.to_record(), "source_revision": 0, "causes": [], "injuries": BodyInjuryState.create(sorted_ids[index]).value.to_record(), "next_assessment_tick": tick + 1 + index % INTERVAL_TICKS})
	return ServiceResult.success({"schema_version": 2, "timebase_hz": Engine.physics_ticks_per_second, "last_tick": tick, "entries": entries})


## Internal adapter queue. Changes apply only at the next fixed tick.
func queue_observation(body_id: String, causes: Array, expected_revision: int, observed_tick: int) -> ServiceResult:
	if Engine.physics_ticks_per_second != _timebase_hz or not _entries.has(body_id) or _pending.has(body_id) or observed_tick != _last_tick + 1:
		return ServiceResult.failure(&"invalid_health_observation", "One fresh next-tick observation for a registered body is required.")
	var entry: Dictionary = _entries[body_id]
	if expected_revision != int(entry["source_revision"]) or expected_revision >= ConsciousnessState.MAX_INTEGER:
		return ServiceResult.failure(&"stale_health_source", "Source revision is stale or exhausted.")
	var parsed: ServiceResult = ConsciousnessState.decode_causes(causes)
	if not parsed.is_success:
		return parsed
	var injuries: BodyInjuryState = entry["injuries"]
	if _pending_injuries.has(body_id):
		injuries = _pending_injuries[body_id]
	var combined: ServiceResult = _combined_causes(injuries, parsed.value)
	if not combined.is_success:
		return combined
	_pending[body_id] = {"causes": parsed.value, "observed_tick": observed_tick}
	return ServiceResult.success()


func injury_observation(body_id: String) -> ServiceResult:
	if not _entries.has(body_id):
		return ServiceResult.failure(&"unknown_health_body", "No injury owner is registered for this body.")
	return ServiceResult.success(_entries[body_id]["injuries"].to_record())


## Internal trusted adapter, not a player/LLM damage or free-healing endpoint.
func queue_injury_change(body_id: String, expected_revision: int, tick: int, operation: String, part_id: String, kind: String, amount: int) -> ServiceResult:
	if Engine.physics_ticks_per_second != _timebase_hz or not _entries.has(body_id) or _pending_injuries.has(body_id) or tick != _last_tick + 1:
		return ServiceResult.failure(&"invalid_injury_queue", "One fresh next-tick injury change per registered body is supported.")
	var entry: Dictionary = _entries[body_id]
	var injury: BodyInjuryState = entry["injuries"]
	if expected_revision != int(injury.to_record()["state_revision"]):
		return ServiceResult.failure(&"stale_injury_revision", "Current injury revision is required.")
	var planned: ServiceResult = injury.plan_change(operation, part_id, kind, amount, tick)
	if not planned.is_success:
		return planned
	var after: BodyInjuryState = BodyInjuryState.from_record(planned.value["after"]).value
	var causes: Array = _pending[body_id]["causes"] if _pending.has(body_id) else entry["causes"]
	var combined: ServiceResult = _combined_causes(after, causes)
	if not combined.is_success:
		return combined
	_pending_injuries[body_id] = after
	return ServiceResult.success({"planned_amount_permille": planned.value["applied_amount_permille"]})


func body_observation(body_id: String) -> ServiceResult:
	if not _entries.has(body_id):
		return ServiceResult.failure(&"unknown_health_body", "No health owner is registered for this body.")
	var entry: Dictionary = _entries[body_id]
	return ServiceResult.success({"state": entry["owner"].state_observation(), "source_revision": entry["source_revision"], "next_assessment_tick": entry["next_assessment_tick"]})


func consciousness_allows_actions(body_id: String) -> bool:
	return _entries.has(body_id) and _entries[body_id]["owner"].allows_voluntary_actions()


func simulate_tick(tick: int, _fixed_delta: float) -> void:
	if Engine.physics_ticks_per_second != _timebase_hz or tick <= _last_tick or tick > ConsciousnessState.MAX_INTEGER - INTERVAL_TICKS:
		_failures = mini(_failures + 1, ConsciousnessOwner.MAX_COUNTER)
		return
	_last_tick = tick
	for body_id in _pending:
		var observation: Dictionary = _pending[body_id]
		if observation["observed_tick"] != tick:
			_failures = mini(_failures + 1, ConsciousnessOwner.MAX_COUNTER)
			continue
		_entries[body_id]["causes"] = observation["causes"]
		_entries[body_id]["source_revision"] += 1
		_entries[body_id]["next_assessment_tick"] = tick
	_pending.clear()
	for body_id in _pending_injuries:
		var injury: BodyInjuryState = _pending_injuries[body_id]
		if int(injury.to_record()["last_changed_tick"]) != tick:
			_failures = mini(_failures + 1, ConsciousnessOwner.MAX_COUNTER)
			continue
		_entries[body_id]["injuries"] = injury
		_entries[body_id]["next_assessment_tick"] = tick
	_pending_injuries.clear()
	var due: Array = []
	for body_id in _entries:
		if int(_entries[body_id]["next_assessment_tick"]) <= tick:
			due.append(body_id)
	due.sort_custom(func(a: String, b: String) -> bool:
		var first: int = _entries[a]["next_assessment_tick"]
		var second: int = _entries[b]["next_assessment_tick"]
		return a < b if first == second else first < second)
	_last_assessments = 0
	for body_id in due.slice(0, MAX_ASSESSMENTS_PER_TICK):
		var entry: Dictionary = _entries[body_id]
		var state: Dictionary = entry["owner"].state_observation()
		var revision: int = state["state_revision"]
		var combined: ServiceResult = _combined_causes(entry["injuries"], entry["causes"])
		if not combined.is_success:
			_failures = mini(_failures + 1, ConsciousnessOwner.MAX_COUNTER)
			entry["next_assessment_tick"] = tick + INTERVAL_TICKS
			continue
		var request := {"schema_version": 1, "request_id": "health-%s-%d" % [String(body_id).sha256_text(), revision + 1],
			"body_id": body_id, "expected_state_revision": revision, "observed_tick": tick, "causes": combined.value}
		var result: ServiceResult = entry["owner"].assess(request, tick)
		if not result.is_success:
			_failures = mini(_failures + 1, ConsciousnessOwner.MAX_COUNTER)
		entry["next_assessment_tick"] = tick + INTERVAL_TICKS
		_last_assessments += 1


func profiling_counters() -> Dictionary:
	var overdue: int = 0
	for entry in _entries.values():
		if int(entry["next_assessment_tick"]) <= _last_tick:
			overdue += 1
	return {"bodies": _entries.size(), "assessments_last_tick": _last_assessments,
		"overdue_bodies": overdue, "pending_observations": _pending.size(), "pending_injury_changes": _pending_injuries.size(), "assessment_failures": _failures}


func capture_snapshot() -> ServiceResult:
	if Engine.physics_ticks_per_second != _timebase_hz:
		return ServiceResult.failure(&"health_timebase_changed", "Changing the health timebase requires an explicit migration.")
	if not _pending.is_empty() or not _pending_injuries.is_empty():
		return ServiceResult.failure(&"health_observations_pending", "Apply pending health observations before capturing.")
	var entries: Array = []
	var ids: Array = _entries.keys()
	ids.sort()
	for id in ids:
		var entry: Dictionary = _entries[id]
		entries.append({"owner": entry["owner"].to_record(), "source_revision": entry["source_revision"],
			"causes": entry["causes"].duplicate(true), "injuries": entry["injuries"].to_record(), "next_assessment_tick": entry["next_assessment_tick"]})
	return ServiceResult.success({"schema_version": 2, "timebase_hz": _timebase_hz, "last_tick": _last_tick, "entries": entries})


func validate_snapshot_record(record: Dictionary, tick: int) -> ServiceResult:
	return _decode(record, tick)


func restore_snapshot_record(record: Dictionary, tick: int) -> ServiceResult:
	var decoded: ServiceResult = _decode(record, tick)
	if not decoded.is_success:
		return decoded
	_entries = decoded.value
	_configured = true
	_last_tick = tick
	_timebase_hz = int(record["timebase_hz"])
	_pending.clear()
	_pending_injuries.clear()
	_last_assessments = 0
	_failures = 0
	return ServiceResult.success()


static func _decode(record: Dictionary, tick: int) -> ServiceResult:
	if tick < 0 or tick > ConsciousnessState.MAX_INTEGER - INTERVAL_TICKS or not ControlContractValidation.has_exact_fields(record, PackedStringArray(["schema_version", "timebase_hz", "last_tick", "entries"])) or not ControlContractValidation.is_integer(record.get("schema_version"), 1, 2) or not ControlContractValidation.is_integer(record.get("timebase_hz"), Engine.physics_ticks_per_second, Engine.physics_ticks_per_second) or not [60, 72, 90].has(Engine.physics_ticks_per_second) or not ControlContractValidation.is_integer(record.get("last_tick"), tick, tick) or typeof(record.get("entries")) != TYPE_ARRAY or record["entries"].size() > MAX_BODIES:
		return ServiceResult.failure(&"invalid_health_snapshot", "An exact bounded health snapshot with a matching supported timebase is required.")
	var entries: Dictionary = {}
	for raw in record["entries"]:
		var fields := PackedStringArray(["owner", "source_revision", "causes", "next_assessment_tick"])
		if int(record["schema_version"]) == 2:
			fields.append("injuries")
		if typeof(raw) != TYPE_DICTIONARY or not ControlContractValidation.has_exact_fields(raw, fields) or typeof(raw.get("owner")) != TYPE_DICTIONARY or not ControlContractValidation.is_integer(raw.get("source_revision"), 0, ConsciousnessState.MAX_INTEGER) or not ControlContractValidation.is_integer(raw.get("next_assessment_tick"), 1, tick + INTERVAL_TICKS):
			return ServiceResult.failure(&"invalid_health_entry", "A bounded owner/source/schedule record is required.")
		var owner: ServiceResult = ConsciousnessOwner.from_record(raw["owner"], tick)
		var causes: ServiceResult = ConsciousnessState.decode_causes(raw["causes"])
		if not owner.is_success or not causes.is_success:
			return ServiceResult.failure(&"invalid_health_entry", "Health owner or current source causes failed validation.")
		var state: Dictionary = owner.value.state_observation()
		var injury: ServiceResult = BodyInjuryState.create(state["body_id"])
		if int(record["schema_version"]) == 2:
			if typeof(raw.get("injuries")) != TYPE_DICTIONARY:
				return ServiceResult.failure(&"invalid_health_injury", "Injuries require a versioned record.")
			injury = BodyInjuryState.from_record(raw["injuries"])
		if not injury.is_success or injury.value.to_record()["body_id"] != state["body_id"] or int(injury.value.to_record()["last_changed_tick"]) > tick:
			return ServiceResult.failure(&"invalid_health_injury", "Injury body/tick must match its containing health entry.")
		var injury_tick: int = injury.value.to_record()["last_changed_tick"]
		if int(state["last_assessed_tick"]) < injury_tick and int(raw["next_assessment_tick"]) > injury_tick:
			return ServiceResult.failure(&"invalid_health_injury", "Unassessed changed injuries must retain their immediate due tick.")
		var combined: ServiceResult = _combined_causes(injury.value, causes.value)
		if not combined.is_success:
			return combined
		if (int(raw["source_revision"]) == 0 and not causes.value.is_empty()) or (int(state["last_assessed_tick"]) == tick and state["causes"] != combined.value):
			return ServiceResult.failure(&"invalid_health_entry", "Source history or latest assessment contradicts the current causes.")
		if entries.has(state["body_id"]) or int(raw["next_assessment_tick"]) <= int(state["last_assessed_tick"]):
			return ServiceResult.failure(&"invalid_health_entry", "Health bodies must be unique and next due tick later than their assessment.")
		entries[state["body_id"]] = {"owner": owner.value, "source_revision": int(raw["source_revision"]), "causes": causes.value, "injuries": injury.value, "next_assessment_tick": int(raw["next_assessment_tick"])}
	return ServiceResult.success(entries)


static func _combined_causes(injuries: BodyInjuryState, sources: Array) -> ServiceResult:
	for cause in sources:
		if cause["cause_id"] in [BodyInjuryState.HEAD_CAUSE, BodyInjuryState.OXYGEN_CAUSE]:
			return ServiceResult.failure(&"reserved_injury_cause", "Anatomy cause IDs are owned by the injury component.")
	return ConsciousnessState.decode_causes(sources + injuries.consciousness_causes())
