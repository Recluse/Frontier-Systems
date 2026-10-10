extends Node
class_name GameComponent

## Reusable capability node attached to an entity by a ComponentHost.

@export var component_key: StringName
var entity: Node


func attach_to(owner_entity: Node) -> bool:
	if owner_entity == null or entity != null or component_key == &"":
		return false
	entity = owner_entity
	_on_attached()
	return true


func detach() -> void:
	if entity == null:
		return
	_on_detaching()
	entity = null


func _on_attached() -> void:
	pass


func _on_detaching() -> void:
	pass
