extends SceneTree

## Inject only the socket output boundary; exercise actual host admission, invite
## authentication, fixed-tick world queue and completion route without a listener.
class RecordingHost extends FirstPlayableHost:
	var frames: Array[Dictionary] = []
	func _send(id: int, value: Dictionary) -> void:
		frames.append({"peer": id, "frame": value.duplicate(true)})

class RecordingSocket extends RefCounted:
	var closed: bool = false
	func close(_code: int, _reason: String = "") -> void:
		closed = true

var failures: int = 0
var host: RecordingHost
var world: WorldRuntime
var inventory: InventorySimulationSystem

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func snapshot() -> Dictionary:
	return inventory.capture_snapshot().value["owner"]

func add_peer(id: int) -> RecordingSocket:
	var socket := RecordingSocket.new()
	host._peers[id] = {"socket": socket, "slot": -1, "created": Time.get_ticks_msec(), "last_move": Time.get_ticks_msec(), "pending_move": false, "window": Time.get_ticks_msec(), "commands": 0}
	return socket

func frame(id: String, operation: String, revision: int) -> Dictionary:
	return {"type": "command", "request_id": id, "system": "inventory", "operation": operation, "payload": {"container_id": "storage.backpack-1", "expected_revision": revision}}

func apply(peer: int, value: Dictionary) -> Dictionary:
	host._events.clear()
	host.frames.clear()
	host._receive(peer, value)
	world.get_node("SimulationRunner")._physics_process(1.0 / 60.0)
	var replies: Array[Dictionary] = host.frames.duplicate()
	for event in host._events: replies.append(event)
	for reply in replies:
		if reply["peer"] == peer and reply["frame"].get("request_id") == value["request_id"]: return reply["frame"]
	check(false, "exact host reply for " + value["request_id"])
	return {"ok": false}

func run() -> void:
	world = WorldRuntime.new()
	root.add_child(world)
	check(world.start_simulation().is_success, "actual runtime fixture")
	world.get_node("SimulationRunner").set_physics_process(false)
	inventory = world.get_simulation_system(InventorySimulationSystem.SYSTEM_ID)
	host = RecordingHost.new()
	root.add_child(host)
	host.set_process(false)
	host._world = world
	host._keys = ["closure-route-actor-invite-000000000000", "closure-route-owner-invite-000000000000"]
	world.command_completed.connect(host._on_completed)
	add_peer(1)
	add_peer(2)
	var unauthenticated: RecordingSocket = add_peer(3)
	host._receive(1, {"type": "authenticate", "key": host._keys[0]})
	host._receive(2, {"type": "authenticate", "key": host._keys[1]})
	check(host._peers[1]["slot"] == 0 and host._peers[2]["slot"] == 1, "actual invite authentication selects server-owned principals")
	var before: Dictionary = snapshot()
	var close_frame: Dictionary = frame("route.close", "close_container", before["state_revision"])
	host._receive(3, close_frame)
	check(unauthenticated.closed and host._pending.is_empty(), "unauthenticated closure denied before queue admission")
	var foreign: Dictionary = apply(1, frame("route.foreign", "close_container", before["state_revision"]))
	check(not foreign["ok"] and snapshot() == before, "authenticated foreign body cannot close owner storage")
	var denied: Dictionary = apply(2, frame("route.unknown", "unlock_container", before["state_revision"]))
	check(not denied["ok"] and denied["code"] == "system_denied" and snapshot() == before, "new admission does not allow arbitrary inventory operations")
	var close_reply: Dictionary = apply(2, close_frame)
	check(close_reply["ok"] and host._pending.is_empty(), "host route admits close through actual fixed-tick owner")
	var closed: Dictionary = snapshot()
	check(closed["ledger"]["items"] == before["ledger"]["items"], "host-routed closure conserves exact matter/provenance")
	var observation: Dictionary = inventory.own_inventory_observation(host._context(1, 2), true).value
	check(PlayerInventoryPresentation.owned_container(observation, "storage.backpack-1")["is_open"] == false, "host-routed close visible in actual scoped v4 observation")
	var retry: Dictionary = apply(2, close_frame)
	check(retry == close_reply and snapshot() == closed, "exact original routed retry returns retained receipt without revision mutation")
	var stale: Dictionary = apply(2, frame("route.stale", "open_container", before["state_revision"]))
	check(not stale["ok"] and snapshot() == closed, "host-routed stale revision fails atomically")
	var forged: Dictionary = frame("route.forged", "open_container", closed["state_revision"])
	forged["payload"]["body_id"] = "body.human-1"
	check(not apply(2, forged)["ok"] and snapshot() == closed, "forged body field cannot replace host-authenticated context")
	var opened: Dictionary = apply(2, frame("route.open", "open_container", closed["state_revision"]))
	check(opened["ok"], "host route admits exact open operation")
	observation = inventory.own_inventory_observation(host._context(1, 2), true).value
	check(PlayerInventoryPresentation.owned_container(observation, "storage.backpack-1")["is_open"] == true, "routed open establishes observed state")
	check(snapshot()["ledger"]["items"] == before["ledger"]["items"], "both routed operations conserve canonical items")
	host.free()
	world.free()
	quit(0 if failures == 0 else 1)
