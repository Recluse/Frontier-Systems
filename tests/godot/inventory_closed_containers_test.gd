extends SceneTree

class Sessions extends InventoryControllerSessionProvider:
	var enabled: bool = true
	func permits_inventory(principal: StringName, session: StringName, world: StringName, region: StringName) -> bool:
		return enabled and principal in [ACTOR, TARGET] and session in [&"one", &"target", &"two"] and world == &"world.test" and region == &"region.test"

const ACTOR: StringName = &"local-inventory-actor"
const TARGET: StringName = &"local-inventory-target"
var failures: int = 0
var tick: int = 0
var health: HealthSimulationSystem
var inventory: InventorySimulationSystem
var queue: InventoryRuntimeCommandQueue
var sessions := Sessions.new()
var actor: InventoryControllerToken
var target: InventoryControllerToken

func _initialize() -> void:
	inventory = InventorySimulationSystem.new()
	check(inventory.configure_defaults().is_success, "actual runtime defaults")
	health = HealthSimulationSystem.new()
	check(health.configure_bodies(["body.human-1", "body.human-2"]).is_success and inventory.bind_health(health).is_success, "actual health capability provider")
	queue = InventoryRuntimeCommandQueue.new()
	check(queue.initialize(inventory, &"world.test", &"region.test", sessions).is_success, "authenticated queue")
	var authority: InventoryControllerAuthority = queue.controller_authority()
	check(authority.bind(&"body.human-2", ACTOR, &"one", 0).is_success, "actor bind")
	check(authority.bind(&"body.human-1", TARGET, &"target", 0).is_success, "target bind")
	actor = authority.pin(context()).value
	target = authority.pin(context(true)).value
	var initial: Dictionary = snapshot()
	var knowledge: Dictionary = queue.own_inventory_observation(target, context(true), true).value
	# Independent actor job outside the closed ancestor remains untouched.
	send(actor, context(), "search.root", "start", intent("search", "body.human-1"))
	var unaffected: Dictionary = snapshot()["jobs"][0]
	send(target, context(true), "close.outer", "close_container", closure("storage.backpack-1"))
	check(snapshot()["jobs"][0]["job"]["progress_ticks"] == int(unaffected["job"]["progress_ticks"]) + 1, "unrelated open-root job progresses normally")
	check(snapshot()["owner"]["ledger"]["items"] == initial["owner"]["ledger"]["items"], "closure preserves every item/provenance record")
	var closed_knowledge: Dictionary = queue.own_inventory_observation(target, context(true), true).value
	check(closed_knowledge["items"] == knowledge["items"] and closed_knowledge["mass_milligrams"] == knowledge["mass_milligrams"], "owned knowledge and carried mass preserved")
	check(closed_knowledge["schema_version"] == 4 and not closed_knowledge["container_records"][1]["is_open"], "detailed closure state versioned")
	send(actor, context(), "cancel.root", "cancel", {"job_id": "search.root"})
	var before: Dictionary = snapshot()["owner"]
	send(actor, context(), "foreign.open", "open_container", closure("storage.backpack-1"), false)
	send(target, context(true), "nested.close", "close_container", closure("storage.pouch-1"), false)
	send(target, context(true), "closed.remove", "self", move("storage.pouch-1", "body.human-1"), false)
	send(actor, context(), "closed.search", "start", intent("search"), false)
	check(not inventory.prepare_equipment_change(context(true), "recycle.closed", "crowbar-1", false, {}, "item.crowbar.prototype").is_success, "factory recycler cannot remove from closed ancestor")
	var graph: Dictionary = snapshot()["owner"].duplicate(true)
	graph["ledger"]["items"][2]["container_id"] = "body.human-1"
	check(not inventory.prepare_factory_graph(context(true), graph, snapshot()["world_storage"], "factory.closed", {}).is_success, "trusted factory graph checks closed source path")
	graph = snapshot()["owner"].duplicate(true)
	graph["ledger"]["containers"][2]["is_open"] = true
	check(not inventory.prepare_factory_graph(context(true), graph, snapshot()["world_storage"], "factory.reopen", {}).is_success, "factory cannot rewrite closure state")
	graph = snapshot()["owner"].duplicate(true)
	graph["ledger"]["items"].append({"item_id": "factory.pouch", "definition_id": "item.pouch.prototype", "definition_revision": 1, "condition_permille": 1000, "container_id": "body.human-1"})
	var storage: Dictionary = graph["ledger"]["containers"][3].duplicate(true)
	storage["container_id"] = "storage.factory-pouch"
	storage["owner_item_id"] = "factory.pouch"
	storage.erase("is_open")
	graph["ledger"]["containers"].append(storage)
	var prepared: ServiceResult = inventory.prepare_factory_graph(context(true), graph, snapshot()["world_storage"], "factory.new", {})
	check(prepared.is_success and prepared.value["owner"]["ledger"]["containers"].back()["is_open"], "prospective factory storage initialized open without committing fixture matter")
	check(snapshot()["owner"] == before, "all closed-path and wrong-actor rejects conserve owner")
	send(target, context(true), "open.outer", "open_container", closure("storage.backpack-1"))
	send(actor, context(), "search.open", "start", intent("search"))
	step(120)
	check(queue.read_search(actor, context(), "search.open").is_success, "reopen permits actual timed search")
	check(not queue.read_search(target, context(true), "search.open").is_success, "search principal isolation")
	send(actor, context(), "take.final", "start", intent("take"))
	step(179)
	var job_checkpoint: Dictionary = JSON.parse_string(JSON.stringify(snapshot()))
	before = snapshot()["owner"]
	var exact: Dictionary = closure("storage.backpack-1")
	send(target, context(true), "close.final", "close_container", exact)
	check(snapshot()["jobs"].is_empty(), "same-final-tick closure cancels timed transfer before completion")
	check(snapshot()["owner"]["ledger"]["items"] == before["ledger"]["items"], "interrupted take commits no item movement")
	check(not queue.read_search(actor, context(), "search.open").is_success, "closure invalidates previously completed search view")
	var outcomes: Array = queue.local_observation(actor, context()).value["outcomes"]
	check(outcomes.back()["error_code"] == "inventory_container_closed", "bounded explicit interrupted-job outcome")
	before = snapshot()["owner"]
	send(target, context(true), "close.final", "close_container", exact)
	check(snapshot()["owner"] == before, "retained exact retry has no second closure revision")
	send(target, context(true), "close.final", "open_container", closure("storage.backpack-1"), false)
	check(snapshot()["owner"] == before, "conflicting retained ID is inert")
	send(target, context(true), "open.again", "open_container", closure("storage.backpack-1"))
	send(target, context(true), "remove.open", "self", move("storage.pouch-1", "body.human-1"))
	send(target, context(true), "close.insert", "close_container", closure("storage.backpack-1"))
	before = snapshot()["owner"]
	send(target, context(true), "insert.closed", "self", move("body.human-1", "storage.pouch-1"), false)
	check(snapshot()["owner"] == before, "closed ancestor blocks insertion too")
	send(target, context(true), "root.close", "close_container", closure("body.human-1"), false)
	var wrong: Dictionary = closure("storage.backpack-1")
	wrong["expected_revision"] = 0
	send(target, context(true), "stale.revision", "open_container", wrong, false)
	before = snapshot()["owner"]
	sessions.enabled = false
	send(target, context(true), "revoked.session", "open_container", closure("storage.backpack-1"), false)
	sessions.enabled = true
	check(authority.replace(&"body.human-1", TARGET, &"two", 1).is_success, "replace controller")
	send(target, context(true), "stale.token", "open_container", closure("storage.backpack-1"), false)
	check(snapshot()["owner"] == before, "revoked and stale controller cannot change closures")
	# A closed shell can move; no descendant is accessed or exposed by world reads.
	# Fresh replacement identity is required for subsequent commands.
	var replacement_context: AuthenticatedCommandContext = AuthenticatedCommandContext.from_authenticated_session(TARGET, &"two", &"world.test", &"region.test", PackedStringArray(["inventory.operate"]))
	target = authority.pin(replacement_context).value
	send(target, replacement_context, "drop.shell", "world", {"operation": "drop", "item_id": "backpack-1", "world_container_id": "world.tray-1", "destination_container_id": "", "slot_id": "", "expected_revision": int(snapshot()["owner"]["state_revision"])})
	var world_read: Dictionary = queue.world_inventory_observation(actor, context()).value
	check(world_read["containers"][0]["items"].size() == 1 and world_read["containers"][0]["items"][0]["item_id"] == "backpack-1", "closed exterior visible without descendants")
	send(target, replacement_context, "world.open", "open_container", closure("storage.backpack-1"), false)
	send(target, replacement_context, "pickup.shell", "world", {"operation": "pickup", "item_id": "backpack-1", "world_container_id": "world.tray-1", "destination_container_id": "body.human-1", "slot_id": "back", "expected_revision": int(snapshot()["owner"]["state_revision"])})
	check(not snapshot()["owner"]["ledger"]["containers"][2]["is_open"], "moving shell preserves canonical closure")
	paused_recovery(job_checkpoint)
	resource_carrier_access()
	# Restore is validated atomically before touching the live owner/generation.
	var live_before: Dictionary = snapshot()
	var saved: Dictionary = JSON.parse_string(JSON.stringify(live_before))
	check(saved["schema_version"] == 5 and saved["owner"]["schema_version"] == 2, "closure snapshot version agreement")
	for bad_value in [0, "false", null]:
		var bad: Dictionary = saved.duplicate(true)
		bad["owner"]["ledger"]["containers"][2]["is_open"] = bad_value
		var generation: int = inventory.controller_restore_generation()
		check(not inventory.restore_snapshot_record(bad, tick).is_success and snapshot() == live_before and inventory.controller_restore_generation() == generation, "malformed closure restore is atomic")
	var bad_root: Dictionary = saved.duplicate(true)
	bad_root["owner"]["ledger"]["containers"][0]["is_open"] = false
	check(not inventory.restore_snapshot_record(bad_root, tick).is_success and snapshot() == live_before, "closed root rejected atomically")
	check(inventory.restore_snapshot_record(saved, tick).is_success and JSON.parse_string(JSON.stringify(snapshot())) == saved, "closed-state JSON recovery")
	check(queue.advance_tick(tick + 1, 1.0 / 60.0).error_code == &"queue_restored", "restore fences queue")
	check(not queue.own_inventory_observation(actor, context()).is_success, "restore fences old token")
	check(inventory.restore_snapshot_record(initial, 0).is_success and snapshot()["schema_version"] == 4, "legacy snapshot retains open semantics without matter creation")
	inventory.free()
	health.free()
	print("Closed containers: %d failures" % failures)
	quit(0 if failures == 0 else 1)

