extends SceneTree

var _failures: int = 0


func _initialize() -> void:
	var profiles: Dictionary = {}
	for name in ["human", "cyborg", "station-ai"]:
		var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/inventory/%s.v1.json" % name))
		var result: ServiceResult = InventoryEquipmentProfile.from_record(record)
		_check(result.is_success, "default profile must parse: " + name)
		if result.is_success:
			profiles[name] = result.value
	if profiles.size() != 3:
		quit(1)
		return
	var human: InventoryEquipmentProfile = profiles["human"]
	_check(human.next_hand("hand.left").value == "hand.right", "left hand must switch to right")
	_check(human.next_hand("hand.right").value == "hand.left", "right hand must switch to left")
	_check(not human.next_hand("invented").is_success, "unknown active hand must reject")
	_check(human.assess_slot("hand.left", PackedStringArray(["item.handheld"]), 1000000, 1000).is_success, "handheld item must fit hand")
	_check(human.assess_slot("back", PackedStringArray(["wearable.human.backpack"]), 1000000, 1000).is_success, "backpack must fit back")
	_check(not human.assess_slot("clothing.uniform", PackedStringArray(["item.handheld"]), 1, 1).is_success, "equipment tags must match")
	_check(not human.assess_slot("hand.left", PackedStringArray(["item.handheld"]), 15000001, 1).is_success, "slot mass limit must reject")
	_check(not human.assess_slot("hand.left", PackedStringArray(["item.handheld"]), 1, 20001).is_success, "slot volume limit must reject")
	_check(not human.assess_slot("hand.left", PackedStringArray(["item.handheld"]), -1, 1).is_success, "negative mass must reject")
	_check(not human.assess_slot("invented", PackedStringArray(["item.handheld"]), 1, 1).is_success, "unknown slot must reject")
	var cyborg: InventoryEquipmentProfile = profiles["cyborg"]
	_check(cyborg.assess_slot("module.utility", PackedStringArray(["module.cyborg.utility"]), 1, 1).is_success, "cyborg module must fit module bay")
	_check(not cyborg.assess_slot("clothing.uniform", PackedStringArray(["wearable.human.uniform"]), 1, 1).is_success, "human clothing slot must not appear on cyborg")
	var station_ai: InventoryEquipmentProfile = profiles["station-ai"]
	_check(not station_ai.next_hand("hand.left").is_success, "station AI must not invent hands")
	var detached: Dictionary = human.to_record()
	detached["slots"].clear()
	_check(human.to_record()["slots"].size() == 10, "profile record must be detached")
	var invalid: Dictionary = human.to_record()
	invalid["slots"].append(invalid["slots"][0].duplicate(true))
	_check(not InventoryEquipmentProfile.from_record(invalid).is_success, "duplicate slots must reject")
	invalid = human.to_record()
	invalid["hand_slot_ids"] = ["missing"]
	_check(not InventoryEquipmentProfile.from_record(invalid).is_success, "hands must reference real slots")
	invalid = human.to_record()
	invalid["max_carried_mass_milligrams"] = 1.5
	_check(not InventoryEquipmentProfile.from_record(invalid).is_success, "fractional carry mass must reject")
	invalid = human.to_record()
	invalid["slots"][0]["accepted_tags"] = []
	_check(not InventoryEquipmentProfile.from_record(invalid).is_success, "empty compatibility tags must reject")
	if _failures == 0:
		print("Body inventory equipment profile scenarios passed.")
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
