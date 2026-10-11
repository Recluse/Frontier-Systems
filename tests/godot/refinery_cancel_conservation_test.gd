extends "res://tests/godot/machinery_cancel_recovery_test.gd"

var refinery: String


func recovery_machine() -> String:
	return refinery


func recovery_recipe() -> String:
	return "refine.ice"


func finish() -> void:
	# The inherited paid finite loop already extracted exactly 1 kg ice. Move
	# that existing physical canister into its existing refinery via commands.
	var machinery: Dictionary = production.capture_snapshot().value["machinery"]
	var generator: String = ""
	for module in machinery["mounts"]:
		match machinery["parts"][module]["kind"]:
			"refinery": refinery = machinery["mounts"][module]
			"solar": generator = machinery["mounts"][module]
	var extractor: String = super.recovery_machine()
	move([-5250, 0, -1000])
	for cable in machinery["links"]:
		var link: Dictionary = machinery["links"][cable]
		move(machinery["placements"][link["a"]]["position"])
		command("machine_unwire", {"machine_id": link["a"], "item_id": cable})
	move([-6000, 0, -1000])
	var extraction_socket: String = ""
	for module in machinery["mounts"]:
		if machinery["mounts"][module] == extractor and machinery["parts"][module]["kind"] == "socket": extraction_socket = module
	command("machine_remove", {"machine_id": extractor, "item_id": "resource-canister-1", "socket_id": extraction_socket})
	move([-3000, 0, -1000])
	command("machine_pack", {"machine_id": generator})
	move([0, 0, -1600])
	command("machine_deploy", {"machine_id": generator, "position": [-1100, 0, -1000], "mode": "surface"})
	command("machine_wire", {"machine_id": generator, "other_id": refinery, "item_id": machinery["links"].keys()[0]})
	var sockets: Array[String] = []
	for module in machinery["mounts"]:
		if machinery["mounts"][module] == refinery and machinery["parts"][module]["kind"] == "socket": sockets.append(module)
	check(sockets.size() == 2, "paid existing refinery has two independently crafted sockets")
	for index in range(2):
		command("machine_insert", {"machine_id": refinery, "item_id": "resource-canister-%d" % (index + 1), "socket_id": sockets[index]})
	step(90)
	var cargo: Dictionary = production.capture_snapshot().value["cargo"]
	check(cargo["resource-canister-1"]["ice"] == 1000000 and ProductionSimulationSystem._mass(cargo["resource-canister-2"]) == 0, "finite extracted input bill and empty output canister before refinery run")
	check(world.capture_world_snapshot_json().is_success, "command-prepared refinery validates full provenance")
	await super.finish()


func conserved(before: Dictionary, after: Dictionary, label: String) -> void:
	super.conserved(before, after, label)
	check(before["cargo"]["resource-canister-1"]["ice"] == 1000000 and after["cargo"]["resource-canister-1"]["ice"] == 1000000, label + " retains exact unconsumed refinery input bill")
	for carrier in ["resource-canister-1", "resource-canister-2"]:
		check(int(after["cargo"][carrier].get("water", 0)) == 0, label + " cannot create refinery water output")
