extends SceneTree

var _failures: int = 0
var _catalog := MaterialCatalog.new()


func _initialize() -> void:
	for path in ["res://data/materials/dirt.v1.json", "res://data/materials/moon-regolith.v1.json"]:
		_check(_catalog.register_definition(JSON.parse_string(FileAccess.get_file_as_string(path))).is_success, "fixture catalog registers")
	_test_transfers_and_recovery()
	_test_retry_tail()
	_test_validation_and_limits()
	if _failures == 0:
		print("Finite terrain ownership, provenance, retry and recovery scenarios passed.")
	quit(0 if _failures == 0 else 1)


func _test_transfers_and_recovery() -> void:
	var owner: TerrainMaterialOwner = TerrainMaterialOwner.create("terrain.test", _catalog, [
		_seed("cell.a", "origin.a", 100, 120), _seed("cell.b", "origin.b", 20, 100),
		_seed("cell.moon", "origin.moon", 10, 100, "material.regolith.moon")]).value
	var initial: Dictionary = owner.to_record()
	var dig: Dictionary = _request(1, "cell.a", 0, "excavate", 60)
	var preview: ServiceResult = owner.plan(dig)
	_check(preview.is_success and owner.to_record() == initial, "planning is pure")
	var pure: ServiceResult = TerrainMaterialState.from_record(initial["cells"]["cell.a"]["state"], _catalog).value.plan_excavation(60)
	_check(preview.value["receipt"]["terrain_plan"] == pure.value, "owner reuses exact pure material plan")
	preview.value["after"]["cells"].clear()
	var dug: ServiceResult = owner.commit(dig)
	_check(dug.is_success, "excavation commits")
	var receipt: Dictionary = dug.value.duplicate(true)
	dug.value["parcels"].clear()
	_check(owner.commit(dig).value == receipt, "retained retry returns detached original receipt")
	_check(owner.to_record()["transfers"]["terrain-transfer-1"]["mass_milligrams"] == 60, "retry does not mint a second transfer")
	_reject_unchanged(owner, _request(1, "cell.a", 0, "excavate", 61), "changed retained intent")
	_reject_unchanged(owner, _request(3, "cell.a", 1, "excavate", 1), "skipped owner sequence")
	_reject_unchanged(owner, _request(2, "cell.a", 0, "excavate", 1), "overlapping stale dig")
	_reject_unchanged(owner, _request(2, "cell.a", 1, "excavate", 41), "finite overdraw")
	_reject_unchanged(owner, _request(2, "cell.a", 1, "fill", 61, "terrain-transfer-1"), "transfer overdraw")
	_reject_unchanged(owner, _request(2, "cell.moon", 0, "fill", 1, "terrain-transfer-1"), "material mismatch")
	_reject_unchanged(owner, _request(2, "cell.a", 1, "fill", 1, "invented.transfer"), "invented fill source")
	var fill: Dictionary = _request(2, "cell.b", 0, "fill", 30, "terrain-transfer-1")
	_check(owner.commit(fill).is_success, "partial transfer fills another homogeneous cell")
	var saved: Dictionary = _json(owner.to_record())
	var restored_result: ServiceResult = TerrainMaterialOwner.from_record(saved, _catalog)
	_check(restored_result.is_success, "partial transfer checkpoint restores: " + restored_result.message)
	if not restored_result.is_success:
		return
	var restored: TerrainMaterialOwner = restored_result.value
	_check(restored.commit(fill).value == owner.commit(fill).value, "restored retry preserves receipt and exact matter")
	_check(restored.to_record()["cells"]["cell.b"]["parcels"] == {"origin.a": 30, "origin.b": 20}, "fill retains both generation origins")
	_check(restored.commit(_request(3, "cell.b", 1, "excavate", 40)).is_success, "mixed provenance terrain excavates")
	var record: Dictionary = restored.to_record()
	_check(record["transfers"]["terrain-transfer-3"]["parcels"] == {"origin.a": 30, "origin.b": 10}, "excavation partitions provenance in stable origin order")
	_check(restored.commit(_request(4, "cell.a", 1, "fill", 30, "terrain-transfer-1")).is_success, "last transfer parcel consumed")
	_check(not restored.to_record()["transfers"].has("terrain-transfer-1"), "empty transfer is removed")
	_check(restored.commit(_request(5, "cell.a", 2, "excavate", 70)).is_success, "terrain can deplete completely")
	record = restored.to_record()
	_check(record["cells"]["cell.a"]["state"]["mass_milligrams"] == 0 and record["cells"]["cell.a"]["parcels"].is_empty(), "depleted cell remains a stable empty record")
	var depletion: ServiceResult = TerrainMaterialOwner.from_record(_json(record), _catalog)
	_check(depletion.is_success, "depletion and consumed transfers recover together")
	if depletion.is_success:
		_reject_unchanged(depletion.value, _request(6, "cell.a", 3, "excavate", 1), "restored depletion never replenishes")
		_check(depletion.value.commit(_request(6, "cell.a", 3, "fill", 70, "terrain-transfer-5")).is_success, "owned loose material reconstructs depleted terrain")
		_reject_unchanged(depletion.value, _request(7, "cell.b", 2, "fill", 91, "terrain-transfer-3"), "capacity and source failure are atomic")
		_check(TerrainMaterialOwner.from_record(_json(depletion.value.to_record()), _catalog).is_success, "reconstruction checkpoint replays all receipts")
	var signals: Dictionary = owner.profiling_signals()
	_check(signals["commits"] == 2 and signals["retries"] == 2 and signals["rejections"] == 7, "bounded counters distinguish commits retries and rejections")


