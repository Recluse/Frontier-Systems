extends RefCounted
class_name MachineryOperationFeedback

## Detached scoped telemetry only. Never predicts host acceptance or power delivery.
var _tick: int = -1
var _previous: Dictionary = {}
var _observed: Dictionary = {}
var machines: Dictionary = {}
var grid_text: String = "Machinery observation unavailable."


func observe(production: Dictionary) -> bool:
	if production.is_empty():
		_tick = -1
		_previous.clear()
		_clear()
		return false
	if not WorkstationResourceView.valid(production):
		_previous.clear()
		_clear()
		grid_text = "Invalid machinery observation discarded; prerequisites unavailable."
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
		var preview_job: String = "No active batch observed"
		var prior: Dictionary = _previous.get(id, {})
		if job.is_empty() and not prior.is_empty():
			job_text += " · previous batch ended; completion/cancellation not distinguished"
			preview_job = "Batch ended · outcome unconfirmed"
		elif not job.is_empty():
			var activity: String = "Awaiting progress observation"
			if job["paused"]: activity = "Paused · Resume required"
			elif not placement["enabled"] or frame_condition == 0: activity = "Not advancing · disabled/broken frame"
			elif not prior.is_empty() and prior["recipe"] == job["recipe"] and tick > _tick:
				activity = "Running · observed progress" if int(job["progress"]) > int(prior["progress"]) else "Not advancing · parts/power/feedstock/capacity may block"
			job_text = "%s · %d ticks · %d J spent · %s" % [job["recipe"], job["progress"], job["energy_spent"], activity]
			preview_job = "%s · %d ticks\n%s" % [job["recipe"], job["progress"], "Paused · Resume" if job["paused"] else ("Progress observed" if activity.begins_with("Running") else "Awaiting / blocked")]
		if tick == _tick and job == prior and prior_text.has(id):
			job_text = prior_text[id]["job"]
			preview_job = prior_text[id]["preview_job"]
		next[id] = job.duplicate(true)
		var preview_condition: String = ""
		if not broken.is_empty(): preview_condition = "\nBroken modules retained"
		elif not damaged.is_empty(): preview_condition = "\nDamaged modules"
		elif not unknown.is_empty(): preview_condition = "\nModule condition unobserved"
		machines[id] = {"text": "%s\n%s\n%s\n%s" % [state, "; ".join(capabilities), power, job_text], "job": job_text, "preview_job": preview_job, "preview_text": "%s%s\nBuffer %d J\n%s" % [state, preview_condition, energy, preview_job]}
	grid_text = "Observed grid: %d frame buffers total %d J · %d cable links. Buffers are separate; links do not certify delivery or job readiness. Host validates operations." % [workshop["placements"].size(), total, workshop["links"].size()]
	if tick > _tick:
		_previous = next
	_tick = tick
	_observed = production.duplicate(true)
	return true


func _clear() -> void:
	machines.clear()
	_observed.clear()
	grid_text = "Machinery observation unavailable."


static func _condition(workshop: Dictionary, id: String) -> int:
	for physical in workshop["inventory_items"]:
		if physical["item_id"] == id: return int(physical["condition_permille"])
	return -1


## Describe only scoped records; do not quote output allocation or readiness.
func recipe_text(machine_id: String, recipe_id: String) -> String:
	if _observed.is_empty(): return "Recipe prerequisites unavailable: wait for a valid current observation."
	var workshop: Dictionary = _observed["machinery"]
	if not workshop["placements"].has(machine_id): return "Selected machine is not observed deployed; recipe prerequisites unavailable."
	var lines := PackedStringArray(["Selected recipe: " + recipe_id])
	var requirements: Dictionary = _observed.get("recipe_requirements", {}).get(recipe_id, {})
	if requirements.is_empty():
		lines.append("Input, energy and required work-head quote unavailable for this recipe in the current observation.")
	else:
		var head: String = "printhead" if requirements["station"] == "printer" else "refinery"
		lines.append("Host catalog inputs: %s; batch energy %d J. Required components: power, controller, %s." % [WorkstationResourceView.stock_text(requirements["inputs"]), requirements["energy_joules"], head])
	var totals: Dictionary = {}
	var carriers := PackedStringArray()
	var unknown_contents: bool = false
	for module in workshop["mounts"]:
		if workshop["mounts"][module] != machine_id or workshop["parts"][module]["kind"] != "socket": continue
		for physical in workshop["inventory_items"]:
			if physical["container_id"] != InventorySimulationSystem.factory_storage_id(module) or not physical["definition_id"] in ["item.resource-canister.prototype", "item.resource-canister.fabricated"]: continue
			var id: String = physical["item_id"]
			var stock: Dictionary = workshop["cargo"].get(id, {})
			if not workshop["cargo"].has(id): unknown_contents = true
			carriers.append("%s (socket %s): %s%s" % [id, module, WorkstationResourceView.stock_text(stock) if workshop["cargo"].has(id) else "contents unavailable", " · socket broken/unobserved" if _condition(workshop, module) <= 0 else ""])
			if _condition(workshop, module) <= 0: continue
			for material in stock: totals[material] = int(totals.get(material, 0)) + int(stock[material])
	lines.append("Fitted input/output canisters: " + ("\n".join(carriers) if not carriers.is_empty() else "none observed"))
	for material in requirements.get("inputs", {}):
		var required: int = int(requirements["inputs"][material])
		var amount: int = int(totals.get(material, 0))
		lines.append("%s: observed at least %d / required %d mg in nonzero-condition sockets%s; host validates usable feedstock." % [material, amount, required, " (some contents unavailable)" if unknown_contents else ""])
	lines.append("Outputs use fitted empty or matching-material canisters. Output amounts, allocation and free capacity quote unavailable; host chooses and validates at execution.")
	var job: Dictionary = workshop["jobs"].get(machine_id, {})
	if not job.is_empty():
		lines.append("Observed batch: %s. %s" % [job["recipe"], "Paused: restore fitted parts/canisters and power, then explicitly Resume this existing batch; selection does not replace it." if job["paused"] else "Not paused; progress and acceptance remain host-observed."])
	else: lines.append("No active batch observed to resume.")
	lines.append("Enabled state, component condition and frame-local buffer are shown above. Delivery, reach, permission and current revision remain host checks; no automatic resume or retry.")
	return "\n".join(lines)
