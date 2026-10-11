extends "res://tests/godot/inventory_durable_checkpoint_test.gd"

class ClosureSessions extends InventoryControllerSessionProvider:
	func permits_inventory(principal: StringName, session: StringName, world: StringName, region: StringName) -> bool:
		return principal in [ACTOR, TARGET] and session in [&"session.acceptance", &"session.target"] and world == WorldRuntime.DEFAULT_WORLD_ID and region == WorldRuntime.DEFAULT_REGION_ID

const TARGET: StringName = &"local-inventory-target"


func _run() -> void:
	_base = OS.get_user_data_dir().path_join("closed-durable-test-%d" % Time.get_ticks_usec())
	var source: Dictionary = _runtime(_fixture("closed"))
	var actor: InventoryControllerToken = _bind(source)
	var target: InventoryControllerToken = _bind_target(source)
	var before: Dictionary = _snapshot(source)["owner"]
	var knowledge: Dictionary = source["queue"].own_inventory_observation(target, _target_context(), true).value
	# Close both existing levels through the real queue; never install a candidate owner.
	_close_send(source, target, "close.inner", "close_container", _closure(source, "storage.pouch-1"))
	var exact: Dictionary = _closure(source, "storage.backpack-1")
	_close_send(source, target, "close.outer", "close_container", exact)
	_send(source, actor, "search.unaffected", "start", _search(source))
	_step(source, 119)
	var closed: Dictionary = _snapshot(source)
	_check(closed["schema_version"] == 5 and closed["owner"]["schema_version"] == 2 and closed["owner"]["ledger"]["schema_version"] == 2, "actual closure upgrades matching v5/v2/v2 records")
	_check(closed["owner"]["ledger"]["items"] == before["ledger"]["items"], "nested closures conserve every item/provenance field")
	var closed_knowledge: Dictionary = source["queue"].own_inventory_observation(target, _target_context(), true).value
	_check(closed_knowledge["mass_milligrams"] == knowledge["mass_milligrams"] and closed_knowledge["items"] == knowledge["items"], "nested closure conserves complete owned knowledge and mass")
	var saved: Dictionary = await _save(source, 1)
	_check(not saved["systems"]["tools"]["ledger"]["parts"].is_empty(), "existing fixture supplies nonempty component material and condition records")
	var directory: String = source["directory"]
	_destroy(source)

	var restored: Dictionary = _runtime(directory, false)
	var stale: InventoryControllerToken = _bind(restored)
	var stale_target: InventoryControllerToken = _bind_target(restored)
	_check(restored["queue"].enqueue(stale, _context(), "volatile.search", "start", _search(restored)).is_success, "pre-load intent belongs to real replacement queue")
	_check(restored["store"].configure(restored["world"], directory).is_success, "actual adapter loads checksum-validated v5 world checkpoint")
	_check(restored["world"].current_tick_number() == int(saved["tick_number"]), "committed world tick restored")
	_check(restored["queue"].advance_tick(int(saved["tick_number"]) + 1, 1.0 / 60.0).error_code == &"queue_restored", "restore synchronization consumes no tick")
	_check(restored["queue"].profiling_counters()["pending"] == 0 and restored["queue"].profiling_counters()["discarded"] == 1, "restore discards exactly one volatile intent")
	_check(not restored["queue"].own_inventory_observation(stale, _context()).is_success and not restored["queue"].own_inventory_observation(stale_target, _target_context()).is_success, "both old opaque tokens fenced")
	_check(_json(_snapshot(restored)["owner"]) == saved["systems"]["inventory"]["owner"], "complete closed owner including receipt/revisions restored exactly")
	_check(_snapshot(restored)["jobs"][0]["job"]["state"] == "paused", "unaffected final-tick search restores paused")
	_start(restored)
	_step(restored, 180)
	_check(_snapshot(restored)["jobs"][0]["job"]["progress_ticks"] == 119 and _snapshot(restored)["jobs"][0]["job"]["state"] == "paused", "180 ticks cannot finish restored paused search")
	_check(_json(_snapshot(restored)["owner"]) == saved["systems"]["inventory"]["owner"], "paused ticks mint no receipts or closure revision")
	var current: Dictionary = JSON.parse_string(restored["world"].capture_world_snapshot_json().value)
	for system in ["production", "terrain", "tools"]:
		var advanced: Dictionary = current["systems"][system].duplicate(true)
		advanced["last_tick"] = saved["systems"][system]["last_tick"]
		_check(advanced == saved["systems"][system], "existing " + system + " records conserved except expected tick advancement")
	_check(restored["authority"].reconcile_after_restore().is_success, "trusted reconciliation fences restored controller epochs")
	target = _bind_target(restored)
	actor = _bind(restored)
	_check(not restored["queue"].own_inventory_observation(stale_target, _target_context()).is_success, "fresh bind never revives old closure token")
	var retry_before: Dictionary = _snapshot(restored)["owner"]
	_close_send(restored, target, "close.outer", "close_container", exact)
	_check(_snapshot(restored)["owner"] == retry_before, "exact retained closure receipt returns without second shared/ledger revision")
	_close_send(restored, target, "close.outer", "open_container", exact, false)
	_check(_snapshot(restored)["owner"] == retry_before, "conflicting retained closure ID rejected without mutation")
	_close_send(restored, target, "blocked.inner", "open_container", _closure(restored, "storage.pouch-1"), false)
	_send(restored, actor, "blocked.take", "start", _intent(restored), false)
	_check(_snapshot(restored)["owner"] == retry_before, "recovered closed ancestry blocks interior commands without matter changes")
	var recovered_knowledge: Dictionary = restored["queue"].own_inventory_observation(target, _target_context(), true).value
	_check(_json(recovered_knowledge["items"]) == _json(closed_knowledge["items"]) and recovered_knowledge["mass_milligrams"] == closed_knowledge["mass_milligrams"], "recovered owned item records and carried mass unchanged")
	_close_send(restored, target, "open.outer", "open_container", _closure(restored, "storage.backpack-1"))
	_check(not _container(_snapshot(restored), "storage.pouch-1")["is_open"], "reopening outer does not implicitly open nested pouch")
	_send(restored, actor, "blocked.inner.take", "start", _intent(restored), false)
	_close_send(restored, target, "open.inner", "open_container", _closure(restored, "storage.pouch-1"))
	_send(restored, actor, "take.resumed", "start", _intent(restored))
	_step(restored, 179)
	var open_saved: Dictionary = await _save(restored, 2)
	_destroy(restored)
	await _paused_closure(directory, open_saved)
	_refuse_closure(saved, open_saved)
	for path in _directories:
		for filename in DirAccess.get_files_at(path):
			_check(DirAccess.remove_absolute(path.path_join(filename)) == OK, "remove disposable checkpoint")
		_check(DirAccess.remove_absolute(path) == OK, "remove disposable directory")
	_check(DirAccess.remove_absolute(_base) == OK, "remove temporary storage root")
	print("Closed inventory durable world recovery: %d failures" % _failures)
	quit(0 if _failures == 0 else 1)


