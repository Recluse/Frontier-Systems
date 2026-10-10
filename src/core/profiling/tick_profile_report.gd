extends RefCounted
class_name TickProfileReport

## Pure, on-demand summaries of internally generated bounded history records.
## Percentiles use nearest rank; counters remain gauges without inferred semantics.
static func summarize(history: Dictionary) -> ServiceResult:
	var samples_value: Variant = history.get("samples")
	if typeof(samples_value) != TYPE_ARRAY or samples_value.size() > TickProfileHistory.MAX_CAPACITY:
		return ServiceResult.failure(&"invalid_profile_samples", "A bounded profiling sample array is required.")
	var elapsed: Array[int] = []
	var command_times: Array[int] = []
	var rows: Dictionary = {}
	var over_budget: int = 0
	var queue_peak: int = 0
	var commands: int = 0
	var omitted_system_observations: int = 0
	var first_tick: int = 0
	var last_tick: int = 0
	for sample in samples_value:
		if typeof(sample) != TYPE_DICTIONARY:
			return ServiceResult.failure(&"invalid_profile_sample", "Profiling samples must be records.")
		for field in ["tick_number", "elapsed_usec", "command_usec", "commands_processed", "queued_commands", "budget_usec"]:
			var value: Variant = sample.get(field)
			if typeof(value) != TYPE_INT or value < 0 or value > 9007199254740990:
				return ServiceResult.failure(&"invalid_profile_measurement", "Profiling counts and timings must be non-negative exact integers.")
		if sample["commands_processed"] > 65536 or sample["queued_commands"] > 1048576 or sample["budget_usec"] < 1:
			return ServiceResult.failure(&"invalid_profile_limits", "Sample counts exceed the supported command bounds.")
		var tick: int = sample["tick_number"]
		if not elapsed.is_empty() and tick <= last_tick:
			return ServiceResult.failure(&"invalid_profile_order", "Profiling ticks must be strictly increasing.")
		if elapsed.is_empty():
			first_tick = tick
		last_tick = tick
		elapsed.append(sample["elapsed_usec"])
		command_times.append(sample["command_usec"])
		commands += int(sample["commands_processed"])
		queue_peak = maxi(queue_peak, int(sample["queued_commands"]))
		if sample["elapsed_usec"] > sample["budget_usec"]:
			over_budget += 1
		var systems_value: Variant = sample.get("systems")
		if typeof(systems_value) != TYPE_ARRAY or systems_value.size() > TickProfileHistory.MAX_SYSTEMS:
			return ServiceResult.failure(&"invalid_profile_systems", "System observations must be bounded.")
		var seen: Dictionary = {}
		for observation in systems_value:
			if typeof(observation) != TYPE_DICTIONARY:
				return ServiceResult.failure(&"invalid_profile_system", "System observations must be records.")
			var id: Variant = observation.get("system_id")
			var duration: Variant = observation.get("elapsed_usec")
			var counters: Variant = observation.get("counters")
			if typeof(id) != TYPE_STRING or String(id).is_empty() or String(id).length() > 128 or seen.has(id):
				return ServiceResult.failure(&"invalid_profile_system_id", "Each tick requires unique bounded system IDs.")
			seen[id] = true
			if typeof(duration) != TYPE_INT or duration < 0 or duration > 9007199254740990 or typeof(counters) != TYPE_DICTIONARY or counters.size() > TickProfileHistory.MAX_COUNTERS:
				return ServiceResult.failure(&"invalid_profile_system_values", "System timing and counters must be bounded numeric records.")
			for key in counters:
				var value: Variant = counters[key]
				if typeof(key) != TYPE_STRING or String(key).is_empty() or String(key).length() > 64 or (typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT) or not is_finite(float(value)):
					return ServiceResult.failure(&"invalid_profile_counter", "Counters must use bounded keys and finite numbers.")
			if not rows.has(id):
				if rows.size() >= TickProfileHistory.MAX_SYSTEMS:
					omitted_system_observations += 1
					continue
				rows[id] = {"durations": [], "latest_counters": {}, "last_observed_tick": tick}
			var row: Dictionary = rows[id]
			row["durations"].append(int(duration))
			row["latest_counters"] = counters.duplicate(true)
			row["last_observed_tick"] = tick
	var system_reports: Array[Dictionary] = []
	var ids: Array = rows.keys()
	ids.sort()
	for id in ids:
		var row: Dictionary = rows[id]
		system_reports.append({"system_id": id, "timing_usec": _statistics(row["durations"]), "last_observed_tick": row["last_observed_tick"], "latest_counters": row["latest_counters"]})
	return ServiceResult.success({
		"schema_version": 1, "sample_count": elapsed.size(),
		"first_tick": first_tick if not elapsed.is_empty() else null,
		"last_tick": last_tick if not elapsed.is_empty() else null,
		"tick_timing_usec": _statistics(elapsed), "command_timing_usec": _statistics(command_times),
		"over_budget_samples": over_budget, "queue_peak": queue_peak,
		"commands_processed": commands, "omitted_system_observations": omitted_system_observations,
		"systems": system_reports,
	})


static func _statistics(values: Array) -> Dictionary:
	if values.is_empty():
		return {"count": 0, "minimum": null, "maximum": null, "mean": null, "p50": null, "p95": null, "p99": null}
	var ordered: Array = values.duplicate()
	ordered.sort()
	var total: float = 0.0
	for value in ordered:
		total += float(value)
	return {"count": ordered.size(), "minimum": ordered[0], "maximum": ordered[-1],
		"mean": total / float(ordered.size()), "p50": _percentile(ordered, 0.50),
		"p95": _percentile(ordered, 0.95), "p99": _percentile(ordered, 0.99)}


static func _percentile(ordered: Array, fraction: float) -> int:
	return int(ordered[maxi(0, ceili(fraction * ordered.size()) - 1)])
