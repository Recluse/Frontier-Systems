extends SceneTree

## Headless contract scenarios for imported modules, mounting, and wiring.

var _failures: int = 0


func _initialize() -> void:
	_run_scenarios()
	if _failures == 0:
		print("Machine module contract scenarios passed.")
	quit(0 if _failures == 0 else 1)


func _run_scenarios() -> void:
	var module_record: Dictionary = _read_fixture("res://data/control/modules/radio_receiver.v1.json")
	var slot_record: Dictionary = _read_fixture("res://data/control/slots/industrial_control.v1.json")
	var parsed_module: ServiceResult = MachineModuleDefinition.from_record(module_record)
	var parsed_slot: ServiceResult = MachineModuleSlotDefinition.from_record(slot_record)
	_check(parsed_module.is_success and parsed_slot.is_success, "JSON fixtures must decode into typed records")
	if not parsed_module.is_success or not parsed_slot.is_success:
		return
	var module: MachineModuleDefinition = parsed_module.value
	var slot: MachineModuleSlotDefinition = parsed_slot.value
	var host := PackedStringArray(["power.consumer", "control.wired"])
	_check(slot.accepts(module).is_success, "compatible industrial receiver must fit its slot")
	_check(not slot.evaluate_operability(module, PackedStringArray()).value["operable"], "missing host capabilities leave a physically fitted module dormant")
	_check(slot.evaluate_operability(module, host).value["operable"], "functional prerequisites enable a fitted module")
	module.interface_id = "control.suit.v1"
	_check(slot.accepts(module).error_code == &"module_interface_mismatch", "different interface versions must be rejected")
	module.interface_id = "control.industrial.v1"
	module.module_family = "trigger.explosive"
	_check(slot.accepts(module).error_code == &"module_family_mismatch", "a mechanically unsupported module family must be rejected")
	module.module_family = "radio.receiver"
	module.size_units = 3
	_check(slot.accepts(module).error_code == &"module_capacity_exceeded", "oversized modules must be rejected")
	module.size_units = 1
	_check_device_specific_slots(module)
	_check_partial_functions()
	_check_board_upgrades(module, host)

	var registry := MachineModuleRegistry.new(PackedStringArray(["radio.receiver.v1"]))
	_check(registry.register_definition(module_record).is_success, "known handler must permit catalog registration")
	_check(registry.register_definition(module_record).error_code == &"module_revision_exists", "definition revisions must be immutable")
	var unknown_handler: Dictionary = module_record.duplicate(true)
	unknown_handler["handler_id"] = "untrusted.custom_code"
	_check(registry.register_definition(unknown_handler).error_code == &"unknown_module_handler", "imports cannot create executable handlers")
	var first_read: ServiceResult = registry.get_definition(module.definition_id, 1)
	_check(first_read.is_success, "registered definition must be retrievable")
	if not first_read.is_success:
		return
	var detached: MachineModuleDefinition = first_read.value
	detached.ports[0]["port_id"] = "changed"
	var second_read: ServiceResult = registry.get_definition(module.definition_id, 1)
	_check(second_read.is_success, "registered definition must survive mutation of a detached result")
	if not second_read.is_success:
		return
	var original: MachineModuleDefinition = second_read.value
	_check(original.ports[0]["port_id"] == "receive", "callers must not mutate registered definitions")

	var duplicate_port: Dictionary = module_record.duplicate(true)
	duplicate_port["ports"].append(duplicate_port["ports"][0].duplicate(true))
	_check(MachineModuleDefinition.from_record(duplicate_port).error_code == &"duplicate_module_port", "duplicate local port IDs must be rejected")
	var executable_field: Dictionary = module_record.duplicate(true)
	executable_field["script"] = "untrusted.gd"
	_check(not MachineModuleDefinition.from_record(executable_field).is_success, "unknown executable fields must be rejected")
	var fractional_revision: Dictionary = module_record.duplicate(true)
	fractional_revision["revision"] = 1.5
	_check(not MachineModuleDefinition.from_record(fractional_revision).is_success, "fractional revisions must be rejected")
	var roundtrip: Variant = JSON.parse_string(JSON.stringify(module.to_record()))
	_check(typeof(roundtrip) == TYPE_DICTIONARY, "module JSON round-trip must produce an object")
	if typeof(roundtrip) == TYPE_DICTIONARY:
		_check(MachineModuleDefinition.from_record(roundtrip).is_success, "JSON numeric conversion must preserve an integer revision")

	var output: Dictionary = module.ports[1]
	var input: Dictionary = {"port_id": "unlock", "direction": "input", "signal_type": "pulse", "transport": "wired"}
	_check(ControlContractValidation.can_connect(output, input).is_success, "a wired pulse output must connect to a matching input")
	_check(ControlContractValidation.assess_wired_attachment(input, output).value["route_direction"] == "second_to_first", "cable attachment order must not determine whether its signal route works")
	_check(ControlContractValidation.can_connect(output, output).error_code == &"control_port_direction_mismatch", "output-to-output wiring has no valid directed signal route")
	var odd_wire: ServiceResult = ControlContractValidation.assess_wired_attachment(output, output)
	_check(odd_wire.is_success and not odd_wire.value["signal_route_available"], "output-to-output cables may be attached without inventing a working signal route")
	input["signal_type"] = "number"
	_check(ControlContractValidation.can_connect(output, input).error_code == &"control_signal_type_mismatch", "different signal types need an explicit converter")
	var inert_wire: ServiceResult = ControlContractValidation.assess_wired_attachment(output, input)
	_check(inert_wire.is_success and not inert_wire.value["signal_route_available"], "physically matching but semantically incompatible wiring must remain constructible")
	input["signal_type"] = "pulse"
	input["transport"] = "radio"
	_check(ControlContractValidation.can_connect(output, input).error_code == &"control_transport_mismatch", "wired ports must not be directly joined to radio ports")
	_check(not ControlContractValidation.assess_wired_attachment(output, input).is_success, "radio endpoints are not physical cable sockets")


