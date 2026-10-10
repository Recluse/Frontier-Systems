extends Node
class_name ComponentHost

## Composition root for the capabilities attached to one entity node.

var _entity: Node
var _components: Dictionary = {}


func _ready() -> void:
	_entity = get_parent()
	if _entity == null:
		push_error("ComponentHost must be a child of an entity node.")


func add_component(component: GameComponent) -> bool:
	if _entity == null or component == null or component.get_parent() != null:
		return false
	if component.component_key == &"" or _components.has(component.component_key):
		return false
	if not component.attach_to(_entity):
		return false
	_components[component.component_key] = component
	add_child(component)
	return true


func get_component(component_key: StringName) -> GameComponent:
	return _components.get(component_key) as GameComponent


func has_component(component_key: StringName) -> bool:
	return _components.has(component_key)


func remove_component(component_key: StringName) -> bool:
	if not _components.has(component_key):
		return false
	var component: GameComponent = _components[component_key]
	_components.erase(component_key)
	component.detach()
	remove_child(component)
	component.queue_free()
	return true


func component_keys() -> Array[StringName]:
	var keys: Array[StringName] = []
	for key in _components:
		keys.append(key)
	return keys


func _exit_tree() -> void:
	for component in _components.values():
		(component as GameComponent).detach()
