extends SceneTree

class Sessions extends InventoryControllerSessionProvider:
	func permits_inventory(principal: StringName, session: StringName, world: StringName, region: StringName) -> bool:
		return principal == ACTOR and session == &"session.acceptance" and world == WorldRuntime.DEFAULT_WORLD_ID and region == WorldRuntime.DEFAULT_REGION_ID

const ACTOR: StringName = &"local-inventory-actor"
var _failures: int = 0
var _base: String
var _directories: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_base = OS.get_user_data_dir().path_join("inventory-durable-test-%d" % Time.get_ticks_usec())
	var source: Dictionary = _runtime(_fixture("lifecycle"))
	var token: InventoryControllerToken = _bind(source)
	var original_owner: Dictionary = _snapshot(source)["owner"]
	_send(source, token, "grip.durable", "grip_join", {"session_id": "session.crate", "expected_revision": 0, "target_id": "fixture.salvage-crate", "action": "move_world_object", "hand_ids": ["hand.right"]})
	_send(source, token, "take.durable", "start", _intent(source))
	_step(source, 179)
	_check(_snapshot(source)["jobs"][0]["job"]["progress_ticks"] == 179, "save one progress tick before completion")
	var saved: Dictionary = await _save(source, 1)
	_check(saved["systems"]["inventory"]["owner"] == _json(original_owner), "final-tick disk snapshot conserves full original owner")
	var directory: String = source["directory"]
	_destroy(source)

	# Initialize a replacement queue/authority BEFORE loading, to test its restore fence.
	var restored: Dictionary = _runtime(directory, false)
	var stale: InventoryControllerToken = _bind(restored)
	var queue: InventoryRuntimeCommandQueue = restored["queue"]
	_check(queue.enqueue(stale, _context(), "volatile.resume", "resume", {"job_id": "take.durable"}).is_success, "replacement has a volatile pre-load intent")
	_check(restored["store"].configure(restored["world"], directory).is_success, "durable adapter restores into replacement world")
	_check(restored["world"].current_tick_number() == int(saved["tick_number"]), "world tick restores from committed envelope")
	_check(_snapshot(restored)["jobs"][0]["job"]["state"] == "paused", "durable restored final-tick job is paused")
	_check(_snapshot(restored)["grips"]["sessions"][0]["paused"], "durable recovery pauses actual cooperative grip reservation")
	_check(queue.advance_tick(int(saved["tick_number"]) + 1, 1.0 / 60.0).error_code == &"queue_restored", "restore fence consumes no inventory tick")
	_check(queue.profiling_counters()["pending"] == 0 and queue.profiling_counters()["discarded"] == 1, "pre-load volatile intent is discarded exactly once")
	_check(not queue.local_observation(stale, _context()).is_success, "pre-load controller cannot read recovered owner")
	var paused: Dictionary = await _save(restored, 2)
	_check(paused["systems"]["inventory"]["jobs"][0]["job"]["state"] == "paused", "paused final-tick record itself is persisted")
	_destroy(restored)

	# A second replacement loads the durable paused record, rather than a subsystem copy.
	restored = _runtime(directory, false)
	stale = _bind(restored)
	queue = restored["queue"]
	_check(restored["store"].configure(restored["world"], directory).is_success, "second replacement loads paused disk checkpoint")
	_check(queue.advance_tick(int(paused["tick_number"]) + 1, 1.0 / 60.0).error_code == &"queue_restored", "second replacement synchronizes without advancement")
	_start(restored)
	_step(restored, 180)
	_check(_snapshot(restored)["jobs"][0]["job"]["progress_ticks"] == 179 and _json(_snapshot(restored)["owner"]) == paused["systems"]["inventory"]["owner"], "180 ticks never auto-complete paused durable work")
	_check(_json(_snapshot(restored)["grips"]) == paused["systems"]["inventory"]["grips"], "paused grip record also remains exact after 180 ticks")
	_check(restored["authority"].reconcile_after_restore().is_success, "explicit reconciliation retires pre-load identity")
	token = _bind(restored)
	_check(not queue.local_observation(stale, _context()).is_success, "fresh bind cannot revive old token")
	_send(restored, token, "resume.invalidated", "resume", {"job_id": "take.durable"}, false)
	_check(_snapshot(restored)["jobs"].is_empty() and _json(_snapshot(restored)["owner"]) == paused["systems"]["inventory"]["owner"], "fresh bind invalidates saved work without matter or receipt changes")
	_check(_snapshot(restored)["grips"]["sessions"].is_empty(), "fresh bind releases restored participating grip")
	_send(restored, token, "take.complete", "start", _intent(restored))
	_step(restored, 179)
	_check(_snapshot(restored)["owner"]["receipts"].is_empty(), "fresh transfer has no premature receipt")
	_step(restored, 1)
	var completed_owner: Dictionary = _snapshot(restored)["owner"]
	_check(completed_owner["receipts"].size() == 1, "exact completion tick creates one receipt")
	var conserved: Dictionary = completed_owner.duplicate(true)
	# Compare all item fields; only the intended container location changes.
	var items: Array = conserved["ledger"]["items"]
	var original_items: Array = original_owner["ledger"]["items"]
	for index in range(items.size()):
		if items[index]["item_id"] == "crowbar-1":
			_check(items[index]["container_id"] == "body.human-2", "intended item moves to actor body")
			items[index]["container_id"] = original_items[index]["container_id"]
	_check(_json(items) == _json(original_items), "all stable item records and provenance conserved except intended location")
	var completed: Dictionary = await _save(restored, 3)
	_check(completed["systems"]["inventory"]["owner"] == _json(completed_owner), "disk snapshot retains exact completed owner and receipt")
	_destroy(restored)

	var recovered: Dictionary = _runtime(directory, false)
	stale = _bind(recovered)
	queue = recovered["queue"]
	_check(queue.enqueue(stale, _context(), "take.complete", "start", _intent(recovered)).is_success, "pre-load duplicate intent is volatile")
	_check(recovered["store"].configure(recovered["world"], directory).is_success, "completed checkpoint loads into new world/queue/authority")
	_check(queue.advance_tick(int(completed["tick_number"]) + 1, 1.0 / 60.0).error_code == &"queue_restored" and queue.profiling_counters()["pending"] == 0, "completed restore cannot replay queued duplicate")
	_check(_json(_snapshot(recovered)["owner"]) == completed["systems"]["inventory"]["owner"], "load preserves exact serialized completed owner")
	_check(recovered["authority"].reconcile_after_restore().is_success, "completed checkpoint reconciliation")
	token = _bind(recovered)
	_start(recovered)
	var retry: Dictionary = _intent(recovered)
	retry["expected_revision"] = 0
	_send(recovered, token, "take.complete", "start", retry, false)
	_step(recovered, 180)
	_check(_json(_snapshot(recovered)["owner"]) == completed["systems"]["inventory"]["owner"], "retained completion retry and ticks preserve exact owner and one receipt")
	_destroy(recovered)
	_test_refusal(paused)
	for path in _directories:
		for filename in DirAccess.get_files_at(path):
			_check(DirAccess.remove_absolute(path.path_join(filename)) == OK, "remove temporary checkpoint")
		_check(DirAccess.remove_absolute(path) == OK, "remove temporary storage directory")
	_check(DirAccess.remove_absolute(_base) == OK, "remove temporary storage root")
	print("Durable queued inventory checkpoint acceptance: %d failures" % _failures)
	quit(0 if _failures == 0 else 1)


