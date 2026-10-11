extends "res://tests/godot/machinery_runtime_test.gd"

var actor: AuthenticatedCommandContext
var crew: AuthenticatedCommandContext


func run() -> void:
	world = WorldRuntime.new()
	world.resource_carriers_enabled = true
	root.add_child(world)
	world.command_completed.connect(func(_command: SimulationCommand, result: ServiceResult) -> void: last = result)
	check(world.start_simulation().is_success, "placement world starts")
	runner = world.get_node("SimulationRunner")
	runner.set_physics_process(false)
	production = world.get_simulation_system(ProductionSimulationSystem.SYSTEM_ID)
	inventory = world.get_simulation_system(InventorySimulationSystem.SYSTEM_ID)
	actor = AuthenticatedCommandContext.for_local_development(&"local-inventory-actor", world.world_id, world.region_id)
	crew = AuthenticatedCommandContext.for_local_development(&"local-inventory-target", world.world_id, world.region_id)
	context = actor
	for batch in range(7):
		move([-3000, 0, -1000])
		command("extract", {"deposit_id": "deposit.iron", "carrier_id": "resource-canister-1", "amount_milligrams": 1000000})
		move([0, 0, 0])
		command("unload_cargo", {"carrier_id": "resource-canister-1", "material": "ore.iron", "amount_milligrams": 1000000})
		command("process", {"recipe_id": "refine.iron"})
		step(120)
	var first: String = craft("frame")
	var second: String = craft("frame")
	var expander: String = craft("expander")
	var sockets: Array[String] = []
	for index in range(6): sockets.append(craft("socket"))
	command("process", {"recipe_id": "craft.plate"})
	step(120)
	command("materialize_plate", {})
	var plate: String = production.observation(context).value["components"][0]
	deny("machine_deploy", {"machine_id": first, "position": [0, 0, 1000], "mode": "surface"}, "workbench keepout")
	move([-3000, 0, -2000])
	deny("machine_deploy", {"machine_id": first, "position": [-3000, 0, -1000], "mode": "surface"}, "finite source keepout")
	move([0, 0, -2500])
	deny("machine_deploy", {"machine_id": first, "position": [0, 0, -2500], "mode": "surface"}, "acting body keepout")
	move([0, 0, -1500])
	deny("machine_deploy", {"machine_id": first, "position": [0, 1, -2500], "mode": "surface"}, "floor Y rule")
	deny("machine_deploy", {"machine_id": first, "position": [0, 0, -5000], "mode": "freeform"}, "reach")
	deny("machine_deploy", {"machine_id": first, "position": [0, 0, -2500], "mode": "surface", "size": [1, 1, 1]}, "client bounds injection")
	var deployed_intent: Dictionary = {"machine_id": first, "position": [0.0, 0.0, -2500.0], "mode": "surface", "expected_revision": production.capture_snapshot().value["state_revision"]}
	command("machine_deploy", deployed_intent)
	var deployed_request: String = "machine-test-%d" % sequence
	var before_retry: Dictionary = canonical()
	check(production.apply_local(context, deployed_request, "machine_deploy", deployed_intent, runner.tick_number + 1).is_success, "retained deployment retry succeeds at original revision")
	check(canonical() == before_retry, "retained deployment retry has no second graph or matter mutation")
	move([1300, 0, -1500])
	deny("machine_deploy", {"machine_id": second, "position": [1299, 0, -2500], "mode": "surface"}, "one millimetre machine overlap")
	command("machine_deploy", {"machine_id": second, "position": [1300, 0, -2500], "mode": "surface"})
	move([0, 0, -1500])
	deny("machine_fit", {"machine_id": first, "item_id": expander, "socket_id": ""}, "expander growth into another machine")
	# Two authenticated crews at the same revision race to pack the shared frame.
	context = crew
	move([1300, 0, -1500])
	context = actor
	move([1300, 0, -1500])
	var revision: int = production.capture_snapshot().value["state_revision"]
	var winner := ProductionDevelopmentCommand.new()
	winner.command_id = &"placement-pack-winner"
	winner.authenticated_context = crew
	winner.operation = "machine_pack"
	winner.payload = {"machine_id": second, "expected_revision": revision}
	var loser := ProductionDevelopmentCommand.new()
	loser.command_id = &"placement-pack-loser"
	loser.authenticated_context = actor
	loser.operation = "machine_pack"
	loser.payload = winner.payload.duplicate(true)
	var outcomes: Array[bool] = []
	var capture: Callable = func(action: SimulationCommand, result: ServiceResult) -> void:
		if action.command_id in [winner.command_id, loser.command_id]: outcomes.append(result.is_success)
	world.command_completed.connect(capture)
	world.enqueue_command(winner)
	world.enqueue_command(loser)
	step()
	world.command_completed.disconnect(capture)
	check(outcomes == [true, false], "same revision cooperative packing has exactly one winner")
	check(MachineryWorkshop.item(inventory.capture_snapshot().value["owner"], second)["container_id"] == "body.human-1", "only winning crew owns packed frame")
	deny("machine_deploy", {"machine_id": second, "position": [1300, 0, -2500], "mode": "surface"}, "unowned packed frame")
	move([1000, 0, -1500])
	command("wall_build", {"item_id": plate, "position": [1000, 0, -2500], "quarter_turn": 1})
	move([0, 0, -1500])
	deny("machine_fit", {"machine_id": first, "item_id": expander, "socket_id": ""}, "expander growth into wall")
	var wall_id: String = production.capture_snapshot().value["walls"].keys()[0]
	move([1000, 0, -1500])
	command("wall_remove", {"wall_id": wall_id})
	move([0, 0, 0])
	plate = production.observation(context).value["components"][0]
	context = crew
	move([1300, 0, -2500])
	context = actor
	move([0, 0, -1500])
	deny("machine_fit", {"machine_id": first, "item_id": expander, "socket_id": ""}, "registered other body in expanded strip")
	context = crew
	move([3000, 0, -2500])
	move([2450, 0, 0])
	command("machine_deploy", {"machine_id": second, "position": [2450, 0, 1000], "mode": "surface"})
	context = actor
	move([2450, 0, 0])
	deny("machine_fit", {"machine_id": second, "item_id": expander, "socket_id": ""}, "expander growth into fixture")
	context = crew
	command("machine_pack", {"machine_id": second})
	move([3000, 0, -2500])
	context = actor
	move([0, 0, -1500])
	fit(first, expander)
	for socket in sockets: fit(first, socket)
	move([1000, 0, -1500])
	deny("wall_build", {"item_id": plate, "position": [1000, 0, -2500], "quarter_turn": 1}, "new wall into expanded envelope")
	move([0, 0, 0])
	command("recycle_component", {"item_id": plate})
	move([0, 0, -1500])
	check(MachineryPlacement.half_size(production.capture_snapshot().value["machinery"], first) == MachineryPlacement.EXPANDED_HALF, "six sockets reserved before filling")
	move([0, 0, 0])
	command("load_cargo", {"carrier_id": "resource-canister-1", "material": "iron", "amount_milligrams": 100000})
	move([0, 0, -1500])
	command("machine_insert", {"machine_id": first, "item_id": "resource-canister-1", "socket_id": sockets[5]})
	command("machine_unfit", {"machine_id": first, "item_id": expander, "socket_id": ""})
	check(MachineryPlacement.half_size(production.capture_snapshot().value["machinery"], first) == MachineryPlacement.EXPANDED_HALF, "removing expander never shrinks retained six-socket footprint")
	fit(first, expander)
	move([0, 0, 0])
	var spare_socket: String = craft("socket")
	var solar: String = craft("solar")
	var power: String = craft("power")
	var controller: String = craft("controller")
	var cable: String = craft("cable")
	move([0, 0, -1500])
	for part in [solar, power, controller]: fit(first, part)
	check(MachineryPlacement.half_size(production.capture_snapshot().value["machinery"], first) == MachineryPlacement.EXPANDED_HALF, "solar fitting stays inside reserved height and width")
	context = crew
	move([0, 0, 0])
	var second_power: String = craft("power")
	fit(second, second_power)
	move([2000, 0, -1500])
	var final_intent: Dictionary = {"machine_id": second, "position": [2000, 0, -2500], "mode": "surface", "expected_revision": production.capture_snapshot().value["state_revision"]}
	command("machine_deploy", final_intent)
	var final_request: String = "machine-test-%d" % sequence
	move([1000, 0, -2500])
	command("machine_wire", {"machine_id": first, "other_id": second, "item_id": cable}, false)
	context = actor
	move([1000, 0, -2500])
	command("machine_wire", {"machine_id": first, "other_id": second, "item_id": cable})
	step(90)
	command("machine_enable", {"machine_id": first, "enabled": false})
	var snapshot: ServiceResult = world.capture_world_snapshot_json()
	check(snapshot.is_success, "finite machine placement and nested materials checkpoint")
	restore_checks(snapshot.value, first, second, expander, spare_socket, final_request, final_intent)
	context = crew
	move([4000, 0, -2500])
	context = actor
	# Freeform is an untranslated bottom anchor, with true vertical face contact.
	command("machine_unwire", {"machine_id": first, "item_id": cable})
	command("machine_pack", {"machine_id": first})
	command("machine_deploy", {"machine_id": first, "position": [2000, 1500, -2500], "mode": "freeform"}, false)
	move([2000, 1500, -1500])
	deny("machine_deploy", {"machine_id": first, "position": [2000, 1499, -2500], "mode": "freeform"}, "vertical one millimetre overlap")
	command("machine_deploy", {"machine_id": first, "position": [2000, 1500, -2500], "mode": "freeform"})
	check(world.capture_world_snapshot_json().is_success, "vertical touching freeform machine restarts")
	print("Machine placement authority: %d failures" % failures)
	finish()


