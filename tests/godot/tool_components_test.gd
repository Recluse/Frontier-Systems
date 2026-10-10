extends SceneTree

var _failures: int = 0
var _catalog := ToolComponentCatalog.new()
var _ledger: ToolAssemblyLedger


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/tools/catalog.v1.json"))
	_check(_catalog.configure(data).is_success, "default component catalog validates")
	var invalid: Dictionary = data.duplicate(true)
	invalid["materials"]["grade.iron.space"]["wear_ppm_per_cycle"] = -1
	_check(not ToolComponentCatalog.new().configure(invalid).is_success, "negative wear is rejected")
	_ledger = ToolAssemblyLedger.create_empty(_catalog).value
	_add("frame", "part.frame", "grade.iron.space")
	_add("basic", "part.head.multipurpose", "grade.iron.basic")
	_add("space", "part.head.multipurpose", "grade.iron.space")
	_add("drive", "part.drive", "grade.iron.space")
	_add("controller", "part.controller", "grade.iron.space")
	_add("handle", "part.handle", "grade.iron.basic")
	_adopt(_ledger.plan_register_assembly("extractor", "tool.extractor", _revision()))
	_adopt(_ledger.plan_register_assembly("shovel", "tool.shovel", _revision()))
	_adopt(_ledger.plan_fit("extractor", "frame", "frame", _revision()))
	_adopt(_ledger.plan_fit("extractor", "head", "basic", _revision()))
	_check(not _available("action.extract") and _available("action.excavate"), "missing drive disables extraction while preserving manual functions")
	_adopt(_ledger.plan_fit("extractor", "drive", "drive", _revision()))
	_check(_available("action.extract") and not _available("action.extract.automatic"), "powered assembly capabilities require optional controller for automation")
	_adopt(_ledger.plan_fit("extractor", "module", "controller", _revision()))
	_check(_available("action.extract.automatic") and _available("action.scan"), "controller grants multiple functions")
	_check(not _ledger.plan_fit("shovel", "head", "basic", _revision()).is_success, "a component cannot belong to two assemblies")
	var before: Dictionary = _ledger.material_stock()
	_adopt(_ledger.plan_fit("extractor", "head", "space", _revision()))
	_check(_ledger.to_record()["parts"].has("basic") and _ledger.material_stock() == before, "replacement preserves old standalone part and total matter")
	var basic: ToolPartState = ToolPartState.from_record(_ledger.to_record()["parts"]["basic"], _catalog).value
	var space: ToolPartState = ToolPartState.from_record(_ledger.to_record()["parts"]["space"], _catalog).value
	_check(basic.plan_usage(1000).value["integrity_ppm"] == 900000 and space.plan_usage(1000).value["integrity_ppm"] == 999000, "space-grade head has 100 times lower routine wear")
	var drive: ToolPartState = ToolPartState.from_record(_ledger.to_record()["parts"]["drive"], _catalog).value
	var batched: Dictionary = drive.plan_usage(4).value
	for _cycle in range(4): drive = ToolPartState.from_record(drive.plan_usage(1).value, _catalog).value
	_check(drive.to_record() == batched, "fractional wear is invariant under work batching")
	_adopt(_ledger.plan_work("extractor", "action.extract", 1000, _revision()))
	_check(not _ledger.plan_work("extractor", "action.extract", 0, _revision()).is_success, "unbounded/empty work rejects")
	_adopt(_ledger.plan_damage("space", 1000000, _revision()))
	_check(not _available("action.extract") and _ledger.to_record()["parts"]["space"]["integrity_ppm"] == 0 and _ledger.material_stock() == before, "damage disables capabilities without deleting component/material")
	var repair: ServiceResult = _ledger.plan_repair("space", 1000000, _revision())
	_check(repair.is_success and repair.value["energy_joules"] == 2000, "full repair quotes maintenance energy")
	_adopt(repair)
	_check(_available("action.extract"), "settled repair restores fitted capabilities")
	var stale: ServiceResult = _ledger.plan_detach("extractor", "drive", _revision())
	_adopt(_ledger.plan_detach("extractor", "module", _revision()))
	_check(not _ledger.adopt_prepared(stale.value["next_record"]).is_success, "stale preparation cannot overwrite a newer transaction")
	_adopt(_ledger.plan_fit("shovel", "module", "controller", _revision()))
	_check(not _ledger.observation("shovel").value["functions"].has("automation.control"), "nonsensical but compatible mounting remains dormant")
	_check(ToolAssemblyLedger.from_record(JSON.parse_string(JSON.stringify(_ledger.to_record())), _catalog).is_success, "standalone and mounted component conditions restore from JSON")
	var duplicate: Dictionary = _ledger.to_record()
	duplicate["assemblies"]["shovel"]["slots"]["head"] = "space"
	_check(not ToolAssemblyLedger.from_record(duplicate, _catalog).is_success, "duplicate mounting cannot be restored")
	if _failures == 0: print("Modular tools: mounting, standalone replacement, material conservation, capabilities, space-tier/fractional wear, repair plans and restore passed.")
	quit(0 if _failures == 0 else 1)


func _add(id: String, definition: String, material: String) -> void:
	var part: ServiceResult = ToolPartState.create(id, definition, material, _catalog)
	_check(part.is_success, "part creates")
	_adopt(_ledger.plan_register_part(part.value, _revision()))


func _revision() -> int:
	return int(_ledger.to_record()["state_revision"])


func _available(action: String) -> bool:
	return _ledger.observation("extractor").value["actions"][action]["available"]


func _adopt(plan: ServiceResult) -> void:
	_check(plan.is_success, "domain plan prepares: " + plan.message)
	if plan.is_success: _check(_ledger.adopt_prepared(plan.value["next_record"]).is_success, "trusted fixture adopts prepared revision")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
