extends SceneTree

var _failures: int = 0


func _initialize() -> void:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/locomotion/cooperative-object-move.v1.json"))
	var before: Dictionary = fixture.duplicate(true)
	_check(PhysicalInteractionPolicy.assess(fixture).value["allowed"], "cooperative capacity must enable world movement")
	_check(fixture == before, "assessment must not mutate hands or world ownership")
	var single: Dictionary = fixture.duplicate(true)
	single["participants"].pop_back()
	_check(not PhysicalInteractionPolicy.assess(single).value["allowed"], "one insufficient participant must not lift the cooperative load")
	single["required_force_millinewtons"] = 100000
	single["movable"] = false
	_check(not PhysicalInteractionPolicy.assess(single).value["allowed"], "anchored objects require detachment before movement")
	single["action"] = "push_off"
	_check(PhysicalInteractionPolicy.assess(single).value["allowed"], "one free hand can push off an anchored surface")
	single["action"] = "pull_along"
	_check(PhysicalInteractionPolicy.assess(single).value["allowed"], "grippable ladder can support traversal")
	single["action"] = "grab"
	_check(PhysicalInteractionPolicy.assess(single).value["allowed"], "free hand can acquire a valid grip")
	single["grippable"] = false
	_check(not PhysicalInteractionPolicy.assess(single).value["allowed"], "smooth pushable surface must not imply a usable grip")
	single["action"] = "push_off"
	_check(PhysicalInteractionPolicy.assess(single).value["allowed"], "ungrippable surface can still support pushing")
	single["pushable"] = false
	_check(not PhysicalInteractionPolicy.assess(single).value["allowed"], "surface must support a push-off reaction")
	single["pushable"] = true
	single["participants"][0]["free_hand_ids"] = []
	_check(not PhysicalInteractionPolicy.assess(single).value["allowed"], "occupied or reserved hands must block gripping")
	single = fixture.duplicate(true)
	single["participants"][1]["contact"] = false
	_check(not PhysicalInteractionPolicy.assess(single).value["allowed"], "remote helpers cannot contribute force")
	single = fixture.duplicate(true)
	single["contact_force_limit_millinewtons"] = 299999
	_check(not PhysicalInteractionPolicy.assess(single).value["allowed"], "weak grips must limit cooperative force")
	single = fixture.duplicate(true)
	single["participants"][1]["body_id"] = single["participants"][0]["body_id"]
	_check(not PhysicalInteractionPolicy.assess(single).is_success, "duplicate participants must not multiply force")
	single = fixture.duplicate(true)
	single["participants"][0]["free_hand_ids"].append("hand.left")
	_check(not PhysicalInteractionPolicy.assess(single).is_success, "duplicate hands must reject")
	single = fixture.duplicate(true)
	single["required_force_millinewtons"] = 0.5
	_check(not PhysicalInteractionPolicy.assess(single).is_success, "fractional canonical force must reject")
	_check(PhysicalInteractionPolicy.assess(JSON.parse_string(JSON.stringify(fixture))).value["allowed"], "JSON observations must round trip")
	if _failures == 0:
		print("Hand traversal and cooperative physical interaction policy scenarios passed.")
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
