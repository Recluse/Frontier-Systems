extends SceneTree

class Sessions extends InventoryControllerSessionProvider:
	var allowed: Dictionary = {"alice/one": true, "alice/two": true, "bob/other": true}
	func permits_inventory(principal: StringName, session: StringName, world: StringName, region: StringName) -> bool:
		return world == &"world.test" and region == &"region.test" and allowed.get(String(principal) + "/" + String(session), false)

var _failures: int = 0

func _initialize() -> void:
	var sessions := Sessions.new()
	var authority := InventoryControllerAuthority.new()
	var bodies: Array = [_body("body.a", "alice", 0), _body("body.b", "bob", 5)]
	_check(authority.initialize(&"world.test", &"region.test", bodies, PackedStringArray(["body.a", "body.b"]), sessions).is_success, "valid candidate")
	bodies[0]["control_epoch"] = 300
	_check(authority.observation()["body.a"]["control_epoch"] == 0, "candidate detached")
	_check(authority.bind(&"body.a", &"alice", &"one", 0).value == 1, "bind increments once")
	var context := _context(&"alice", &"one")
	var token: InventoryControllerToken = authority.pin(context).value
	_check(authority.pin(context).value == token, "pin bounded and stable")
	_check(authority.validate(token, context, &"body.a").value["control_epoch"] == 1, "current token")
	var before: Dictionary = authority.observation()
	_check(not authority.bind(&"body.a", &"alice", &"two", 1).is_success, "bind cannot replace")
	_check(not authority.replace(&"body.a", &"bob", &"other", 1).is_success, "foreign principal")
	_check(not authority.replace(&"body.a", &"alice", &"two", 0).is_success, "stale lifecycle")
	_check(not authority.replace(&"body.a", &"alice", &"missing", 1).is_success, "missing session")
	_check(not authority.replace(&"body.a", &"alice", &"one", 1).is_success, "same session")
	_check(authority.observation() == before and authority.pin(context).value == token, "failed lifecycle preserves state and token")
	_check(not authority.validate(token, context, &"body.b").is_success, "foreign body")
	_check(not authority.validate(InventoryControllerToken.new(), context, &"body.a").is_success, "fabricated token")
	var other := InventoryControllerAuthority.new()
	_check(other.initialize(&"world.test", &"region.test", [_body("body.a", "alice", 0)], PackedStringArray(["body.a"]), sessions).is_success, "second issuer")
	_check(other.bind(&"body.a", &"alice", &"one", 0).is_success, "second bind")
	_check(not other.validate(token, context, &"body.a").is_success, "foreign issuer same claims")
	sessions.allowed["alice/one"] = false
	_check(not authority.validate(token, context, &"body.a").is_success and not authority.pin(context).is_success, "provider revocation checked on application and ingress")
	sessions.allowed["alice/one"] = true
	context.permissions.clear()
	_check(not authority.validate(token, context, &"body.a").is_success, "current grant required")
	context = _context(&"alice", &"one")
	context.region_id = &"region.foreign"
	_check(not authority.validate(token, context, &"body.a").is_success, "foreign region")
	context = AuthenticatedCommandContext.for_local_development(&"alice", &"world.test", &"region.test")
	_check(not authority.pin(context).is_success, "debug context excluded")
	context = _context(&"alice", &"one")
	_check(authority.replace(&"body.a", &"alice", &"two", 1).value == 2, "replace increments")
	_check(not authority.validate(token, context, &"body.a").is_success, "retired token")
	var next_context := _context(&"alice", &"two")
	var next_token: InventoryControllerToken = authority.pin(next_context).value
	_check(next_token != token and authority.validate(next_token, next_context, &"body.a").is_success, "new token")
	_check(authority.revoke(&"body.a", &"alice", 2).value == 3, "revoke increments")
	_check(not authority.validate(next_token, next_context, &"body.a").is_success, "revoked token")
	before = authority.observation()
	_check(not authority.revoke(&"body.a", &"alice", 3).is_success and authority.observation() == before, "duplicate revoke unchanged")
	_check(authority.bind(&"body.a", &"alice", &"one", 3).value == 4, "fresh bind")
	_check(not authority.validate(token, _context(&"alice", &"one"), &"body.a").is_success, "session reuse cannot revive identity")
	_check(authority.profiling_counters()["active_controllers"] == 1, "bounded gauge")
	_test_candidates(sessions)
	print("Inventory controller authority: %d failures" % _failures)
	quit(0 if _failures == 0 else 1)

func _test_candidates(sessions: Sessions) -> void:
	var invalid: Array = [
		[_body("body.a", "alice", 0), _body("body.b", "alice", 0)],
		[_body("body.a", "alice", 0), _body("body.a", "bob", 0)],
		[_body("body.a", "alice", 0), _body("body.b", "bob", 1.5)],
		[_body("body.a", "alice", 0), _body("body.foreign", "bob", 0)],
		[_body("body.a", "alice", 0), _body("body.b", "bob", InventoryControllerAuthority.MAX_EXACT_INTEGER + 1)],
	]
	for candidate in invalid:
		var authority := InventoryControllerAuthority.new()
		_check(not authority.initialize(&"world.test", &"region.test", candidate, PackedStringArray(["body.a", "body.b"]), sessions).is_success and authority.observation().is_empty(), "invalid candidate atomic")
		_check(authority.initialize(&"world.test", &"region.test", [_body("body.a", "alice", 0)], PackedStringArray(["body.a"]), sessions).is_success, "failed initialization retry")
	var capped := InventoryControllerAuthority.new()
	var many: Array = []
	var ids := PackedStringArray()
	for index in range(33):
		many.append(_body("body.%d" % index, "principal.%d" % index, 0))
		ids.append("body.%d" % index)
	_check(not capped.initialize(&"world.test", &"region.test", many, ids, sessions).is_success and capped.observation().is_empty(), "binding capacity")
	var exhausted := InventoryControllerAuthority.new()
	_check(exhausted.initialize(&"world.test", &"region.test", [_body("body.a", "alice", InventoryControllerAuthority.MAX_EXACT_INTEGER - 1)], PackedStringArray(["body.a"]), sessions).is_success, "boundary candidate")
	_check(exhausted.bind(&"body.a", &"alice", &"one", InventoryControllerAuthority.MAX_EXACT_INTEGER - 1).is_success, "last exact transition")
	var before: Dictionary = exhausted.observation()
	var token: InventoryControllerToken = exhausted.pin(_context(&"alice", &"one")).value
	_check(exhausted.replace(&"body.a", &"alice", &"two", InventoryControllerAuthority.MAX_EXACT_INTEGER).error_code == &"epoch_exhausted", "replace exhaustion")
	_check(exhausted.revoke(&"body.a", &"alice", InventoryControllerAuthority.MAX_EXACT_INTEGER).error_code == &"epoch_exhausted", "revoke exhaustion")
	_check(exhausted.observation() == before and exhausted.validate(token, _context(&"alice", &"one"), &"body.a").is_success, "exhaustion preserves token and state")
	_check(not exhausted.initialize(&"world.test", &"region.test", [], PackedStringArray(), sessions).is_success and exhausted.observation() == before, "reinitialize forbidden")

func _body(id: String, principal: String, epoch: Variant) -> Dictionary:
	return {"body_id": id, "principal_id": principal, "control_epoch": epoch}

func _context(principal: StringName, session: StringName) -> AuthenticatedCommandContext:
	return AuthenticatedCommandContext.from_authenticated_session(principal, session, &"world.test", &"region.test", PackedStringArray(["inventory.operate"]))

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
