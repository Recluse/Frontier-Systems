extends RefCounted
class_name TickProfileHistory

## Disposable bounded ring. It stores data only, never nodes, commands or actors.
const MAX_CAPACITY: int = 2048
const MAX_SYSTEMS: int = 64
const MAX_COUNTERS: int = 16
var _capacity: int = 120
var _samples: Array[Dictionary] = []
var _next: int = 0
var _overwritten: int = 0


func _init(capacity: int = 120) -> void:
	_capacity = clampi(capacity, 1, MAX_CAPACITY)


func record_tick(tick_number: int, elapsed_usec: int, command_usec: int, commands_processed: int, queued_commands: int, budget_usec: int, systems: Array[Dictionary]) -> void:
	var bounded_systems: Array[Dictionary] = []
	for index in range(mini(systems.size(), MAX_SYSTEMS)):
		var source: Dictionary = systems[index]
		var id: Variant = source.get("system_id")
		if typeof(id) != TYPE_STRING or String(id).is_empty() or String(id).length() > 128:
			continue
		var counters: Dictionary = {}
		var values: Variant = source.get("counters", {})
		if typeof(values) == TYPE_DICTIONARY:
			var inspected: int = 0
			for key in values:
				if inspected >= MAX_COUNTERS:
					break
				inspected += 1
				if typeof(key) != TYPE_STRING or String(key).is_empty() or String(key).length() > 64:
					continue
				var value: Variant = values[key]
				if (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value)):
					counters[key] = value
		bounded_systems.append({"system_id": id, "elapsed_usec": int(source.get("elapsed_usec", 0)), "counters": counters})
	var sample: Dictionary = {
		"schema_version": 1, "tick_number": tick_number, "elapsed_usec": elapsed_usec,
		"command_usec": command_usec, "commands_processed": commands_processed,
		"queued_commands": queued_commands, "budget_usec": budget_usec,
		"over_budget": elapsed_usec > budget_usec, "systems": bounded_systems,
	}
	if _samples.size() < _capacity:
		_samples.append(sample)
	else:
		_samples[_next] = sample
		_overwritten += 1
	_next = (_next + 1) % _capacity


## Most recent requested samples, returned oldest first and deeply detached.
func snapshot(limit: int = 120) -> Dictionary:
	var count: int = mini(clampi(limit, 0, _capacity), _samples.size())
	var records: Array[Dictionary] = []
	var start: int = (_next - count + _samples.size()) % maxi(1, _samples.size())
	for offset in range(count):
		records.append(_samples[(start + offset) % _samples.size()].duplicate(true))
	return {"schema_version": 1, "capacity": _capacity, "retained_samples": _samples.size(), "overwritten_samples": _overwritten, "samples": records}


func clear() -> void:
	_samples.clear()
	_next = 0
	_overwritten = 0
