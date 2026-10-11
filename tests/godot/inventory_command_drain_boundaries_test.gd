extends SceneTree

class Sessions extends InventoryControllerSessionProvider:
	var allowed: bool = true
	var on_check: Callable
	var checks: int = 0
	var trigger: int = 1
	func permits_inventory(_principal: StringName, _session: StringName, _world: StringName, _region: StringName) -> bool:
		if on_check.is_valid():
			checks += 1
			if checks == trigger:
				var callback: Callable = on_check
				on_check = Callable()
				callback.call()
		return allowed

var _failures: int = 0

func _initialize() -> void:
	for effect in ["advance", "advance_denied", "free", "free_denied", "restore", "restore_reconciled"]:
		for trigger in [1, 2]:
			_boundary(effect, trigger)
	_normal_callback()
	print("Inventory drain callback boundaries: %d failures" % _failures)
	quit(0 if _failures == 0 else 1)

func _boundary(effect: String, trigger: int) -> void:
	var inventory := InventorySimulationSystem.new()
	var health := HealthSimulationSystem.new()
	var queue := InventoryRuntimeCommandQueue.new()
	var sessions := Sessions.new()
	_check(inventory.configure_defaults().is_success, "actual runtime")
	_check(health.configure_bodies(["body.human-1", "body.human-2"]).is_success and inventory.bind_health(health).is_success, "actual health")
	_check(queue.initialize(inventory, &"world.test", &"region.test", sessions, 3, 2).is_success, "bounded queue")
	var authority: InventoryControllerAuthority = queue.controller_authority()
	_check(authority.bind(&"body.human-2", &"local-inventory-actor", &"one", 0).is_success, "actual controller")
	var token: InventoryControllerToken = authority.pin(_context()).value
	for index in range(3):
		_check(queue.enqueue(token, _context(), "callback.%d" % index, "self", _intent(index)).is_success, "pending FIFO")
	var saved: Dictionary = inventory.capture_snapshot().value
	var observed: Array[Dictionary] = []
	sessions.trigger = trigger
	sessions.on_check = func() -> void:
		_check(queue.enqueue(token, _context(), "reentrant", "self", _intent(0)).error_code == &"queue_unavailable", "busy enqueue")
		_check(queue.advance_tick(1, 1.0 / 60.0).error_code == &"queue_unavailable", "busy drain")
		if effect.begins_with("free"):
			inventory.free()
		elif effect.begins_with("advance"):
			inventory.simulate_tick(1, 1.0 / 60.0)
		else:
			_check(inventory.restore_snapshot_record(saved, 0).is_success, "actual restore")
			if effect == "restore_reconciled":
				_check(authority.reconcile_after_restore().is_success, "callback reconciliation")
				_check(authority.bind(&"body.human-2", &"local-inventory-actor", &"one", 1).is_success, "callback rebind")
		if is_instance_valid(inventory):
			observed.append(inventory.capture_snapshot().value)
		if effect.ends_with("denied"):
			sessions.allowed = false
	var result: ServiceResult = queue.advance_tick(1, 1.0 / 60.0)
	var expected: StringName = &"queue_restored"
	if effect.begins_with("free"):
		expected = &"queue_unavailable"
	elif effect.begins_with("advance"):
		expected = &"queue_tick_mismatch"
	var label := effect + " at attempt " + str(trigger)
	_check(not result.is_success and result.error_code == expected and result.value == null, label + " fails closed without outcomes")
	_check(not queue.get("_busy"), label + " releases busy")
	var counters: Dictionary = queue.profiling_counters()
	_check(counters["pending"] == 0 and counters["attempts"] == trigger and counters["discarded"] == 3 - trigger, label + " accounts attempted and discarded intents")
	_check(counters["rejections"] == 3, label + " counts two reentrant refusals and interrupted boundary")
	if is_instance_valid(inventory):
		_check(observed.size() == 1, label + " actually invoked provider callback")
	if is_instance_valid(inventory) and not observed.is_empty():
		_check(inventory.capture_snapshot().value == observed[0], label + " no stale dispatch, extra job tick or unrelated mutation")
		if effect.begins_with("advance"):
			_check(queue.advance_tick(1, 1.0 / 60.0).error_code == &"queue_tick_mismatch" and inventory.capture_snapshot().value == observed[0], label + " no double advance")
		else:
			if effect != "restore_reconciled":
				_check(authority.reconcile_after_restore().is_success, "restore reconciliation after boundary")
				_check(authority.bind(&"body.human-2", &"local-inventory-actor", &"one", 1).is_success, "fresh bind")
			token = authority.pin(_context()).value
			_check(queue.enqueue(token, _context(), "fresh", "self", _intent(0)).is_success, "fresh intent after restore")
			var resumed: ServiceResult = queue.advance_tick(1, 1.0 / 60.0)
			_check(resumed.is_success and resumed.value.size() == 1 and resumed.value[0]["result"].is_success, "restore releases busy and permits fresh draining")
			_check(inventory.capture_snapshot().value["last_tick"] == 1, "fresh boundary advances once")
		inventory.free()

	health.free()

