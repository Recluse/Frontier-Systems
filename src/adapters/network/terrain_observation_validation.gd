extends RefCounted
class_name TerrainObservationValidation

## Bounded presentation data. This decoder never imports records into a mass owner.
const MAX_INTEGER: int = TerrainMaterialOwner.MAX_INTEGER


static func valid_intent(number: Variant, operation: Variant, payload: Variant) -> bool:
	if operation in ["materialize", "return"]:
		if not ControlContractValidation.is_integer(number, 1, TerrainSimulationSystem.MAX_PORTABLE) or typeof(payload) != TYPE_DICTIONARY or not ToolComponentCatalog.exact(payload, ["item_id" if operation == "return" else "transfer_id", "expected_inventory_revision"]): return false
		var prefix: String = "terrain-item-" if operation == "return" else "terrain-transfer-"
		var id: Variant = payload["item_id" if operation == "return" else "transfer_id"]
		if typeof(id) != TYPE_STRING or id.length() > 128 or not id.begins_with(prefix): return false
		var suffix: String = id.trim_prefix(prefix)
		return suffix.is_valid_int() and suffix == str(suffix.to_int()) and ControlContractValidation.is_integer(suffix.to_int(), 1, MAX_INTEGER) and ControlContractValidation.is_integer(payload["expected_inventory_revision"], 0, MAX_INTEGER - 1)
	return ControlContractValidation.is_integer(number, 1, MAX_INTEGER) and typeof(payload) == TYPE_DICTIONARY and operation in ["excavate", "fill"] and ToolComponentCatalog.exact(payload, ["cell_id", "expected_cell_revision", "amount_milligrams", "transfer_id", "expected_inventory_revision", "expected_tool_revision"]) and typeof(payload["cell_id"]) == TYPE_STRING and TerrainSimulationSystem.CELLS.has(payload["cell_id"]) and ControlContractValidation.is_integer(payload["expected_cell_revision"], 0, MAX_INTEGER) and ControlContractValidation.is_integer(payload["expected_inventory_revision"], 0, MAX_INTEGER) and ControlContractValidation.is_integer(payload["expected_tool_revision"], 0, MAX_INTEGER) and ControlContractValidation.is_integer(payload["amount_milligrams"], 1, TerrainSimulationSystem.MAX_AMOUNT) and (payload["transfer_id"] == "" if operation == "excavate" else ControlContractValidation.is_id(payload["transfer_id"]))


