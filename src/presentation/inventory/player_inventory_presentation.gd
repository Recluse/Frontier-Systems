extends RefCounted
class_name PlayerInventoryPresentation

## Disposable hints from scoped host observations; never an authorization owner.
static func item(record: Dictionary, item_id: String) -> Dictionary:
	for entry in record.get("items", []):
		if entry["item_id"] == item_id:
			return entry
	return {}


static func world_item(nearby: Dictionary, item_id: String, container_id: String) -> Dictionary:
	for container in nearby.get("containers", []):
		if container["container_id"] == container_id:
			for entry in container["items"]:
				if entry["item_id"] == item_id:
					return entry
	return {}


static func prerequisite(operation: String, record: Dictionary, nearby: Dictionary, item_id: String, destination: String, slot: String, world_root: String) -> String:
	if record.is_empty():
		return "Wait for a fresh owned inventory observation."
	if operation == "select_hand":
		return "" if record.get("hand_slot_ids", []).has(slot) else "Choose a configured hand slot."
	if operation == "switch_hand":
		return "" if record.get("hand_slot_ids", []).size() > 0 else "No configured hands in this observation."
	if operation in ["equip", "unequip"] and not record.get("slot_ids", []).has(slot):
		return "Choose an observed equipment slot."
	if operation in ["pickup", "move", "unequip"] and not record.get("container_ids", []).has(destination):
		return "Choose observed owned destination storage."
	if operation in ["pickup", "drop"]:
		var found: bool = false
		for container in nearby.get("containers", []):
			if container["container_id"] == world_root:
				found = true
		if not found:
			return "Choose accessible world storage from the latest host reach view."
	if operation == "pickup":
		return "" if not world_item(nearby, item_id, world_root).is_empty() else "Select a direct item in the observed tray."
	if operation == "unequip":
		for binding in record.get("equipped", []):
			if binding["slot_id"] == slot:
				return ""
		return "The selected slot has no observed equipped item."
	if operation == "equip":
		for binding in record.get("equipped", []):
			if binding["slot_id"] == slot:
				return "Unequip the existing item before using this slot."
	var selected: Dictionary = item(record, item_id)
	if selected.is_empty():
		return "Select a currently observed owned item."
	if operation == "move":
		if selected["container_id"] == destination:
			return "The item is already in that destination."
		for binding in record.get("equipped", []):
			if binding["item_id"] == item_id:
				return "Unequip the item before moving it into storage."
	return ""


static func storage_hint(record: Dictionary, destination: String) -> String:
	for container in record.get("container_records", []):
		if container["container_id"] != destination:
			continue
		var load: Dictionary = container["load"]
		var capacity: Dictionary = container["capacity"]
		return "Observed destination %s: %.2f / %.2f kg; %.2f / %.2f L. Host rechecks capacity, tags, nesting and equipment limits." % [destination, float(load["mass_milligrams"]) / 1000000.0, float(capacity["max_mass_milligrams"]) / 1000000.0, float(load["volume_millilitres"]) / 1000.0, float(capacity["max_volume_millilitres"]) / 1000.0]
	return "Destination capacity is unavailable in this observation; the host decides."


static func pending_text(payload: Dictionary) -> String:
	return "Waiting for host · %s · item %s · source %s · destination %s · slot %s · revision %d. Outcome unconfirmed until host acknowledgement." % [payload.get("operation", ""), payload.get("item_id", ""), payload.get("source_container_id", payload.get("world_container_id", "")), payload.get("destination_container_id", ""), payload.get("slot_id", ""), payload.get("expected_revision", -1)]
