extends VBoxContainer
class_name LocalHealthPanel

## Disposable own-body display. No treatment commands or target selection.
const REFRESH_SECONDS: float = 0.1
const PART_LABELS: Dictionary = {"head": "Head", "torso": "Torso", "arm.left": "Left arm", "arm.right": "Right arm", "leg.left": "Left leg", "leg.right": "Right leg"}
var _world: WorldRuntime
var _configured: bool = false
var _elapsed: float = 0.0
var _status: Label
var _injuries: Label
var _timing: Label


func configure(world: WorldRuntime) -> ServiceResult:
	if _configured or not is_instance_valid(world):
		return ServiceResult.failure(&"health_panel_configuration", "Configure one local world per health panel.")
	_configured = true
	_world = world
	_world.tree_exiting.connect(_on_world_closed)
	var title := _label()
	title.text = "Your health (development body)"
	_status = _label()
	_injuries = _label()
	_timing = _label()
	refresh()
	return ServiceResult.success()


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= REFRESH_SECONDS:
		_elapsed = 0.0
		refresh()


func refresh() -> void:
	if _status == null:
		return
	if not is_instance_valid(_world):
		_clear("Health unavailable: world closed")
		return
	var context := AuthenticatedCommandContext.for_local_development(&"local-inventory-actor", _world.world_id, _world.region_id)
	var observed: ServiceResult = _world.own_health_observation(context)
	if not observed.is_success:
		_clear("Health unavailable for your body")
		return
	var record: Dictionary = observed.value
	_status.text = "Consciousness: %s%s\nVoluntary inventory actions: %s" % [String(record["consciousness"]).capitalize(), " (recovering)" if record["recovering"] else "", "available" if record["voluntary_actions_available"] else "unavailable"]
	var lines: PackedStringArray = []
	for part_id in BodyInjuryState.PARTS:
		var part: Dictionary = record["parts"][part_id]
		lines.append("%s — blunt %d/1000, burn %d/1000" % [PART_LABELS[part_id], part["blunt"], part["burn"]])
	lines.append("Systemic oxygen injury: %d/1000" % record["oxygen_damage_permille"])
	_injuries.text = "\n".join(lines)
	_timing.text = "Injury revision %d · consciousness assessed at tick %d%s\nValues show injury severity, not remaining health. Body is separate from the local walker." % [record["injury_revision"], record["last_assessed_tick"], " (new injury awaiting assessment)" if record["injury_changed_tick"] > record["last_assessed_tick"] else ""]


func _on_world_closed() -> void:
	_world = null
	_clear("Health unavailable: world closed")
	set_process(false)


func _clear(message: String) -> void:
	_status.text = message
	_injuries.text = ""
	_timing.text = ""


func _label() -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(label)
	return label