func canonical() -> Dictionary:
	var records: Dictionary = {"production": production.capture_snapshot().value, "inventory": inventory.capture_snapshot().value}
	for record in records.values(): record.erase("last_tick")
	return records


func deny(operation: String, payload: Dictionary, label: String) -> void:
	var before: Dictionary = canonical()
	command(operation, payload, false)
	check(canonical() == before, label + " leaves inventory, matter, placements, mounts, receipts and buffers atomic")


func restore_checks(json: String, first: String, second: String, expander: String, spare_socket: String, request: String, intent: Dictionary) -> void:
	var saved: Dictionary = JSON.parse_string(json)
	for variant in ["clear", "legacy-v6", "legacy-v7"]:
		var legacy: bool = variant != "clear"
		var record: Dictionary = saved.duplicate(true)
		if legacy:
			# These matching poses were legal before deployment collision authority.
			if variant == "legacy-v6":
				record["systems"]["production"]["schema_version"] = 6
				record["systems"]["production"].erase("walls")
			record["systems"]["production"]["machinery"]["placements"][second]["position"] = [0, 0, -2500]
			for location in record["systems"]["inventory"]["world_storage"]:
				if location["container_id"] == MachineryWorkshop.root_id(second): location["position_millimetres"] = [0, 0, -2500]
			for physical in record["systems"]["inventory"]["owner"]["ledger"]["items"]:
				if physical["item_id"] in [first, expander] or record["systems"]["production"]["machinery"]["parts"].get(physical["item_id"], {}).get("kind") == "socket" and record["systems"]["production"]["machinery"]["mounts"].has(physical["item_id"]): physical["condition_permille"] = 0
		var restored := WorldRuntime.new()
		restored.resource_carriers_enabled = true
		root.add_child(restored)
		var result: ServiceResult = restored.restore_world_snapshot_json(JSON.stringify(record))
		check(result.is_success, "restore preserves trusted old overlapping wrecks" if legacy else "clear deployed grid and nested cargo restart")
		if result.is_success:
			var owner: ProductionSimulationSystem = restored.get_simulation_system(ProductionSimulationSystem.SYSTEM_ID)
			var restored_inventory: InventorySimulationSystem = restored.get_simulation_system(InventorySimulationSystem.SYSTEM_ID)
			var state: Dictionary = owner.capture_snapshot().value
			check(state["machinery"]["placements"][first]["energy"] == saved["systems"]["production"]["machinery"]["placements"][first]["energy"], "restart retains exact machine buffer")
			for carrier in state["cargo"]:
				for material in state["cargo"][carrier]: check(int(state["cargo"][carrier][material]) == int(saved["systems"]["production"]["cargo"][carrier][material]), "restart retains exact nested cargo")
			check(state["machinery"]["links"] == saved["systems"]["production"]["machinery"]["links"], "restart retains grid links")
			check(MachineryPlacement.half_size(state["machinery"], first) == MachineryPlacement.EXPANDED_HALF, "damaged modules still obstruct with their physical envelope")
			if not legacy:
				check(owner.apply_local(crew, request, "machine_deploy", intent, int(record["tick_number"]) + 1).is_success, "checkpoint retains deployment retry receipt")
			else:
				var before: Dictionary = owner.capture_snapshot().value
				var graph: Dictionary = restored_inventory.capture_snapshot().value
				var denied: ServiceResult = owner.apply_local(actor, "legacy-new-fit", "machine_fit", {"machine_id": first, "item_id": expander, "socket_id": "", "expected_revision": state["state_revision"] - 1}, int(record["tick_number"]) + 1)
				check(not denied.is_success and before == owner.capture_snapshot().value and graph == restored_inventory.capture_snapshot().value, "stale legacy command cannot alter grandfathered state")
				var socket_denial: ServiceResult = owner.apply_local(actor, "legacy-broken-socket", "machine_fit", {"machine_id": first, "item_id": spare_socket, "socket_id": "", "expected_revision": state["state_revision"]}, int(record["tick_number"]) + 1)
				check(not socket_denial.is_success and before == owner.capture_snapshot().value and graph == restored_inventory.capture_snapshot().value, "broken sockets retain physical mounting capacity")
				check(not MachineryWorkshop.operational(state["machinery"], graph["owner"], first, "solar"), "zero condition wreck remains physical while functions stop")
				check(restored.start_simulation().is_success, "grandfathered world resumes ticking")
				var restored_runner: SimulationRunner = restored.get_node("SimulationRunner")
				restored_runner.set_physics_process(false)
				var controller: String = MachineryWorkshop.modules(state["machinery"], graph["owner"], first)["controller"][0]
				var wire: String = state["machinery"]["links"].keys()[0]
				var results: Array[bool] = []
				restored.command_completed.connect(func(_action: SimulationCommand, outcome: ServiceResult) -> void: results.append(outcome.is_success))
				for intent_record in [
					{"operation": "machine_enable", "payload": {"machine_id": first, "enabled": true}},
					{"operation": "machine_unfit", "payload": {"machine_id": first, "item_id": controller, "socket_id": ""}},
					{"operation": "machine_fit", "payload": {"machine_id": first, "item_id": controller, "socket_id": ""}},
					{"operation": "machine_unwire", "payload": {"machine_id": first, "item_id": wire}},
					{"operation": "machine_pack", "payload": {"machine_id": first}}
				]:
					var action := ProductionDevelopmentCommand.new()
					action.command_id = StringName("legacy-operation-%d" % results.size())
					action.authenticated_context = actor
					action.operation = intent_record["operation"]
					action.payload = intent_record["payload"].duplicate(true)
					action.payload["expected_revision"] = owner.capture_snapshot().value["state_revision"]
					check(restored.enqueue_command(action).is_success, "legacy command enters runtime queue")
					restored_runner._physics_process(1.0 / 60.0)
				check(results == [true, true, true, true, true], "grandfathered wreck allows enable, non-growing fit, disconnection and packing")
				var packed: Dictionary = owner.capture_snapshot().value
				var packed_graph: Dictionary = restored_inventory.capture_snapshot().value
				var redeploy: ServiceResult = owner.apply_local(actor, "legacy-redeploy", "machine_deploy", {"machine_id": first, "position": [0, 0, -2500], "mode": "surface", "expected_revision": packed["state_revision"]}, restored_runner.tick_number + 1)
				check(not redeploy.is_success and packed == owner.capture_snapshot().value and packed_graph == restored_inventory.capture_snapshot().value, "packed legacy wreck cannot redeploy into existing obstruction")
				check(restored.capture_world_snapshot_json().is_success, "packed legacy wreck and nested contents form a valid next checkpoint")
		restored.free()