func _test_retry_tail() -> void:
	var owner: TerrainMaterialOwner = TerrainMaterialOwner.create("terrain.tail", _catalog, [_seed("cell.tail", "origin.tail", 1, 1)]).value
	var first: Dictionary = _request(1, "cell.tail", 0, "excavate", 1)
	for sequence in range(1, 71):
		var command: Dictionary = _request(sequence, "cell.tail", sequence - 1, "excavate" if sequence % 2 == 1 else "fill", 1,
			"" if sequence % 2 == 1 else "terrain-transfer-%d" % (sequence - 1))
		_check(owner.commit(command).is_success, "alternating finite transfer commits")
	var record: Dictionary = owner.to_record()
	_check(record["receipts"].size() == TerrainMaterialOwner.MAX_RECEIPTS and record["transfers"].is_empty(), "history and live matter remain bounded")
	var loaded: ServiceResult = TerrainMaterialOwner.from_record(_json(record), _catalog)
	_check(loaded.is_success, "evicted receipt tail restores and replays: " + loaded.message)
	if loaded.is_success:
		_reject_unchanged(loaded.value, first, "expired command after recovery")
		var latest: Dictionary = _request(70, "cell.tail", 69, "fill", 1, "terrain-transfer-69")
		_check(loaded.value.commit(latest).is_success, "latest retained retry survives eviction and restore")
	var recycled: Dictionary = _request(71, "cell.tail", 70, "excavate", 1)
	recycled["request_id"] = first["request_id"]
	_reject_unchanged(owner, recycled, "expired request ID cannot be reused as a fresh sequence")
	var bad: Dictionary = record.duplicate(true)
	bad["receipts"].pop_front()
	_check(not TerrainMaterialOwner.from_record(bad, _catalog).is_success, "missing retained receipt rejects")
	bad = record.duplicate(true)
	bad["receipts"][0]["command"]["sequence"] = 1
	_check(not TerrainMaterialOwner.from_record(bad, _catalog).is_success, "unordered receipt rejects")


