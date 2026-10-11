extends RefCounted
class_name MachineryOperationFeedback

## Detached scoped telemetry only. Never predicts host acceptance or power delivery.
var _tick: int = -1
var _previous: Dictionary = {}
var machines: Dictionary = {}
var grid_text: String = "Machinery observation unavailable."


func observe(production: Dictionary) -> bool:
	if production.is_empty():
		_tick = -1
		_previous.clear()
		_clear()
		return false
	var tick: int = int(production["last_tick"])
	if tick < _tick:
		_previous.clear()
		_clear()
		grid_text = "Stale machinery observation discarded; waiting for current host telemetry."
		return false
	var workshop: Dictionary = production["machinery"]
	var total: int = 0
	var next: Dictionary = {}
	var prior_text: Dictionary = machines.duplicate(true)
	machines.clear()
	for id in workshop["placements"]:
		var placement: Dictionary = workshop["placements"][id]
		var fitted: PackedStringArray = []
		var usable: PackedStringArray = []
		var damaged: PackedStringArray = []
		var broken: PackedStringArray = []
		var unknown: PackedStringArray = []
		for module in workshop["mounts"]:
			if workshop["mounts"][module] != id: continue
			var kind: String = workshop["parts"][module]["kind"]
			fitted.append(kind)
			var condition: int = _condition(workshop, module)
			if condition < 0: unknown.append(kind)
			elif condition == 0: broken.append(kind)
			else:
				usable.append(kind)
				if condition < 1000: damaged.append(kind)
		var frame_condition: int = _condition(workshop, id)
		var state: String = "Enabled" if placement["enabled"] else "Isolated / disabled"
		if frame_condition == 0: state += " · broken frame (retained)"
		elif frame_condition < 0: state += " · frame condition unknown"
		elif frame_condition < 1000: state += " · damaged frame %d/1000" % frame_condition
		var capabilities: PackedStringArray = []
		for kind in ["solar", "router", "extractor", "refinery", "printhead", "autolathe"]:
			if not fitted.has(kind): continue
			var missing: PackedStringArray = []
			for required in ["power", "controller", kind]:
				if not usable.has(required): missing.append(required)
			capabilities.append(kind + (": components observed with nonzero condition" if missing.is_empty() else ": missing/broken/unobserved " + ", ".join(missing)))
		if capabilities.is_empty(): capabilities.append("No work head / generator / router observed")
		if not broken.is_empty(): capabilities.append("Broken modules retained: " + ", ".join(broken))
		if not damaged.is_empty(): capabilities.append("Damaged modules: " + ", ".join(damaged))
		if not unknown.is_empty(): capabilities.append("Condition unobserved: " + ", ".join(unknown))
		var energy: int = int(placement["energy"])
		total += energy
		var power: String = "Buffer %d J" % energy
		if energy == 0: power += " · empty; delivery unconfirmed"
		var job: Dictionary = workshop["jobs"].get(id, {})
		var job_text: String = "No active batch observed"
		var prior: Dictionary = _previous.get(id, {})
		if job.is_empty() and not prior.is_empty():
			job_text += " · previous batch ended; completion/cancellation not distinguished"
		elif not job.is_empty():
			var activity: String = "Awaiting progress observation"
			if job["paused"]: activity = "Paused · Resume required"
			elif not placement["enabled"] or frame_condition == 0: activity = "Not advancing · disabled/broken frame"
			elif not prior.is_empty() and prior["recipe"] == job["recipe"] and tick > _tick:
				activity = "Running · observed progress" if int(job["progress"]) > int(prior["progress"]) else "Not advancing · parts/power/feedstock/capacity may block"
			job_text = "%s · %d ticks · %d J spent · %s" % [job["recipe"], job["progress"], job["energy_spent"], activity]
		if tick == _tick and job == prior and prior_text.has(id):
			job_text = prior_text[id]["job"]
		next[id] = job.duplicate(true)
		machines[id] = {"text": "%s\n%s\n%s\n%s" % [state, "; ".join(capabilities), power, job_text], "job": job_text}
	grid_text = "Observed grid: %d frame buffers total %d J · %d cable links. Buffers are separate; links do not certify delivery or job readiness. Host validates operations." % [workshop["placements"].size(), total, workshop["links"].size()]
	if tick > _tick:
		_previous = next
	_tick = tick
	return true


func _clear() -> void:
	machines.clear()
	grid_text = "Machinery observation unavailable."


static func _condition(workshop: Dictionary, id: String) -> int:
	for physical in workshop["inventory_items"]:
		if physical["item_id"] == id: return int(physical["condition_permille"])
	return -1
