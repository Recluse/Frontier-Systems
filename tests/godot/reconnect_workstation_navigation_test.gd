extends "res://tests/godot/client_inventory_shell_test.gd"

class NavigationClient extends InventoryClient:
	var navigation_calls: int = 0
	func _navigate_to_workstation() -> void:
		navigation_calls += 1
		super._navigate_to_workstation()

func run() -> void:
	world = WorldRuntime.new()
	root.add_child(world)
	check(world.start_simulation().is_success, "canonical observation fixture starts")
	world.get_node("SimulationRunner").set_physics_process(false)
	context = AuthenticatedCommandContext.for_local_development(&"local-inventory-target", world.world_id, world.region_id)
	var navigation := NavigationClient.new()
	client = navigation
	root.add_child(client)
	client.set_process(false)
	remote = client._remote
	remote.set_process(false)
	remote.server_slot = 0
	for cycle in range(4):
		observe_shell()
		await settle()
		client._tabs.current_tab = 1
		var calls: int = navigation.navigation_calls
		client._habitat.production.workstation_selected.emit()
		check(navigation.navigation_calls == calls + 1 and client._tabs.current_tab == 0, "one navigation effect after reconnect %d" % cycle)
		check(client._habitat.production.workstation_selected.get_connections().size() == 1, "persistent emitter has one navigation owner")
		var old_panel: LocalProductionPanel = client._production_panel
		remote.connection_closed.emit("Fixture disconnect")
		check(client._production_panel == null and old_panel.is_queued_for_deletion(), "disconnect releases old production panel")
		client._tabs.current_tab = 1
		client._habitat.production.workstation_selected.emit()
		check(client._tabs.current_tab == 1, "signal during deferred panel deletion cannot navigate")
		await settle()
		client._habitat.production.workstation_selected.emit()
		check(client._tabs.current_tab == 1, "signal while disconnected cannot dereference absent panel")
	check(remote.sent.is_empty(), "presentation navigation emits no canonical commands")
	# Deterministic CI race: completion and the next observation share one frame.
	observe_shell()
	var checkpoint: Dictionary = {}
	remote.command_completed.connect(func(command: SimulationCommand, result: ServiceResult) -> void:
		if command is CheckpointRequest:
			checkpoint["success"] = result.is_success
			checkpoint["visible"] = client._status.text == "Shared world checkpoint confirmed on disk."
	)
	remote.command_completed.emit(CheckpointRequest.new(), ServiceResult.success())
	observe_shell()
	check(checkpoint.get("success", false) and checkpoint.get("visible", false), "receipt latch captures successful checkpoint UI before same-frame observation")
	check(client._status.text != "Shared world checkpoint confirmed on disk.", "polling transient label after same-frame observation misses receipt")
	client.free()
	world.free()
	PlayerInputSettings.instance().release_all()
	await process_frame
	print("Repeated reconnect workstation navigation: %d failures; socket-free shell fixture" % failures)
	quit(1 if failures else 0)
