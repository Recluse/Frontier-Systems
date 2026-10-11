extends RefCounted
class_name TerrainParcelLifecycleView

## Read-only text from the authenticated projection; never a lifecycle owner.
static func mass(value: int) -> String:
	return "%d mg (%d.%06d kg)" % [value, value / 1000000, value % 1000000]


static func entry(id: String, record: Dictionary) -> String:
	return "%s · %s · %s" % [id, record["material_id"], mass(int(record["mass_milligrams"]))]


static func describe(terrain: Dictionary, escrow_id: String, parcel_id: String, intent: Dictionary, waiting: bool) -> String:
	var lines: PackedStringArray = []
	if not intent.is_empty():
		lines.append("Unresolved %s #%d · original payload %s. Fresh terrain work is blocked. Retry the original intent with a scoped observation; reconnect first if disconnected. Retry does not promise success or recreate a parcel." % [intent["operation"], intent["request_number"], str(intent["payload"])])
	elif waiting:
		lines.append("Waiting for host confirmation; fresh terrain work is blocked.")
	lines.append("Client retry storage is not a durable host save; host recovery depends on its checkpoint cadence.")
	if terrain.is_empty():
		lines.append("Scoped terrain data unavailable. Carried parcels and returned escrow are unknown, not confirmed empty.")
		lines.append("Retained escrow selection: " + (escrow_id if not escrow_id.is_empty() else "none"))
		lines.append("Retained parcel selection: " + (parcel_id if not parcel_id.is_empty() else "none"))
		return "\n".join(lines)
	var version: int = int(terrain["schema_version"])
	var excavation: PackedStringArray = []
	var returned: PackedStringArray = []
	for id in terrain["transfers"]:
		if terrain.get("fill_only_transfers", []).has(id): returned.append(entry(id, terrain["transfers"][id]))
		else: excavation.append(entry(id, terrain["transfers"][id]))
	lines.append("%s:\n%s" % ["Own escrow (legacy lifecycle classification unavailable)" if version < 3 else "Own excavation escrow", "\n".join(excavation) if not excavation.is_empty() else "None observed."])
	if version == 3:
		var carried: PackedStringArray = []
		for id in terrain["returnable_parcels"]:
			var parcel: Dictionary = terrain["returnable_parcels"][id]
			carried.append(entry(id, parcel) + " · transfer " + parcel["transfer_id"])
		lines.append("Carried returnable parcels:\n" + ("\n".join(carried) if not carried.is_empty() else "None observed."))
		lines.append("Returned fill-only escrow:\n" + ("\n".join(returned) if not returned.is_empty() else "None observed."))
	else:
		lines.append("Carried returnable parcels and returned fill-only escrow unavailable in legacy observation v%d. Return is disabled." % version)
	lines.append("Selected escrow: " + selection(escrow_id, terrain["transfers"]))
	lines.append("Selected carried parcel: " + selection(parcel_id, terrain.get("returnable_parcels", {})))
	lines.append("Lifetime limit: 128 claims across this terrain owner; returning does not free a slot. The observed next claim ordinal is principal-specific, not a remaining-slot count. Returned transfers cannot be rematerialized; use them for fill only.")
	lines.append("Claim prerequisite: " + ("unavailable in legacy v1" if version == 1 else ("lifetime claim limit reached" if terrain["materialize_sequence_exhausted"] else ("host capability ready; select own excavation escrow and have a free hand" if terrain["materialize_ready"] else terrain["materialize_message"]))))
	if version == 3:
		lines.append("Return prerequisite: " + ("return ordinal limit reached" if terrain["return_sequence_exhausted"] else ("host capability ready; select a whole parcel in your owned inventory (including nested storage)" if terrain["return_ready"] else terrain["return_message"])))
	lines.append("Return needs voluntary consciousness, an unreserved manipulator and the observed inventory revision; a tray or another body's parcel must be picked up first. Return needs no shovel, cell or reach. Fill still needs an operational active shovel, free supporting hand, reach and sufficient cell capacity/mass.")
	return "\n".join(lines)


static func selection(id: String, records: Dictionary) -> String:
	if id.is_empty(): return "none selected"
	if not records.has(id): return id + " · no longer observed; select explicitly to change target"
	return entry(id, records[id])