static func valid(value: Variant) -> bool:
	if typeof(value) == TYPE_DICTIONARY and value.get("schema_version") == 3:
		var fields: Array = ["returnable_parcels", "fill_only_transfers", "next_return_request_number", "return_sequence_exhausted", "return_ready", "return_message"]
		for field in fields:
			if not value.has(field): return false
		if typeof(value["returnable_parcels"]) != TYPE_DICTIONARY or value["returnable_parcels"].size() > TerrainSimulationSystem.MAX_PORTABLE or typeof(value["fill_only_transfers"]) != TYPE_ARRAY or value["fill_only_transfers"].size() > TerrainSimulationSystem.MAX_PORTABLE or not ControlContractValidation.is_integer(value["next_return_request_number"], 1, TerrainSimulationSystem.MAX_PORTABLE) or typeof(value["return_sequence_exhausted"]) != TYPE_BOOL or (value["return_sequence_exhausted"] and value["next_return_request_number"] != TerrainSimulationSystem.MAX_PORTABLE) or typeof(value["return_ready"]) != TYPE_BOOL or typeof(value["return_message"]) != TYPE_STRING or value["return_message"].length() > 512 or (value["return_ready"] and not value["return_message"].is_empty()): return false
		var legacy: Dictionary = value.duplicate(true)
		for field in fields: legacy.erase(field)
		legacy["schema_version"] = 2
		if not valid(legacy): return false
		var seen: Dictionary = {}
		for id in value["fill_only_transfers"]:
			if typeof(id) != TYPE_STRING or seen.has(id) or not value["transfers"].has(id): return false
			seen[id] = true
		var visible: int = 0
		for cell in value["cells"].values(): visible += int(cell["state"]["mass_milligrams"])
		for transfer in value["transfers"].values(): visible += int(transfer["mass_milligrams"])
		for id in value["returnable_parcels"]:
			var receipt: Variant = value["returnable_parcels"][id]
			if typeof(id) != TYPE_STRING or typeof(receipt) != TYPE_DICTIONARY or not ToolComponentCatalog.exact(receipt, ["schema_version", "owner_id", "transfer_id", "item_id", "material_id", "material_revision", "mass_milligrams", "parcels"]) or receipt["item_id"] != id or not ControlContractValidation.is_integer(receipt["schema_version"], 1, 1) or receipt["owner_id"] != TerrainSimulationSystem.OWNER_ID or not valid_intent(1, "return", {"item_id": id, "expected_inventory_revision": 0}) or receipt["transfer_id"] != id.replace("terrain-item-", "terrain-transfer-") or value["transfers"].has(receipt["transfer_id"]): return false
			var check: Dictionary = legacy.duplicate(true)
			var transfer: Dictionary = receipt.duplicate(true)
			for field in ["schema_version", "owner_id", "transfer_id", "item_id"]: transfer.erase(field)
			check["transfers"] = {receipt["transfer_id"]: transfer}
			if not valid(check): return false
			visible += int(receipt["mass_milligrams"])
		return visible <= TerrainSimulationSystem.FIXTURE_MASS

	if typeof(value) == TYPE_DICTIONARY and value.get("schema_version") == 2:
		if not ToolComponentCatalog.exact(value, ["schema_version", "owner_id", "cells", "transfers", "next_request_number", "request_sequence_exhausted", "next_materialize_request_number", "materialize_sequence_exhausted", "materialize_ready", "materialize_message"]) or not ControlContractValidation.is_integer(value["next_materialize_request_number"], 1, TerrainSimulationSystem.MAX_PORTABLE) or typeof(value["materialize_sequence_exhausted"]) != TYPE_BOOL or typeof(value["materialize_ready"]) != TYPE_BOOL or typeof(value["materialize_message"]) != TYPE_STRING or value["materialize_message"].length() > 512 or (value["materialize_ready"] and not value["materialize_message"].is_empty()): return false
		var legacy: Dictionary = value.duplicate(true)
		for field in ["next_materialize_request_number", "materialize_sequence_exhausted", "materialize_ready", "materialize_message"]: legacy.erase(field)
		legacy["schema_version"] = 1
		return valid(legacy)
	if typeof(value) != TYPE_DICTIONARY or not ToolComponentCatalog.exact(value, ["schema_version", "owner_id", "cells", "transfers", "next_request_number", "request_sequence_exhausted"]) or not ControlContractValidation.is_integer(value["schema_version"], 1, 1) or value["owner_id"] != TerrainSimulationSystem.OWNER_ID or not ControlContractValidation.is_integer(value["next_request_number"], 1, MAX_INTEGER) or typeof(value["request_sequence_exhausted"]) != TYPE_BOOL or (value["request_sequence_exhausted"] and value["next_request_number"] != MAX_INTEGER): return false
	if typeof(value["cells"]) != TYPE_DICTIONARY or value["cells"].size() != 2 or typeof(value["transfers"]) != TYPE_DICTIONARY or value["transfers"].size() > TerrainMaterialOwner.MAX_TRANSFERS: return false
	var visible_mass: int = 0
	var capacity: int = -1
	for id in TerrainSimulationSystem.CELLS:
		var cell: Variant = value["cells"].get(id)
		if typeof(cell) != TYPE_DICTIONARY or not ToolComponentCatalog.exact(cell, ["state", "position_millimetres", "capacity_milligrams", "work_ready", "work_message"]) or not InventorySpatialMath.is_position(cell["position_millimetres"]) or InventorySpatialMath.normalized(cell["position_millimetres"]) != TerrainSimulationSystem.CELLS[id] or not ControlContractValidation.is_integer(cell["capacity_milligrams"], 0, TerrainSimulationSystem.FIXTURE_MASS) or int(cell["capacity_milligrams"]) not in [0, TerrainSimulationSystem.FIXTURE_MASS] or typeof(cell["work_ready"]) != TYPE_BOOL or typeof(cell["work_message"]) != TYPE_STRING or cell["work_message"].length() > 512 or (cell["work_ready"] and not cell["work_message"].is_empty()): return false
		if capacity >= 0 and capacity != int(cell["capacity_milligrams"]): return false
		capacity = int(cell["capacity_milligrams"])
		var state: Variant = cell["state"]
		if typeof(state) != TYPE_DICTIONARY or not ToolComponentCatalog.exact(state, ["schema_version", "cell_id", "state_revision", "material_id", "material_revision", "mass_milligrams"]) or not ControlContractValidation.is_integer(state["schema_version"], 1, 1) or state["cell_id"] != id or state["material_id"] != "material.dirt" or not ControlContractValidation.is_integer(state["material_revision"], 1, 1) or not ControlContractValidation.is_integer(state["state_revision"], 0, MAX_INTEGER) or not ControlContractValidation.is_integer(state["mass_milligrams"], 0, capacity): return false
		visible_mass += int(state["mass_milligrams"])
	for id in value["transfers"]:
		if typeof(id) != TYPE_STRING or not id.begins_with("terrain-transfer-"): return false
		var suffix: String = id.trim_prefix("terrain-transfer-")
		if suffix.length() > 16 or not suffix.is_valid_int() or suffix != str(suffix.to_int()) or suffix.to_int() < 1 or suffix.to_int() > MAX_INTEGER: return false
		var transfer: Variant = value["transfers"][id]
		if typeof(transfer) != TYPE_DICTIONARY or not ToolComponentCatalog.exact(transfer, ["material_id", "material_revision", "mass_milligrams", "parcels"]) or transfer["material_id"] != "material.dirt" or not ControlContractValidation.is_integer(transfer["material_revision"], 1, 1) or not ControlContractValidation.is_integer(transfer["mass_milligrams"], 1, capacity) or typeof(transfer["parcels"]) != TYPE_DICTIONARY or transfer["parcels"].is_empty() or transfer["parcels"].size() > TerrainMaterialOwner.MAX_PARCELS: return false
		var parcel_mass: int = 0
		for origin in transfer["parcels"]:
			if origin != "terrain.dirt.source.generation" or not ControlContractValidation.is_integer(transfer["parcels"][origin], 1, capacity): return false
			parcel_mass += int(transfer["parcels"][origin])
		if parcel_mass != int(transfer["mass_milligrams"]): return false
		visible_mass += parcel_mass
	return visible_mass <= capacity


