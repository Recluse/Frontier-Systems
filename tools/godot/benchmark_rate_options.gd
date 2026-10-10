extends RefCounted
class_name BenchmarkRateOptions

## Development-only process configuration; never changes the saved project default.
const CANDIDATES: Array[int] = [60, 72, 90]


static func parse(arguments: PackedStringArray) -> ServiceResult:
	var rate: int = 60
	var seen: bool = false
	for argument in arguments:
		if argument.begins_with("--physics-hz="):
			var value: String = argument.trim_prefix("--physics-hz=")
			if seen or not ["60", "72", "90"].has(value):
				return ServiceResult.failure(&"invalid_benchmark_rate", "Use one --physics-hz=60, --physics-hz=72 or --physics-hz=90 argument.")
			rate = int(value)
			seen = true
	return ServiceResult.success({"physics_hz": rate, "tick_budget_usec": ceili(1000000.0 / float(rate)),
		"fixed_delta_seconds": 1.0 / float(rate), "configuration_only": arguments.has("--benchmark-config")})