func _test_refusal(paused: Dictionary) -> void:
	for fault in ["truncated", "checksum", "job_epoch", "owner_receipt"]:
		var directory: String = _fixture(fault)
		var candidate: Dictionary = paused.duplicate(true)
		if fault == "job_epoch":
			candidate["systems"]["inventory"]["jobs"][0]["job"]["target_action_epoch"] = 999
		elif fault == "owner_receipt":
			candidate["systems"]["inventory"]["owner"]["receipts"].append({"request_id": "invented"})
		var snapshot: String = JSON.stringify(candidate)
		var text: String = JSON.stringify({"schema_version": 1, "sequence": 1, "snapshot_json": snapshot, "sha256": snapshot.sha256_text() if fault != "checksum" else "bad"})
		if fault == "truncated":
			text = text.substr(0, 20)
		var path: String = directory.path_join("world-b.json")
		_check(CheckpointFileIO.new().write_text(path, text).is_success, "write isolated corrupt checkpoint")
		var fresh: Dictionary = _runtime(directory, false)
		var token: InventoryControllerToken = _bind(fresh)
		_check(fresh["queue"].enqueue(token, _context(), "refusal.pending", "resume", {"job_id": "take.durable"}).is_success, "refusal fixture retains existing volatile intent")
		var before: String = fresh["world"].capture_world_snapshot_json().value
		var counters: Dictionary = fresh["queue"].profiling_counters()
		var observation: Dictionary = fresh["queue"].local_observation(token, _context()).value
		var loaded: ServiceResult = fresh["store"].configure(fresh["world"], directory)
		_check(not loaded.is_success, fault + " refused by storage/domain boundary")
		_check(fresh["world"].capture_world_snapshot_json().value == before and fresh["queue"].profiling_counters() == counters and fresh["queue"].local_observation(token, _context()).value == observation, fault + " refusal preserves complete world, queue and authority")
		_check(fresh["store"].status()["saved_tick"] == -1 and not fresh["store"].status()["busy"] and FileAccess.get_file_as_string(path) == text, fault + " refusal acknowledges no save and preserves source bytes")
		_check(fresh["store"].request_checkpoint().error_code == &"checkpoint_busy", "failed configure cannot write over corrupt source")
		_destroy(fresh)


