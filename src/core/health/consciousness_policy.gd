extends RefCounted
class_name ConsciousnessPolicy

## Pure fictional suppression policy over trusted physiological observations.
const MAX_ASSESSMENT_GAP_TICKS: int = 6
const RECOVERY_TICKS: int = 60


static func plan(state: ConsciousnessState, causes: Array, assessed_tick: int) -> ServiceResult:
	if state == null:
		return ServiceResult.failure(&"invalid_consciousness_state", "A validated current record is required.")
	var parsed: ServiceResult = ConsciousnessState.from_record(state.to_record())
	if not parsed.is_success:
		return parsed
	var before: Dictionary = parsed.value.to_record()
	if assessed_tick <= int(before["last_assessed_tick"]) or assessed_tick > ConsciousnessState.MAX_INTEGER or int(before["state_revision"]) == ConsciousnessState.MAX_INTEGER:
		return ServiceResult.failure(&"invalid_consciousness_tick", "Assessment requires a newer bounded tick and revision capacity.")
	var decoded: ServiceResult = ConsciousnessState.decode_causes(causes)
	if not decoded.is_success:
		return decoded
	var after: Dictionary = before.duplicate(true)
	var total: int = ConsciousnessState.suppression(decoded.value)
	var next_state: String = before["state"]
	var recovery: int = -1
	if total >= 750:
		next_state = "unconscious"
	elif next_state == "unconscious":
		if total <= 500:
			recovery = int(before["recovery_since_tick"])
			if recovery < 0 or assessed_tick - int(before["last_assessed_tick"]) > MAX_ASSESSMENT_GAP_TICKS:
				recovery = assessed_tick
			if assessed_tick - recovery >= RECOVERY_TICKS:
				next_state = "impaired" if total >= 250 else "alert"
				recovery = -1
	elif next_state == "alert" and total >= 250:
		next_state = "impaired"
	elif next_state == "impaired" and total <= 150:
		next_state = "alert"
	after["state"] = next_state
	after["causes"] = decoded.value
	after["last_assessed_tick"] = assessed_tick
	after["state_revision"] = int(before["state_revision"]) + 1
	after["recovery_since_tick"] = recovery
	if next_state != before["state"]:
		after["transition_tick"] = assessed_tick
	var validated: ServiceResult = ConsciousnessState.from_record(after)
	if not validated.is_success:
		return validated
	return ServiceResult.success({"schema_version": 1, "before": before, "after": validated.value.to_record(),
		"suppression_permille": total, "transitioned": next_state != before["state"],
		"consciousness_allows_voluntary_actions": next_state != "unconscious"})