func _normal_callback() -> void:
	var inventory := InventorySimulationSystem.new()
	var health := HealthSimulationSystem.new()
	var queue := InventoryRuntimeCommandQueue.new()
	var sessions := Sessions.new()
	_check(inventory.configure_defaults().is_success, "normal runtime")
	_check(health.configure_bodies(["body.human-1", "body.human-2"]).is_success and inventory.bind_health(health).is_success, "normal health")
	_check(queue.initialize(inventory, &"world.test", &"region.test", sessions, 3, 2).is_success, "normal queue")
	var authority: InventoryControllerAuthority = queue.controller_authority()
	_check(authority.bind(&"body.human-2", &"local-inventory-actor", &"one", 0).is_success, "normal bind")
	var token: InventoryControllerToken = authority.pin(_context()).value
	for index in range(3):
		_check(queue.enqueue(token, _context(), "normal.%d" % index, "self", _intent(index)).is_success, "normal enqueue")
	sessions.on_check = func() -> void:
		_check(queue.advance_tick(1, 1.0 / 60.0).error_code == &"queue_unavailable", "normal callback fences reentrancy")
	var drained: ServiceResult = queue.advance_tick(1, 1.0 / 60.0)
	_check(drained.is_success and drained.value.size() == 2 and drained.value[0]["result"].is_success and drained.value[1]["result"].is_success, "benign callback preserves normal FIFO")
	var before: Dictionary = inventory.capture_snapshot().value
	sessions.checks = 0
	sessions.on_check = func() -> void: sessions.allowed = false
	drained = queue.advance_tick(2, 1.0 / 60.0)
	_check(drained.is_success and drained.value.size() == 1 and not drained.value[0]["result"].is_success, "ordinary denial consumes only an attempt and still ticks")
	var after: Dictionary = inventory.capture_snapshot().value
	_check(after["last_tick"] == 2, "ordinary denial advances once")
	after["last_tick"] = before["last_tick"]
	_check(after == before, "ordinary denial conserves inventory")
	var counters: Dictionary = queue.profiling_counters()
	_check(counters["attempts"] == 3 and counters["discarded"] == 0 and counters["pending"] == 0 and not queue.get("_busy"), "normal callback accounting")
	inventory.free()
	health.free()


func _context() -> AuthenticatedCommandContext:
	return AuthenticatedCommandContext.from_authenticated_session(&"local-inventory-actor", &"one", &"world.test", &"region.test", PackedStringArray(["inventory.operate"]))

func _intent(revision: int) -> Dictionary:
	return {"operation": "switch_hand", "item_id": "", "source_container_id": "", "destination_container_id": "", "slot_id": "", "expected_revision": revision}

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)


