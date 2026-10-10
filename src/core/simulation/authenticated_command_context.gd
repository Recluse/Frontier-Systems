extends RefCounted
class_name AuthenticatedCommandContext

## Server-local identity and grants bound after session authentication.
## Never serialize this object or accept it from a network client.

enum Origin {
	DEVELOPMENT_LOCAL,
	AUTHENTICATED_SESSION,
}

var principal_id: StringName
var session_id: StringName
var world_id: StringName
var region_id: StringName
var origin: Origin = Origin.AUTHENTICATED_SESSION
var permissions: Dictionary = {}
## Server-derived tool instance IDs grouped by capability. Transport clients must
## never populate this data directly; rebuild it from the authoritative loadout.
var tools_by_capability: Dictionary = {}


static func from_authenticated_session(
	principal: StringName,
	session: StringName,
	world: StringName,
	region: StringName,
	granted_permissions: PackedStringArray,
	verified_tools_by_capability: Dictionary = {}
) -> AuthenticatedCommandContext:
	var context := AuthenticatedCommandContext.new()
	context.principal_id = principal
	context.session_id = session
	context.world_id = world
	context.region_id = region
	context.origin = Origin.AUTHENTICATED_SESSION
	for permission in granted_permissions:
		if not permission.strip_edges().is_empty():
			context.permissions[permission] = true
	for capability in verified_tools_by_capability:
		if (typeof(capability) == TYPE_STRING or typeof(capability) == TYPE_STRING_NAME) and not String(capability).strip_edges().is_empty():
			var tool_ids: PackedStringArray = PackedStringArray()
			var supplied_ids: Variant = verified_tools_by_capability[capability]
			if typeof(supplied_ids) == TYPE_PACKED_STRING_ARRAY:
				tool_ids = supplied_ids
			elif typeof(supplied_ids) == TYPE_ARRAY:
				for tool_id in supplied_ids:
					if typeof(tool_id) == TYPE_STRING:
						tool_ids.append(tool_id)
			if not tool_ids.is_empty():
				context.tools_by_capability[StringName(capability)] = tool_ids
	return context


static func for_local_development(
	principal: StringName,
	world: StringName,
	region: StringName,
	allow_airlock_operation: bool = true
) -> AuthenticatedCommandContext:
	var context := AuthenticatedCommandContext.new()
	if not OS.is_debug_build():
		return context
	context.principal_id = principal
	context.session_id = &"local-development"
	context.world_id = world
	context.region_id = region
	context.origin = Origin.DEVELOPMENT_LOCAL
	context.permissions["control.debug_pulse"] = true
	context.permissions["control.configure"] = true
	context.permissions["inventory.development"] = true
	if allow_airlock_operation:
		context.permissions["airlock.operate"] = true
	context.permissions["airlock.bypass.electrical"] = true
	context.permissions["airlock.bypass.mechanical"] = true
	context.permissions["airlock.manual_operate"] = true
	context.tools_by_capability[&"tool.electrical_probe"] = PackedStringArray(["debug-electrical-probe"])
	context.tools_by_capability[&"tool.manual_release"] = PackedStringArray(["debug-manual-release-tool"])
	context.tools_by_capability[&"tool.pry"] = PackedStringArray(["debug-crowbar"])
	return context


func is_valid_for(world: StringName, region: StringName) -> bool:
	return (
		(origin == Origin.DEVELOPMENT_LOCAL or origin == Origin.AUTHENTICATED_SESSION)
		and not String(principal_id).strip_edges().is_empty()
		and not String(session_id).strip_edges().is_empty()
		and world_id == world
		and region_id == region
	)


func has_permission(permission_id: String) -> bool:
	return permissions.get(permission_id, false) == true


func has_tool_capability(capability_id: String) -> bool:
	var tool_ids: Variant = tools_by_capability.get(StringName(capability_id), PackedStringArray())
	return (typeof(tool_ids) == TYPE_PACKED_STRING_ARRAY or typeof(tool_ids) == TYPE_ARRAY) and not tool_ids.is_empty()


func tool_ids_for_capability(capability_id: String) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	var tool_ids: Variant = tools_by_capability.get(StringName(capability_id), PackedStringArray())
	if typeof(tool_ids) == TYPE_PACKED_STRING_ARRAY:
		return tool_ids.duplicate()
	if typeof(tool_ids) == TYPE_ARRAY:
		for tool_id in tool_ids:
			if typeof(tool_id) == TYPE_STRING:
				result.append(tool_id)
	return result