func paused_recovery(saved: Dictionary) -> void:
	var restored := InventorySimulationSystem.new()
	var restored_health := HealthSimulationSystem.new()
	check(restored.configure_defaults().is_success and restored_health.configure_bodies(["body.human-1", "body.human-2"]).is_success and restored.bind_health(restored_health).is_success, "isolated recovery runtime")
	var saved_tick: int = int(saved["last_tick"])
	check(restored.restore_snapshot_record(saved, saved_tick).is_success and restored.capture_snapshot().value["jobs"][0]["job"]["state"] == "paused", "unfinished JSON recovery pauses job")
	var bad: Dictionary = saved.duplicate(true)
	bad["owner"]["ledger"]["containers"][2]["is_open"] = false
	var before: Dictionary = restored.capture_snapshot().value
	check(not restored.restore_snapshot_record(bad, saved_tick).is_success and restored.capture_snapshot().value == before, "closed-path saved job rejected atomically")
	check(restored.apply_local(context(true), "close.paused", "close_container", {"container_id": "storage.backpack-1", "expected_revision": int(saved["owner"]["state_revision"])}, saved_tick + 1).is_success, "fixed-tick closure interrupts restored paused job")
	check(restored.apply_local(context(true), "reopen.paused", "open_container", {"container_id": "storage.backpack-1", "expected_revision": int(restored.capture_snapshot().value["owner"]["state_revision"])}, saved_tick + 1).is_success, "same-boundary reopen")
	restored.simulate_tick(saved_tick + 1, 1.0 / 60.0)
	check(restored.capture_snapshot().value["jobs"].is_empty() and restored.capture_snapshot().value["owner"]["ledger"]["items"] == saved["owner"]["ledger"]["items"], "paused interruption preserves item matter")
	restored.free()
	restored_health.free()

