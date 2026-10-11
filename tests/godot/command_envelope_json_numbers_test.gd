extends SceneTree

const MAX_TICK: int = 9007199254740990
var failures: int = 0

func _initialize() -> void:
	var source: Dictionary = {"protocol_version": 1, "request_id": "request-1", "world_id": "world-1", "region_id": "region-1", "command_type": "airlock.action", "payload": {"quantity": 0.25, "count": 2}}
	for tick in [0, 42, MAX_TICK]:
		var record: Dictionary = source.duplicate(true)
		record["expected_tick_number"] = tick
		var parsed: ServiceResult = CommandEnvelope.from_json(JSON.stringify(record, "", true, true))
		check(parsed.is_success, "valid JSON integer envelope decodes")
		if parsed.is_success:
			check(parsed.value.expected_tick_number == tick, "expected tick normalizes exactly")
			check(parsed.value.payload == JSON.parse_string(JSON.stringify(record))["payload"], "command-specific payload is preserved")
			var roundtrip: ServiceResult = CommandEnvelope.from_json(JSON.stringify(parsed.value.to_dictionary(), "", true, true))
			check(roundtrip.is_success and roundtrip.value.to_dictionary() == parsed.value.to_dictionary(), "envelope roundtrips")
	check(CommandEnvelope.from_json(JSON.stringify(source)).is_success, "expected tick remains optional")
	for number in [-1, 0.5, MAX_TICK + 1, 9223372036854775807, NAN, INF, -INF, null, true, "1", [], {}]:
		var record: Dictionary = source.duplicate(true)
		record["expected_tick_number"] = number
		check(not CommandEnvelope.from_dictionary(record).is_success, "invalid expected tick rejects before conversion")
	for version in [null, true, "1", 1.5, 2, NAN, INF, []]:
		var record: Dictionary = source.duplicate(true)
		record["protocol_version"] = version
		check(not CommandEnvelope.from_dictionary(record).is_success, "invalid version rejects")
	var float_record: Dictionary = source.duplicate(true)
	float_record["protocol_version"] = 1.0
	float_record["expected_tick_number"] = 42.0
	check(CommandEnvelope.from_dictionary(float_record).is_success, "integral decoder floats are supported")
	for raw_tick in ["0.5", "-1", "9007199254740991", "1e100"]:
		var raw: String = JSON.stringify(source).trim_suffix("}") + ',"expected_tick_number":' + raw_tick + '}'
		check(not CommandEnvelope.from_json(raw).is_success, "invalid wire numbers reject")
	print("Command envelope JSON numbers: %d failures" % failures)
	quit(1 if failures else 0)

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