func _check_device_specific_slots(receiver: MachineModuleDefinition) -> void:
	var pda_module_result: ServiceResult = MachineModuleDefinition.from_record(_read_fixture("res://data/control/modules/pda_transceiver.v1.json"))
	var pda_slot_result: ServiceResult = MachineModuleSlotDefinition.from_record(_read_fixture("res://data/control/slots/pda_radio.v1.json"))
	var door_slot_result: ServiceResult = MachineModuleSlotDefinition.from_record(_read_fixture("res://data/control/slots/door_receiver.v1.json"))
	_check(pda_module_result.is_success and pda_slot_result.is_success and door_slot_result.is_success, "PDA and door fixtures must parse")
	if not pda_module_result.is_success or not pda_slot_result.is_success or not door_slot_result.is_success:
		return
	var transceiver: MachineModuleDefinition = pda_module_result.value
	var pda_slot: MachineModuleSlotDefinition = pda_slot_result.value
	var door_slot: MachineModuleSlotDefinition = door_slot_result.value
	_check(pda_slot.accepts(transceiver).is_success, "a PDA supports a compatible radio transceiver")
	_check(door_slot.accepts(receiver).is_success, "a simple door supports its receive-only module")
	_check(not door_slot.accepts(transceiver).is_success, "a stock door receiver socket must reject a PDA transceiver")
	transceiver.interface_id = door_slot.interface_id
	_check(door_slot.accepts(transceiver).error_code == &"module_family_mismatch", "a dedicated receiver socket still rejects unsupported card families")