func _paused_closure(directory: String, saved: Dictionary) -> void:
	var restored: Dictionary = _runtime(directory, false)
	_bind(restored)
	_bind_target(restored)
	_check(restored["store"].configure(restored["world"], directory).is_success, "replacement loads real open v5 final-tick checkpoint")
	_check(restored["queue"].advance_tick(int(saved["tick_number"]) + 1, 1.0 / 60.0).error_code == &"queue_restored", "paused take restore fence")
	_start(restored)
	_step(restored, 180)
	_check(_snapshot(restored)["jobs"][0]["job"]["state"] == "paused" and _snapshot(restored)["jobs"][0]["job"]["progress_ticks"] == 179, "durable open v5 final-tick take never auto-completes")
	var before: Dictionary = _snapshot(restored)["owner"]
	# Internal authenticated dispatch uses the same physical owner checks, as in the
	# existing paused closure fixture. A fresh bind would first invalidate this job.
	var context := _target_context()
	var tick: int = restored["world"].current_tick_number() + 1
	_check(restored["inventory"].apply_local(context, "close.paused.durable", "close_container", _closure(restored, "storage.backpack-1"), tick).is_success, "fixed-tick closure cancels actual restored paused take")
	_check(restored["inventory"].apply_local(context, "reopen.paused.durable", "open_container", _closure(restored, "storage.backpack-1"), tick).is_success, "same-boundary reopening uses owner revision")
	_step(restored, 1)
	_check(_snapshot(restored)["jobs"].is_empty() and _snapshot(restored)["owner"]["ledger"]["items"] == before["ledger"]["items"], "same-boundary reopen cannot resurrect paused take or move matter")
	var final_saved: Dictionary = await _save(restored, 3)
	_check(final_saved["systems"]["inventory"]["jobs"].is_empty(), "durable readback retains cancellation")
	_destroy(restored)