func resource_carrier_access() -> void:
	var runtime := InventorySimulationSystem.new()
	var runtime_health := HealthSimulationSystem.new()
	check(runtime.configure_defaults(true).is_success and runtime_health.configure_bodies(["body.human-1", "body.human-2"]).is_success and runtime.bind_health(runtime_health).is_success, "resource carrier runtime")
	var saved: Dictionary = runtime.capture_snapshot().value
	for item in saved["owner"]["ledger"]["items"]:
		if item["definition_id"] == "item.resource-canister.prototype": item["container_id"] = "storage.backpack-1"
	check(runtime.restore_snapshot_record(saved, 0).is_success, "existing carrier nested without adding matter")
	var carriers: ServiceResult = runtime.owned_resource_carriers(context(true))
	check(carriers.is_success and not carriers.value.is_empty(), "open owned carrier capability")
	check(runtime.apply_local(context(true), "carrier.close", "close_container", {"container_id": "storage.backpack-1", "expected_revision": 0}, 1).is_success, "close carrier ancestor")
	runtime.simulate_tick(1, 1.0 / 60.0)
	check(runtime.owned_resource_carriers(context(true)).value.is_empty(), "owned knowledge cannot authorize production carrier access through closure")
	check(runtime.capture_snapshot().value["owner"]["ledger"]["items"] == saved["owner"]["ledger"]["items"], "carrier closure conserves physical matter")
	runtime.free()
	runtime_health.free()

