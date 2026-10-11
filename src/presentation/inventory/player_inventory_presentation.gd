extends RefCounted
class_name PlayerInventoryPresentation

static func owned_container(record: Dictionary, id: String) -> Dictionary:
	for container in record.get("container_records", []):
		if container.get("container_id") == id and record.get("container_ids", []).has(id): return container
	return {}


static func closure_prerequisite(record: Dictionary, id: String) -> String:
	if not ControlContractValidation.is_integer(record.get("schema_version"), 3, 4) or not ControlContractValidation.is_integer(record.get("inventory_revision"), 0, 9007199254740990):
		return "Closure observation/revision unavailable; wait for a fresh detailed owned observation."
	var container: Dictionary = owned_container(record, id)
	if container.is_empty(): return "Select a currently observed owned container; retained target %s is unavailable." % id
	if str(container.get("owner_item_id", "")).is_empty(): return "Body roots do not support closure. Select item-hosted owned storage."
	if record.get("schema_version") == 4 and typeof(container.get("is_open")) != TYPE_BOOL:
		return "Closure field unavailable; wait for a complete host observation."
	return ""


static func closure_status(record: Dictionary, id: String) -> String:
	var container: Dictionary = owned_container(record, id)
	var state: String = "unavailable"
	if record.get("schema_version") == 4 and not container.is_empty() and typeof(container.get("is_open")) == TYPE_BOOL:
		state = "open" if container["is_open"] else "closed"
	return "Selected owned container: %s\nHost-observed closure: %s\nOwned descendant knowledge remains visible. It does not establish physical access or a lock. The host checks open ancestors, available hands and revision." % [id if not id.is_empty() else "unavailable", state]


static func closure_targets(payload: Dictionary) -> String:
	return "%s · container %s · revision %s · request %s" % [payload.get("operation", ""), payload.get("container_id", ""), payload.get("expected_revision", ""), payload.get("request_id", "")]

## Disposable hints from scoped host observations; never an authorization owner.
static func active_equipment(record: Dictionary, selected_item: String, selected_slot: String) -> String:
	var lines := PackedStringArray(["Host-observed active equipment"])
	var hand: String = str(record.get("active_hand_slot_id", ""))
	if hand.is_empty() or not record.get("hand_slot_ids", []).has(hand) or not record.has("equipped"):
		lines.append("Active hand/item: unavailable; wait for a fresh host observation.")
	else:
		lines.append("Active hand: " + hand)
		var held: String = ""
		for binding in record.get("equipped", []):
			if binding["slot_id"] == hand: held = binding["item_id"]
		var entry: Dictionary = item(record, held)
		if held.is_empty():
			lines.append("Active hand item: empty in this observation.")
		elif entry.is_empty():
			lines.append("Active hand item: unavailable in this observation.")
		else:
			lines.append("Active hand item: %s · %s" % [PlayerInventoryPanel.NAMES.get(entry["definition_id"], "Equipment"), held])
	lines.append("Selected inventory item: " + (selected_item if not item(record, selected_item).is_empty() else "unavailable"))
	lines.append("Selected equipment slot: " + (selected_slot if record.get("slot_ids", []).has(selected_slot) else "unavailable"))
	lines.append("Selections do not change active equipment. Engineering uses the active hand; the host checks tool and reach.")
	return "\n".join(lines)


## Operation-specific paths; the selected move destination is not an equip target.
static func equipment_access(record: Dictionary, selected_item: String, slot: String, destination: String) -> String:
	var selected: Dictionary = item(record, selected_item)
	var occupant: String = ""
	for binding in record.get("equipped", []):
		if binding["slot_id"] == slot: occupant = binding["item_id"]
	var equipped_item: Dictionary = item(record, occupant)
	var lines := PackedStringArray([
		"Equip item: %s · source: %s · target slot: %s" % [selected_item if not selected.is_empty() else "unavailable", selected.get("container_id", "unavailable"), slot if record.get("slot_ids", []).has(slot) else "unavailable"],
		access_hint(record, str(selected.get("container_id", "")), "Equip source", true),
		access_hint(record, str(record.get("body_container_id", "")), "Equip body-root target", true),
		"Equip uses the body root and selected slot; the storage destination selection is not used.",
		"Unequip slot item: %s · source: %s · destination: %s" % [occupant if not equipped_item.is_empty() else "unavailable", equipped_item.get("container_id", "unavailable"), destination if record.get("container_ids", []).has(destination) else "unavailable"],
		access_hint(record, str(equipped_item.get("container_id", "")), "Unequip source", true),
		access_hint(record, destination, "Unequip destination", true),
		"Paths describe closure only; the host checks access, fit, hands, reach and revision. Known contents remain browsable. Open closed ancestors explicitly and refresh; unknown paths need a fresh complete v4 observation. Shells use their containing path, not their contents.",
		"Select hand uses the selected hand slot; switch cycles hands. Neither moves items or opens storage."
	])
	return "\n".join(lines)


