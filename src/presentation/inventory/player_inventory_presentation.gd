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


## Exact observed targets only; no projected after-load or fit decision.
static func transfer_preview(record: Dictionary, item_id: String, destination: String, slot: String, nearby: Dictionary = {}, world_root: String = "") -> String:
	var selected: Dictionary = item(record, item_id) if world_root.is_empty() else world_item(nearby, item_id, world_root)
	var lines := PackedStringArray(["Observed owned move/equipment selections" if world_root.is_empty() else "Observed tray collection selections"])
	if selected.is_empty():
		lines.append("Item/source: unavailable; select a currently observed item.")
	else:
		lines.append("Item: %s · source: %s" % [selected["item_id"], selected["container_id"]])
		var mass_text: String = "Loaded mass: unavailable in this observation."
		if world_root.is_empty():
			for detail in record.get("item_details", []):
				if detail["item"]["item_id"] == selected["item_id"]:
					mass_text = "Observed loaded mass: %.2f kg (nested contents and payload included)." % [float(detail["mass_milligrams"]) / 1000000.0]
		lines.append(mass_text)
	lines.append("Destination: %s" % [destination if record.get("container_ids", []).has(destination) else "unavailable"])
	lines.append("Slot: %s" % [slot if record.get("slot_ids", []).has(slot) else "unavailable"])
	for binding in record.get("equipped", []):
		if binding["slot_id"] == slot:
			lines.append("Observed slot item: %s" % binding["item_id"])
	lines.append(storage_hint(record, destination) if record.get("container_ids", []).has(destination) else "Destination capacity: unavailable.")
	lines.append("Host decides acceptance, ownership and current reach; no outcome is predicted.")
	return "\n".join(lines)


static func drop_preview(record: Dictionary, item_id: String, nearby: Dictionary, world_root: String) -> String:
	var selected: Dictionary = item(record, item_id)
	var destination: String = "unavailable"
	for container in nearby.get("containers", []):
		if container["container_id"] == world_root: destination = world_root
	var source: String = str(selected["container_id"]) if not selected.is_empty() else "unavailable"
	return "Observed tray drop selections\nItem: %s · source: %s · tray destination: %s\nTray capacity: unavailable in this observation. Host rechecks acceptance, ownership and reach." % [item_id if not selected.is_empty() else "unavailable", source, destination]