func _refuse_closure(closed: Dictionary, open_job: Dictionary) -> void:
	for fault in ["numeric", "string", "null", "missing", "root", "version", "closed_job"]:
		var candidate: Dictionary = (open_job if fault == "closed_job" else closed).duplicate(true)
		var inventory: Dictionary = candidate["systems"]["inventory"]
		var container: Dictionary = _container(inventory, "storage.backpack-1")
		match fault:
			"numeric": container["is_open"] = 0
			"string": container["is_open"] = "false"
			"null": container["is_open"] = null
			"missing": container.erase("is_open")
			"root": _container(inventory, "body.human-1")["is_open"] = false
			"version": inventory["schema_version"] = 4
			"closed_job": container["is_open"] = false
		var directory: String = _fixture("refuse-" + fault)
		# Persist an unmodified genuine older world first. Domain-invalid newer
		# closure must not be silently bypassed, even with a usable older slot.
		var older_json: String = JSON.stringify(closed)
		_check(LocalWorldSaveStore.write_checkpoint(directory, 1, older_json).is_success, "seed genuine older committed checkpoint")
		var altered_json: String = JSON.stringify(candidate)
		_check(LocalWorldSaveStore.write_checkpoint(directory, 2, altered_json).is_success, "commit checksummed malformed domain candidate")
		_check(LocalWorldSaveStore.read_latest(directory).value["snapshot_json"] == altered_json, "storage validates checksum and selects newer envelope")
		var bytes_a: String = FileAccess.get_file_as_string(directory.path_join("world-a.json"))
		var bytes_b: String = FileAccess.get_file_as_string(directory.path_join("world-b.json"))
		var live: Dictionary = _runtime(directory, false)
		var token: InventoryControllerToken = _bind(live)
		var target: InventoryControllerToken = _bind_target(live)
		_check(live["queue"].enqueue(token, _context(), "pending.refusal", "start", _search(live)).is_success, "retain pending live queue on refused startup")
		var before: String = live["world"].capture_world_snapshot_json().value
		var counters: Dictionary = live["queue"].profiling_counters()
		var generation: int = live["inventory"].controller_restore_generation()
		var observation: Dictionary = live["queue"].own_inventory_observation(target, _target_context(), true).value
		var result: ServiceResult = live["store"].configure(live["world"], directory)
		_check(not result.is_success, fault + " fails at real world/domain startup validation")
		_check(live["world"].capture_world_snapshot_json().value == before and live["inventory"].controller_restore_generation() == generation, fault + " refusal preserves whole live world/tick/generation atomically")
		_check(live["queue"].profiling_counters() == counters and live["queue"].own_inventory_observation(target, _target_context(), true).value == observation, fault + " refusal preserves queue and valid controller observation")
		_check(live["store"].status()["saved_tick"] == -1 and not live["store"].status()["busy"] and live["store"].request_checkpoint().error_code == &"checkpoint_busy", fault + " refuses writable adoption")
		_check(FileAccess.get_file_as_string(directory.path_join("world-a.json")) == bytes_a and FileAccess.get_file_as_string(directory.path_join("world-b.json")) == bytes_b, fault + " retains both source slots without domain fallback")
		_destroy(live)


func _runtime(directory: String, configure: bool = true, files: CheckpointFileIO = null) -> Dictionary:
	var world := WorldRuntime.new()
	# Use the repository's versioned production inventory fixture and its
	# existing owners; enable before initialization, never synthesize payloads.
	world.resource_carriers_enabled = true
	root.add_child(world)
	var inventory := world.get_simulation_system(InventorySimulationSystem.SYSTEM_ID) as InventorySimulationSystem
	var queue := InventoryRuntimeCommandQueue.new()
	_check(queue.initialize(inventory, world.world_id, world.region_id, ClosureSessions.new(), 4, 1).is_success, "actual owners and bounded authenticated queue")
	var store := WorldPersistenceAdapter.new()
	root.add_child(store)
	store.set_process(false)
	var runtime: Dictionary = {"world": world, "inventory": inventory, "queue": queue, "authority": queue.controller_authority(), "store": store, "directory": directory}
	if configure:
		_check(store.configure(world, directory, files).is_success, "configure temporary native store")
		_start(runtime)
	return runtime


func _target_context() -> AuthenticatedCommandContext:
	return AuthenticatedCommandContext.from_authenticated_session(TARGET, &"session.target", WorldRuntime.DEFAULT_WORLD_ID, WorldRuntime.DEFAULT_REGION_ID, PackedStringArray(["inventory.operate"]))


func _bind_target(runtime: Dictionary) -> InventoryControllerToken:
	var epoch: int = int(_snapshot(runtime)["bodies"][0]["control_epoch"])
	_check(runtime["authority"].bind(&"body.human-1", TARGET, &"session.target", epoch).is_success, "trusted target bind")
	return runtime["authority"].pin(_target_context()).value


func _closure(runtime: Dictionary, id: String) -> Dictionary:
	return {"container_id": id, "expected_revision": int(_snapshot(runtime)["owner"]["state_revision"])}


func _search(runtime: Dictionary) -> Dictionary:
	return {"action": "search", "target_body_id": "body.human-1", "target_container_id": "body.human-1", "item_id": "", "slot_id": "", "destination_container_id": "", "expected_revision": int(_snapshot(runtime)["owner"]["state_revision"])}


func _close_send(runtime: Dictionary, token: InventoryControllerToken, id: String, operation: String, payload: Dictionary, success: bool = true) -> void:
	_check(runtime["queue"].enqueue(token, _target_context(), id, operation, payload).is_success, "enqueue " + id)
	var results: Array = _step(runtime, 1)
	_check(results.size() == 1 and results[0]["result"].is_success == success, "apply " + id)


func _container(snapshot: Dictionary, id: String) -> Dictionary:
	for container in snapshot["owner"]["ledger"]["containers"]:
		if container["container_id"] == id:
			return container
	_check(false, "existing canonical container " + id)
	return {}
