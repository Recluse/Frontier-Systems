extends RefCounted
class_name InventoryControllerSessionProvider

## Inject a trusted, synchronous in-memory session/grant view. No I/O here.
## Rechecked on bind/replace, pin and application; missing provider fails closed.
func permits_inventory(_principal: StringName, _session: StringName, _world: StringName, _region: StringName) -> bool:
	return false