func context(is_target: bool = false) -> AuthenticatedCommandContext:
	return AuthenticatedCommandContext.from_authenticated_session(TARGET if is_target else ACTOR, &"target" if is_target else &"one", &"world.test", &"region.test", PackedStringArray(["inventory.operate"]))

func snapshot() -> Dictionary:
	return inventory.capture_snapshot().value

func closure(id: String) -> Dictionary:
	return {"container_id": id, "expected_revision": int(snapshot()["owner"]["state_revision"])}

func move(source: String, destination: String) -> Dictionary:
	return {"operation": "move", "item_id": "crowbar-1", "source_container_id": source, "destination_container_id": destination, "slot_id": "", "expected_revision": int(snapshot()["owner"]["state_revision"])}

func intent(action: String, container: String = "storage.pouch-1") -> Dictionary:
	return {"action": action, "target_body_id": "body.human-1", "target_container_id": container, "item_id": "crowbar-1" if action == "take" else "", "slot_id": "", "destination_container_id": "body.human-2" if action == "take" else "", "expected_revision": int(snapshot()["owner"]["state_revision"])}

func send(token: InventoryControllerToken, auth: AuthenticatedCommandContext, id: String, operation: String, payload: Dictionary, success: bool = true) -> void:
	check(queue.enqueue(token, auth, id, operation, payload).is_success, "enqueue " + id)
	var outcomes: Array = step(1)
	check(outcomes.size() == 1 and outcomes[0]["result"].is_success == success, "apply " + id + (": " + outcomes[0]["result"].message if outcomes.size() == 1 else ": no outcome"))

func step(count: int) -> Array:
	var outcomes: Array = []
	for index in range(count):
		tick += 1
		var result: ServiceResult = queue.advance_tick(tick, 1.0 / 60.0)
		check(result.is_success, "fixed queue tick")
		if result.is_success: outcomes = result.value
	return outcomes

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