func _test_validation_and_limits() -> void:
	var owner: TerrainMaterialOwner = TerrainMaterialOwner.create("terrain.limits", _catalog, [
		_seed("cell.source", "origin.source", 100, 100), _seed("cell.full", "origin.full", 10, 10)]).value
	_check(owner.commit(_request(1, "cell.source", 0, "excavate", 10)).is_success, "capacity fixture excavates")
	_reject_unchanged(owner, _request(2, "cell.full", 0, "fill", 1, "terrain-transfer-1"), "full spatial capacity")
	for amount in [0, -1, 1.5, TerrainMaterialOwner.MAX_INTEGER + 1]:
		var command: Dictionary = _request(2, "cell.source", 1, "excavate", 1)
		command["amount_milligrams"] = amount
		_reject_unchanged(owner, command, "invalid exact quantity")
	var snapshot: Dictionary = owner.to_record()
	var corruptions: Array = []
	var bad: Dictionary = snapshot.duplicate(true)
	bad["transfers"]["terrain-transfer-1"]["mass_milligrams"] += 1
	corruptions.append(bad)
	bad = snapshot.duplicate(true)
	bad["cells"]["cell.source"]["parcels"]["origin.source"] -= 1
	corruptions.append(bad)
	bad = snapshot.duplicate(true)
	bad["cells"]["cell.source"]["state"]["cell_id"] = "another.cell"
	corruptions.append(bad)
	bad = snapshot.duplicate(true)
	bad["origins"]["origin.source"]["material_revision"] = 2
	corruptions.append(bad)
	bad = snapshot.duplicate(true)
	bad["receipts"][0]["terrain_plan"]["after"]["mass_milligrams"] += 1
	corruptions.append(bad)
	bad = snapshot.duplicate(true)
	bad["receipts"][0]["parcels"] = {"origin.full": 10}
	corruptions.append(bad)
	bad = snapshot.duplicate(true)
	bad["cells"]["cell.source"]["capacity_milligrams"] = 80
	corruptions.append(bad)
	bad = snapshot.duplicate(true)
	bad["cells"]["cell.source"]["state"]["state_revision"] = TerrainMaterialOwner.MAX_INTEGER
	corruptions.append(bad)
	for corrupted in corruptions:
		_check(not TerrainMaterialOwner.from_record(_json(corrupted), _catalog).is_success, "inconsistent saved matter identity or receipt rejects")
	var seeds: Array = []
	for index in range(TerrainMaterialOwner.MAX_CELLS + 1):
		seeds.append(_seed("cell.%d" % index, "origin.%d" % index, 1, 1))
	_check(not TerrainMaterialOwner.create("too.many.cells", _catalog, seeds).is_success, "commissioning cell bound rejects")
	_check(not TerrainMaterialOwner.create("overflow", _catalog, [
		_seed("cell.max", "origin.max", TerrainMaterialOwner.MAX_INTEGER, TerrainMaterialOwner.MAX_INTEGER), _seed("cell.extra", "origin.extra", 1, 1)]).is_success, "total commissioned matter is exact and bounded")
	var full: TerrainMaterialOwner = TerrainMaterialOwner.create("transfer.limit", _catalog, [_seed("cell.big", "origin.big", 300, 300)]).value
	for sequence in range(1, TerrainMaterialOwner.MAX_TRANSFERS + 1):
		_check(full.commit(_request(sequence, "cell.big", sequence - 1, "excavate", 1)).is_success, "finite loose transfer fills slot")
	_reject_unchanged(full, _request(257, "cell.big", 256, "excavate", 1), "transfer slot bound")
	_check(full.commit(_request(257, "cell.big", 256, "fill", 1, "terrain-transfer-1")).is_success, "fill frees a transfer slot under backpressure")
	_check(full.commit(_request(258, "cell.big", 257, "excavate", 1)).is_success, "freed slot admits exact extraction")
	_check(TerrainMaterialOwner.from_record(_json(full.to_record()), _catalog).is_success, "full bounded checkpoint recovers")
	_test_provenance_limit()


func _test_provenance_limit() -> void:
	var seeds: Array = [_seed("cell.target", "origin.target", 0, 100)]
	for index in range(TerrainMaterialOwner.MAX_PARCELS + 1):
		seeds.append(_seed("cell.p%d" % index, "origin.p%d" % index, 1, 1))
	var owner: TerrainMaterialOwner = TerrainMaterialOwner.create("provenance.limit", _catalog, seeds).value
	for index in range(TerrainMaterialOwner.MAX_PARCELS):
		var sequence: int = index * 2 + 1
		_check(owner.commit(_request(sequence, "cell.p%d" % index, 0, "excavate", 1)).is_success, "origin excavates")
		_check(owner.commit(_request(sequence + 1, "cell.target", index, "fill", 1, "terrain-transfer-%d" % sequence)).is_success, "provenance merges within bound")
	_check(owner.commit(_request(33, "cell.p16", 0, "excavate", 1)).is_success, "extra origin remains accounted loose matter")
	_reject_unchanged(owner, _request(34, "cell.target", 16, "fill", 1, "terrain-transfer-33"), "provenance map capacity")
	_check(TerrainMaterialOwner.from_record(_json(owner.to_record()), _catalog).is_success, "maximum provenance checkpoint recovers")


func _seed(cell_id: String, origin_id: String, mass: int, capacity: int, material: String = "material.dirt") -> Dictionary:
	return {"state": {"schema_version": 1, "cell_id": cell_id, "state_revision": 0, "material_id": material, "material_revision": 1, "mass_milligrams": mass},
		"capacity_milligrams": capacity, "origin_id": origin_id, "generation_revision": 1}


func _request(sequence: int, cell_id: String, revision: int, operation: String, mass: int, transfer_id: String = "") -> Dictionary:
	return {"sequence": sequence, "request_id": "terrain-request-%d" % sequence, "cell_id": cell_id,
		"expected_cell_revision": revision, "operation": operation, "amount_milligrams": mass, "transfer_id": transfer_id}


func _reject_unchanged(owner: TerrainMaterialOwner, request: Dictionary, message: String) -> void:
	var before: Dictionary = owner.to_record()
	_check(not owner.commit(request).is_success and owner.to_record() == before, message + " rejects without changing canonical state")


func _json(record: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(record))


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)

