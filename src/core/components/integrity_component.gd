extends GameComponent
class_name IntegrityComponent

## Persistent, repairable condition state for a physical entity component.
## Zero integrity makes the part salvageable; it does not delete the part or kill occupants.

enum Condition {
	OPERATIONAL,
	DEGRADED,
	DISABLED,
	SALVAGEABLE,
}

signal integrity_changed(integrity: float, condition: Condition)

@export_range(0.01, 1000000.0, 0.01) var maximum_integrity: float = 100.0
@export_range(0.0, 1.0, 0.01) var degraded_below_fraction: float = 0.75
@export_range(0.0, 1.0, 0.01) var disabled_below_fraction: float = 0.05

var integrity: float = 100.0
var condition: Condition = Condition.OPERATIONAL


func _ready() -> void:
	maximum_integrity = maxf(maximum_integrity, 0.01)
	integrity = clampf(integrity, 0.0, maximum_integrity)
	_refresh_condition()


func apply_damage(amount: float) -> ServiceResult:
	if amount <= 0.0:
		return ServiceResult.failure(&"invalid_damage", "Damage must be greater than zero.")
	var previous_integrity: float = integrity
	integrity = maxf(integrity - amount, 0.0)
	_refresh_condition()
	if not is_equal_approx(previous_integrity, integrity):
		integrity_changed.emit(integrity, condition)
	return ServiceResult.success(snapshot())


func repair(amount: float) -> ServiceResult:
	if amount <= 0.0:
		return ServiceResult.failure(&"invalid_repair", "Repair amount must be greater than zero.")
	var previous_integrity: float = integrity
	integrity = minf(integrity + amount, maximum_integrity)
	_refresh_condition()
	if not is_equal_approx(previous_integrity, integrity):
		integrity_changed.emit(integrity, condition)
	return ServiceResult.success(snapshot())


func is_operational() -> bool:
	return condition == Condition.OPERATIONAL or condition == Condition.DEGRADED


func is_salvageable() -> bool:
	return condition == Condition.SALVAGEABLE


func snapshot() -> Dictionary:
	return {
		"component_key": component_key,
		"integrity": integrity,
		"maximum_integrity": maximum_integrity,
		"condition": condition,
	}


func _refresh_condition() -> void:
	var integrity_fraction: float = integrity / maximum_integrity
	if integrity <= 0.0:
		condition = Condition.SALVAGEABLE
	elif integrity_fraction <= disabled_below_fraction:
		condition = Condition.DISABLED
	elif integrity_fraction < degraded_below_fraction:
		condition = Condition.DEGRADED
	else:
		condition = Condition.OPERATIONAL