func _runtime(directory: String, configure: bool = true) -> Dictionary:
	var world := WorldRuntime.new()
	root.add_child(world)
	var inventory := world.get_simulation_system(InventorySimulationSystem.SYSTEM_ID) as InventorySimulationSystem
	var queue := InventoryRuntimeCommandQueue.new()
	_check(queue.initialize(inventory, world.world_id, world.region_id, Sessions.new(), 4, 1).is_success, "compose real inventory with one bounded queue")
	var store := WorldPersistenceAdapter.new()
	root.add_child(store)
	store.set_process(false)
	var runtime: Dictionary = {"world": world, "inventory": inventory, "queue": queue, "authority": queue.controller_authority(), "store": store, "directory": directory}
	if configure:
		_check(store.configure(world, directory).is_success, "configure empty temporary store")
		_start(runtime)
	return runtime


func _start(runtime: Dictionary) -> void:
	_check(runtime["world"].start_simulation().is_success, "start actual world")
	runtime["world"].get_node("SimulationRunner").set_physics_process(false)


func _step(runtime: Dictionary, count: int) -> Array:
	var runner: SimulationRunner = runtime["world"].get_node("SimulationRunner")
	var results: Array = []
	for index in range(count):
		# Test-only composition: queue exclusively advances inventory; the actual runner
		# advances all remaining systems. Re-register before any checkpoint capture.
		_check(runner.unregister_system(InventorySimulationSystem.SYSTEM_ID), "exclude double inventory advancement")
		var advanced: ServiceResult = runtime["queue"].advance_tick(runner.tick_number + 1, 1.0 / 60.0)
		_check(advanced.is_success, "one consecutive queued inventory tick")
		if advanced.is_success:
			results = advanced.value
		runner._physics_process(1.0 / 60.0)
		_check(runner.register_system(runtime["inventory"]), "restore complete world system set before capture")
	return results


func _save(runtime: Dictionary, sequence: int) -> Dictionary:
	var captured: String = runtime["world"].capture_world_snapshot_json().value
	var tick: int = runtime["world"].current_tick_number()
	var acknowledgements: Array = []
	var callback: Callable = func(saved_tick: int, result: ServiceResult) -> void: acknowledgements.append({"tick": saved_tick, "result": result})
	runtime["store"].checkpoint_completed.connect(callback)
	_check(runtime["store"].request_checkpoint().is_success, "queue asynchronous durable checkpoint")
	var deadline: int = Time.get_ticks_msec() + 5000
	while runtime["store"].status()["busy"] and Time.get_ticks_msec() < deadline:
		runtime["store"]._process(0.0)
		await process_frame
	_check(not runtime["store"].status()["busy"] and acknowledgements.size() == 1 and acknowledgements[0]["tick"] == tick and acknowledgements[0]["result"].is_success and runtime["store"].status()["saved_tick"] == tick, "one matching durable acknowledgement")
	runtime["store"].checkpoint_completed.disconnect(callback)
	var disk: ServiceResult = LocalWorldSaveStore.read_latest(runtime["directory"])
	_check(disk.is_success and int(disk.value["sequence"]) == sequence and disk.value["snapshot_json"] == captured, "committed two-slot checksum envelope reads back captured world exactly")
	return JSON.parse_string(disk.value["snapshot_json"])


func _bind(runtime: Dictionary) -> InventoryControllerToken:
	var epoch: int = int(_snapshot(runtime)["bodies"][1]["control_epoch"])
	_check(runtime["authority"].bind(&"body.human-2", ACTOR, &"session.acceptance", epoch).is_success, "fresh trusted bind at canonical epoch")
	return runtime["authority"].pin(_context()).value


func _context() -> AuthenticatedCommandContext:
	return AuthenticatedCommandContext.from_authenticated_session(ACTOR, &"session.acceptance", WorldRuntime.DEFAULT_WORLD_ID, WorldRuntime.DEFAULT_REGION_ID, PackedStringArray(["inventory.operate"]))


func _intent(runtime: Dictionary) -> Dictionary:
	return {"action": "take", "target_body_id": "body.human-1", "target_container_id": "storage.pouch-1", "item_id": "crowbar-1", "slot_id": "", "destination_container_id": "body.human-2", "expected_revision": int(_snapshot(runtime)["owner"]["state_revision"])}


func _send(runtime: Dictionary, token: InventoryControllerToken, id: String, operation: String, payload: Dictionary, success: bool = true) -> void:
	_check(runtime["queue"].enqueue(token, _context(), id, operation, payload).is_success, "enqueue " + id)
	var results: Array = _step(runtime, 1)
	_check(results.size() == 1 and results[0]["result"].is_success == success, "queued result " + id)


func _snapshot(runtime: Dictionary) -> Dictionary:
	return runtime["inventory"].capture_snapshot().value


func _json(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value))


func _fixture(name: String) -> String:
	var path: String = _base.path_join(name)
	_check(DirAccess.make_dir_recursive_absolute(path) == OK, "create isolated temporary storage")
	_directories.append(path)
	return path


func _destroy(runtime: Dictionary) -> void:
	runtime["store"].free()
	runtime["world"].free()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)

