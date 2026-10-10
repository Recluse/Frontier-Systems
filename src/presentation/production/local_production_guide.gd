extends RefCounted
class_name LocalProductionGuide

## Session-only presentation checklist. Never grants resources or progression.
var _extracted_milligrams: int = 0
var _unloaded_milligrams: int = 0
var _refined_batches: int = 0
var _crafted: bool = false
var _physical_plate: bool = false
var _recycled: bool = false
var _recrafted: bool = false
var _requested_recipe: String = ""


## Called only for confirmed commands from this panel's own actor.
func note_command(operation: String, payload: Dictionary) -> void:
	if operation == "extract" and payload.get("deposit_id") == "deposit.iron":
		_extracted_milligrams = mini(2000000, _extracted_milligrams + int(payload["amount_milligrams"]))
	elif operation == "unload_cargo" and payload.get("material") == "ore.iron":
		_unloaded_milligrams = mini(2000000, _unloaded_milligrams + int(payload["amount_milligrams"]))
	elif operation == "process":
		_requested_recipe = payload["recipe_id"]
	elif operation == "materialize_plate":
		_physical_plate = true
	elif operation == "recycle_component" and _physical_plate:
		_recycled = true
	elif operation == "cancel":
		cancel_recipe()


## Authoritative completion notification; accepting a job does not complete a step.
func note_batch_completed(recipe_id: String) -> void:
	if _requested_recipe != recipe_id:
		return
	_requested_recipe = ""
	if recipe_id == "refine.iron":
		_refined_batches = mini(2, _refined_batches + 1)
	elif recipe_id == "craft.plate":
		_crafted = true
		if _recycled:
			_recrafted = true
	elif recipe_id == "salvage.plate" and _crafted:
		_recycled = true


func cancel_recipe() -> void:
	_requested_recipe = ""


func text() -> String:
	var done: Array[bool] = [_extracted_milligrams >= 2000000, _unloaded_milligrams >= 2000000, _refined_batches >= 2, _crafted, _physical_plate, _recycled, _recrafted]
	var count: int = 0
	for complete in done:
		if complete:
			count += 1
	var next: String
	if not done[0]:
		next = "Approach Iron ore. Extract 1000 g into your canister twice (%d / 2000 g collected)." % (_extracted_milligrams / 1000)
	elif not done[1]:
		next = "Return to the workstation and unload 1000 g iron ore twice (%d / 2000 g unloaded)." % (_unloaded_milligrams / 1000)
	elif not done[2]:
		next = "Run Refine iron ore twice and wait for completion (%d / 2 batches)." % _refined_batches
	elif not done[3]:
		next = "Print a plate using 1 kg of refined iron."
	elif not done[4]:
		next = "Collect the printed plate into your inventory."
	elif not done[5]:
		next = "Recycle the carried plate to recover its iron."
	elif not done[6]:
		next = "Print another plate with recovered iron to finish the loop."
	else:
		next = "Loop complete for this session. Explore ice, regolith and material transport."
	if not _requested_recipe.is_empty():
		next += " A recipe is in progress; cancellation will not count as completion."
	return "Collection guide: %d / 7 steps\n%s" % [count, next]


func suggested_action() -> Dictionary:
	if not _requested_recipe.is_empty():
		return {"operation": "", "label": "Wait for the active recipe"}
	if _extracted_milligrams < 2000000:
		return {"operation": "extract", "label": "Collect 1 kg iron ore", "payload": {"deposit_id": "deposit.iron", "amount_milligrams": 1000000}}
	if _unloaded_milligrams < 2000000:
		return {"operation": "unload_cargo", "label": "Unload 1 kg iron ore", "payload": {"material": "ore.iron", "amount_milligrams": 1000000}}
	if _refined_batches < 2:
		return {"operation": "process", "label": "Refine one iron ore batch", "payload": {"recipe_id": "refine.iron"}}
	if not _crafted or (_recycled and not _recrafted):
		return {"operation": "process", "label": "Print a plate", "payload": {"recipe_id": "craft.plate"}}
	if not _physical_plate:
		return {"operation": "materialize_plate", "label": "Collect the printed plate", "payload": {}}
	if not _recycled:
		return {"operation": "recycle_component", "label": "Recycle the carried plate", "payload": {}}
	return {"operation": "", "label": "Collection loop complete"}