## Detached submission-time observation, kept separate from the command payload.
static func equipment_submission(record: Dictionary, payload: Dictionary) -> String:
	var slot: String = str(payload.get("slot_id", ""))
	var occupant: String = "empty"
	if not record.has("equipped") or not record.get("slot_ids", []).has(slot):
		occupant = "unavailable"
	else:
		for binding in record["equipped"]:
			if binding["slot_id"] == slot: occupant = binding["item_id"]
	return "Submitted equipment observation · slot %s · slot item %s · active hand %s. These are observed identities, not a predicted outcome." % [slot if not slot.is_empty() else "not used", occupant if not slot.is_empty() else "not used", record.get("active_hand_slot_id", "unavailable")]

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


## Quotes a bounded owned observation path; never calls canonical access checks.
## Unknown fields never inherit the legacy runtime's default-open semantics.
static func observed_access(record: Dictionary, container_id: String) -> Dictionary:
	if not ControlContractValidation.is_integer(record.get("schema_version"), 4, 4) or not ControlContractValidation.is_integer(record.get("inventory_revision"), 0, 9007199254740990):
		return {"state": "unknown"}
	var cursor: String = container_id
	var seen: Array[String] = []
	for _depth in range(InventoryLedger.MAX_DEPTH):
		if seen.has(cursor): return {"state": "unknown"}
		seen.append(cursor)
		var container: Dictionary = owned_container(record, cursor)
		if container.is_empty() or typeof(container.get("is_open")) != TYPE_BOOL:
			return {"state": "unknown"}
		if not container["is_open"]: return {"state": "closed", "container_id": cursor}
		if typeof(container.get("owner_item_id")) != TYPE_STRING: return {"state": "unknown"}
		var owner: String = container["owner_item_id"]
		if owner.is_empty():
			return {"state": "open"} if cursor == record.get("body_container_id") else {"state": "unknown"}
		var shell: Dictionary = item(record, owner)
		if shell.is_empty(): return {"state": "unknown"}
		cursor = str(shell.get("container_id", ""))
	return {"state": "unknown"}


static func access_hint(record: Dictionary, container_id: String, role: String, compact: bool = false) -> String:
	var access: Dictionary = observed_access(record, container_id)
	if compact:
		if access["state"] == "closed": return "%s physical access: observed closed container %s blocks this path." % [role, access["container_id"]]
		if access["state"] == "open": return "%s closure path: observed open." % role
		return "%s physical access: unknown." % role
	if access["state"] == "closed":
		return "%s physical access: observed closed container %s blocks this path. Known contents remain browsable; explicitly open it and refresh before transferring." % [role, access["container_id"]]
	if access["state"] == "open":
		return "%s closure path: observed open; physical access and transfer acceptance remain host decisions." % role
	return "%s physical access: unknown; wait for a fresh complete v4 owned closure observation. Known contents do not establish access." % role


static func transfer_blocker(operation: String, record: Dictionary, access_record: Dictionary, item_id: String, destination: String, slot: String) -> String:
	var source: String = ""
	if operation in ["move", "equip", "drop"]: source = str(item(record, item_id).get("container_id", ""))
	if operation == "unequip":
		for binding in record.get("equipped", []):
			if binding["slot_id"] == slot: source = str(item(record, binding["item_id"]).get("container_id", ""))
	for path in [{"id": source, "role": "Source"}, {"id": destination if operation in ["move", "pickup", "unequip"] else "", "role": "Destination"}]:
		if not path["id"].is_empty() and observed_access(access_record, path["id"])["state"] == "closed":
			return access_hint(access_record, path["id"], path["role"])
	return ""


static func prerequisite(operation: String, record: Dictionary, nearby: Dictionary, item_id: String, destination: String, slot: String, world_root: String, access_record: Variant = null) -> String:
	if record.is_empty():
		return "Wait for a fresh owned inventory observation."
	var blocker: String = transfer_blocker(operation, record, record if access_record == null else access_record, item_id, destination, slot)
	if not blocker.is_empty(): return blocker
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
static func transfer_preview(record: Dictionary, item_id: String, destination: String, _slot: String, nearby: Dictionary = {}, world_root: String = "", access_record: Variant = null) -> String:
	var selected: Dictionary = item(record, item_id) if world_root.is_empty() else world_item(nearby, item_id, world_root)
	var lines := PackedStringArray(["Move selected item · observed targets" if world_root.is_empty() else "Observed tray collection selections"])
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
	if not world_root.is_empty(): lines.append(storage_hint(record, destination) if record.get("container_ids", []).has(destination) else "Destination capacity: unavailable.")
	var closure_record: Dictionary = record if access_record == null else access_record
	if world_root.is_empty(): lines.append(access_hint(closure_record, str(selected.get("container_id", "")), "Source"))
	lines.append(access_hint(closure_record, destination, "Destination"))
	lines.append("Host decides acceptance, ownership and current reach; no outcome is predicted.")
	return "\n".join(lines)


static func drop_preview(record: Dictionary, item_id: String, nearby: Dictionary, world_root: String, access_record: Variant = null) -> String:
	var selected: Dictionary = item(record, item_id)
	var destination: String = "unavailable"
	for container in nearby.get("containers", []):
		if container["container_id"] == world_root: destination = world_root
	var source: String = str(selected["container_id"]) if not selected.is_empty() else "unavailable"
	return "Observed tray drop selections\nItem: %s · source: %s · tray destination: %s\nTray capacity: unavailable in this observation. Host rechecks acceptance, ownership and reach." % [item_id if not selected.is_empty() else "unavailable", source, destination] + "\n" + access_hint(record if access_record == null else access_record, source, "Source")