func _check_board_upgrades(receiver: MachineModuleDefinition, host: PackedStringArray) -> void:
	var stock_result: ServiceResult = MachineControlBoardDefinition.from_record(_read_fixture("res://data/control/boards/door_stock.v1.json"))
	var expanded_result: ServiceResult = MachineControlBoardDefinition.from_record(_read_fixture("res://data/control/boards/door_expanded.v2.json"))
	var igniter_result: ServiceResult = MachineModuleDefinition.from_record(_read_fixture("res://data/control/modules/igniter.v1.json"))
	_check(stock_result.is_success and expanded_result.is_success and igniter_result.is_success, "board and igniter fixtures must parse")
	if not stock_result.is_success or not expanded_result.is_success or not igniter_result.is_success:
		return
	var stock: MachineControlBoardDefinition = stock_result.value
	var expanded: MachineControlBoardDefinition = expanded_result.value
	var igniter: MachineModuleDefinition = igniter_result.value
	var receiver_slot := stock.slots["door.receiver.1"] as MachineModuleSlotDefinition
	var utility_slot := expanded.slots["door.utility.1"] as MachineModuleSlotDefinition
	_check(not receiver_slot.accepts(igniter).is_success, "an igniter must not fit a stock receiver socket")
	_check(utility_slot.accepts(igniter).is_success, "an upgraded door utility bay must accept a physically compatible igniter")
	_check(not utility_slot.evaluate_operability(igniter, PackedStringArray()).value["operable"], "a fitted igniter can remain nonfunctional without its host services")
	_check(utility_slot.evaluate_operability(igniter, host).value["operable"], "host services enable a compatible fitted igniter")
	_check(ControlContractValidation.can_connect(receiver.ports[1], igniter.ports[0]).is_success, "a receiver's wired pulse can connect to an igniter trigger across module mounting interfaces")
	var original_board: Dictionary = stock.to_record()
	var original_receiver: Dictionary = receiver.to_record()
	var upgrade: ServiceResult = stock.plan_replacement(expanded, {"door.receiver.1": receiver}, PackedStringArray())
	_check(upgrade.is_success, "more-slot board upgrades must preserve fitted modules even when dormant")
	if upgrade.is_success:
		_check(upgrade.value["slot_assignments"]["door.receiver.1"] == "door.receiver.1", "retained slot IDs must keep the receiver assignment")
		_check(not upgrade.value["module_operability"][0]["operable"], "upgrade plans must diagnose dormant modules without rejecting them")
	_check(stock.to_record() == original_board and receiver.to_record() == original_receiver, "planning must not mutate boards or installed modules")
	_check(stock.plan_replacement(expanded, {"door.receiver.1": "untrusted_module"}, host).error_code == &"invalid_installed_module", "malformed installed-module input must fail without executing or crashing")
	var fitted: Dictionary = {"door.receiver.1": receiver, "door.utility.1": igniter}
	_check(expanded.plan_replacement(stock, fitted, host).error_code == &"module_relocation_required", "a smaller board must never silently delete an attached igniter")
	var relocation: ServiceResult = expanded.plan_replacement(expanded, fitted, host, {"door.utility.1": "door.utility.2"})
	_check(relocation.is_success, "an explicit compatible relocation must be accepted")
	var two_igniters: Dictionary = {"door.utility.1": igniter, "door.utility.2": igniter}
	_check(expanded.plan_replacement(expanded, two_igniters, host, {"door.utility.1": "door.utility.2"}).error_code == &"board_slot_collision", "two modules cannot be transferred into one slot")
	var incompatible_result: ServiceResult = MachineControlBoardDefinition.from_record(expanded.to_record())
	var incompatible: MachineControlBoardDefinition = incompatible_result.value
	incompatible.mount_interface_id = "pda.controlboard.v1"
	_check(stock.plan_replacement(incompatible, {"door.receiver.1": receiver}, host).error_code == &"board_mount_mismatch", "board mounting constraints still apply")
	var duplicate_slot: Dictionary = expanded.to_record()
	duplicate_slot["slots"].append(duplicate_slot["slots"][0].duplicate(true))
	_check(MachineControlBoardDefinition.from_record(duplicate_slot).error_code == &"duplicate_control_board_slot", "board layouts must have unique slot IDs")
	igniter.module_family = "utility.unusual"
	_check(utility_slot.accepts(igniter).is_success, "general utility bays must not reject physically compatible modules for being unusual")


func _check_partial_functions() -> void:
	var radio_result: ServiceResult = MachineFunctionRequirement.from_record(_read_fixture("res://data/control/functions/door_radio_receive.v1.json"))
	var manual_result: ServiceResult = MachineFunctionRequirement.from_record(_read_fixture("res://data/control/functions/door_manual_move.v1.json"))
	_check(radio_result.is_success and manual_result.is_success, "function requirement fixtures must parse")
	if not radio_result.is_success or not manual_result.is_success:
		return
	var radio: MachineFunctionRequirement = radio_result.value
	var manual: MachineFunctionRequirement = manual_result.value
	var available := PackedStringArray(["door.manual_path"])
	_check(not radio.evaluate(available).value["available"], "a missing receiver must disable radio reception")
	_check(manual.evaluate(available).value["available"], "missing radio parts must preserve an intact manual path")
	available.append("radio.receive")
	_check(not radio.evaluate(available).value["available"], "a fitted receiver must still require its control power")
	available.append("control.power")
	_check(radio.evaluate(available).value["available"], "a fitted powered receiver enables reception")


func _read_fixture(path: String) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK or typeof(parser.data) != TYPE_DICTIONARY:
		_check(false, "fixture must contain valid JSON: %s" % path)
		return {}
	return parser.data


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