static func normalized(value: Dictionary) -> Dictionary:
	var record: Dictionary = value.duplicate(true)
	record["schema_version"] = int(record["schema_version"])
	record["next_request_number"] = int(record["next_request_number"])
	if record.has("next_return_request_number"):
		record["next_return_request_number"] = int(record["next_return_request_number"])
		for receipt in record["returnable_parcels"].values():
			for field in ["schema_version", "material_revision", "mass_milligrams"]: receipt[field] = int(receipt[field])
			for origin in receipt["parcels"]: receipt["parcels"][origin] = int(receipt["parcels"][origin])
	if record.has("next_materialize_request_number"): record["next_materialize_request_number"] = int(record["next_materialize_request_number"])
	for cell in record["cells"].values():
		cell["position_millimetres"] = InventorySpatialMath.normalized(cell["position_millimetres"])
		cell["capacity_milligrams"] = int(cell["capacity_milligrams"])
		for field in ["schema_version", "state_revision", "material_revision", "mass_milligrams"]: cell["state"][field] = int(cell["state"][field])
	for transfer in record["transfers"].values():
		for field in ["material_revision", "mass_milligrams"]: transfer[field] = int(transfer[field])
		for origin in transfer["parcels"]: transfer["parcels"][origin] = int(transfer["parcels"][origin])
	return record
