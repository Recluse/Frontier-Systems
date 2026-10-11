extends SceneTree

class Sessions extends InventoryControllerSessionProvider:
	var allowed: Dictionary = {"alice/one": true, "alice/two": true, "bob/other": true}
	var before_permit: Callable
	func permits_inventory(principal: StringName, session: StringName, world: StringName, region: StringName) -> bool:
		if before_permit.is_valid():
			before_permit.call()
		return world == &"world.test" and region == &"region.test" and allowed.get(String(principal) + "/" + String(session), false)

class FixtureOwner extends InventoryControllerOwner:
	var bodies: Array
	var ids: PackedStringArray
	var deny_commit: bool = false
	var restore_generation: int = 0
	func controller_restore_generation() -> ServiceResult:
		return ServiceResult.success(restore_generation)
	func _init(records: Array, expected_ids: PackedStringArray) -> void:
		bodies = records.duplicate(true)
		ids = expected_ids.duplicate()
	func controller_candidate() -> ServiceResult:
		var candidate: Dictionary = {}
		for body in bodies:
			if candidate.has(body["body_id"]) or not ids.has(body["body_id"]):
				return ServiceResult.failure(&"invalid_candidate", "Fixture owner body mismatch.")
			candidate[body["body_id"]] = body.duplicate(true)
		return ServiceResult.success(candidate)
	func commit_control_epoch(expected: Dictionary, next_epoch: int) -> ServiceResult:
		if deny_commit:
			return ServiceResult.failure(&"binding_conflict", "Injected owner failure.")
		for body in bodies:
			if body == expected:
				if next_epoch != int(body["control_epoch"]) + 1:
					return ServiceResult.failure(&"binding_conflict", "Invalid increment.")
				body["control_epoch"] = next_epoch
				return ServiceResult.success(next_epoch)
		return ServiceResult.failure(&"binding_conflict", "Stale owner candidate.")
var _failures: int = 0

func _initialize() -> void:
	var sessions := Sessions.new()
	var authority := InventoryControllerAuthority.new()
	var bodies: Array = [_body("body.a", "alice", 0), _body("body.b", "bob", 5)]
	_check(authority.initialize(&"world.test", &"region.test", FixtureOwner.new(bodies, PackedStringArray(["body.a", "body.b"])), sessions).is_success, "valid candidate")
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
	_check(other.initialize(&"world.test", &"region.test", FixtureOwner.new([_body("body.a", "alice", 0)], PackedStringArray(["body.a"])), sessions).is_success, "second issuer")
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
	_test_owner(sessions)
	_test_restore(sessions)
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
		_check(not authority.initialize(&"world.test", &"region.test", FixtureOwner.new(candidate, PackedStringArray(["body.a", "body.b"])), sessions).is_success and authority.observation().is_empty(), "invalid candidate atomic")
		_check(authority.initialize(&"world.test", &"region.test", FixtureOwner.new([_body("body.a", "alice", 0)], PackedStringArray(["body.a"])), sessions).is_success, "failed initialization retry")
	var capped := InventoryControllerAuthority.new()
	var many: Array = []
	var ids := PackedStringArray()
	for index in range(33):
		many.append(_body("body.%d" % index, "principal.%d" % index, 0))
		ids.append("body.%d" % index)
	_check(not capped.initialize(&"world.test", &"region.test", FixtureOwner.new(many, ids), sessions).is_success and capped.observation().is_empty(), "binding capacity")
	var exhausted := InventoryControllerAuthority.new()
	_check(exhausted.initialize(&"world.test", &"region.test", FixtureOwner.new([_body("body.a", "alice", InventoryControllerAuthority.MAX_EXACT_INTEGER - 1)], PackedStringArray(["body.a"])), sessions).is_success, "boundary candidate")
	_check(exhausted.bind(&"body.a", &"alice", &"one", InventoryControllerAuthority.MAX_EXACT_INTEGER - 1).is_success, "last exact transition")
	var before: Dictionary = exhausted.observation()
	var token: InventoryControllerToken = exhausted.pin(_context(&"alice", &"one")).value
	_check(exhausted.replace(&"body.a", &"alice", &"two", InventoryControllerAuthority.MAX_EXACT_INTEGER).error_code == &"epoch_exhausted", "replace exhaustion")
	_check(exhausted.revoke(&"body.a", &"alice", InventoryControllerAuthority.MAX_EXACT_INTEGER).error_code == &"epoch_exhausted", "revoke exhaustion")
	_check(exhausted.observation() == before and exhausted.validate(token, _context(&"alice", &"one"), &"body.a").is_success, "exhaustion preserves token and state")
	_check(not exhausted.initialize(&"world.test", &"region.test", FixtureOwner.new([], PackedStringArray()), sessions).is_success and exhausted.observation() == before, "reinitialize forbidden")

func _test_owner(sessions: Sessions) -> void:
	var inventory := InventorySimulationSystem.new()
	_check(inventory.configure_defaults().is_success, "canonical runtime fixture")
	var owner := InventoryRuntimeControllerOwner.new(inventory)
	var canonical_before: Dictionary = inventory.capture_snapshot().value
	var authority := InventoryControllerAuthority.new()
	sessions.allowed["local-inventory-actor/one"] = true
	sessions.allowed["local-inventory-actor/two"] = true
	_check(authority.initialize(&"world.test", &"region.test", owner, sessions).is_success, "validated actual canonical owner")
	var body: Dictionary = owner.controller_candidate().value["body.human-2"]
	var stale: Dictionary = body.duplicate(true)
	stale["body_container_id"] = "foreign.root"
	_check(not owner.commit_control_epoch(stale, 1).is_success and inventory.capture_snapshot().value == canonical_before, "foreign root commit rejected atomically")
	stale = body.duplicate(true)
	stale["principal_id"] = "foreign.principal"
	_check(not owner.commit_control_epoch(stale, 1).is_success, "principal mismatch rejected")
	stale = body.duplicate(true)
	stale["body_id"] = "foreign.body"
	_check(not owner.commit_control_epoch(stale, 1).is_success, "foreign body rejected")
	_check(authority.bind(&"body.human-2", &"local-inventory-actor", &"one", 0).value == 1, "canonical bind")
	var context := _context(&"local-inventory-actor", &"one")
	var token: InventoryControllerToken = authority.pin(context).value
	var snapshot: Dictionary = inventory.capture_snapshot().value
	for record in snapshot["bodies"]:
		if record["body_id"] == "body.human-2":
			_check(record["control_epoch"] == 1, "snapshot shares canonical epoch")
	_check(owner.controller_candidate().value["body.human-2"]["control_epoch"] == authority.observation()["body.human-2"]["control_epoch"], "owner and binding agreement")
	_check(authority.replace(&"body.human-2", &"local-inventory-actor", &"two", 1).value == 2, "canonical replacement")
	_check(not authority.validate(token, context, &"body.human-2").is_success, "canonical replacement fences old token")
	context = _context(&"local-inventory-actor", &"two")
	token = authority.pin(context).value
	body = owner.controller_candidate().value["body.human-2"]
	_check(owner.commit_control_epoch(body, 3).is_success, "trusted owner changes sole epoch")
	_check(authority.observation()["body.human-2"]["control_epoch"] == 3 and not authority.validate(token, context, &"body.human-2").is_success and not authority.pin(context).is_success, "external canonical epoch change fences pin/application")
	var changed: Dictionary = inventory.capture_snapshot().value
	changed["bodies"][0]["body_id"] = "foreign.body"
	var before: Dictionary = inventory.capture_snapshot().value
	_check(not inventory.restore_snapshot_record(changed, 0).is_success and inventory.capture_snapshot().value == before, "foreign runtime body candidate atomic")
	changed = before.duplicate(true)
	changed["owner"]["bodies"][0]["body_container_id"] = changed["owner"]["bodies"][1]["body_container_id"]
	_check(not inventory.restore_snapshot_record(changed, 0).is_success and inventory.capture_snapshot().value == before, "shared body/root mismatch rejected")
	changed = before.duplicate(true)
	for record in changed["bodies"]:
		if record["body_id"] == "body.human-2":
			record["control_epoch"] = InventoryControllerAuthority.MAX_EXACT_INTEGER - 1
	_check(inventory.restore_snapshot_record(changed, 0).is_success, "canonical near exhaustion")
	_check(authority.reconcile_after_restore().is_success, "explicit exhaustion restore reconciliation")
	_check(authority.bind(&"body.human-2", &"local-inventory-actor", &"one", InventoryControllerAuthority.MAX_EXACT_INTEGER - 1).is_success, "last canonical transition")
	before = inventory.capture_snapshot().value
	var binding_before: Dictionary = authority.observation()
	token = authority.pin(_context(&"local-inventory-actor", &"one")).value
	_check(authority.replace(&"body.human-2", &"local-inventory-actor", &"two", InventoryControllerAuthority.MAX_EXACT_INTEGER).error_code == &"epoch_exhausted", "canonical replace exhausted")
	_check(authority.revoke(&"body.human-2", &"local-inventory-actor", InventoryControllerAuthority.MAX_EXACT_INTEGER).error_code == &"epoch_exhausted", "canonical revoke exhausted")
	_check(inventory.capture_snapshot().value == before and authority.observation() == binding_before and authority.pin(_context(&"local-inventory-actor", &"one")).value == token, "exact exhaustion preserves entire canonical record and token")
	var fixture := FixtureOwner.new([_body("body.a", "alice", 0)], PackedStringArray(["body.a"]))
	var isolated := InventoryControllerAuthority.new()
	_check(isolated.initialize(&"world.test", &"region.test", fixture, sessions).is_success, "injected owner")
	fixture.deny_commit = true
	_check(not isolated.bind(&"body.a", &"alice", &"one", 0).is_success and fixture.bodies[0]["control_epoch"] == 0 and not isolated.observation()["body.a"]["active"], "failed canonical commit publishes nothing")
	fixture.deny_commit = false
	_check(isolated.bind(&"body.a", &"alice", &"one", 0).is_success, "owner recovery")
	var retained_bindings: Dictionary = isolated._bindings.duplicate()
	fixture.restore_generation = 1
	fixture.bodies.append(_body("body.b", "alice", 0))
	_check(not isolated.reconcile_after_restore().is_success and isolated._bindings == retained_bindings and isolated._restore_generation == 0, "invalid reconciliation preserves identities and fence")
	fixture.bodies.pop_back()
	_check(isolated.reconcile_after_restore().is_success and not isolated.pin(_context(&"alice", &"one")).is_success, "valid reconciliation retires all bindings")
	_check(isolated.bind(&"body.a", &"alice", &"one", 1).is_success, "fresh binding after candidate repair")
	var race_owner := FixtureOwner.new([_body("body.race", "alice", 0)], PackedStringArray(["body.race"]))
	var race := InventoryControllerAuthority.new()
	_check(race.initialize(&"world.test", &"region.test", race_owner, sessions).is_success, "race owner initialized")
	sessions.before_permit = func() -> void: race_owner.bodies[0]["control_epoch"] = 1
	_check(not race.bind(&"body.race", &"alice", &"one", 0).is_success and race_owner.bodies[0]["control_epoch"] == 1 and not race.observation()["body.race"]["active"], "provider mutation cannot be overwritten or publish token")
	sessions.before_permit = Callable()
	token = isolated.pin(_context(&"alice", &"one")).value
	fixture.bodies[0]["body_container_id"] = "foreign.root"
	_check(not isolated.validate(token, _context(&"alice", &"one"), &"body.a").is_success and not isolated.revoke(&"body.a", &"alice", 1).is_success and isolated.observation().is_empty(), "changed owner root fails closed")
	inventory.free()
	_check(not owner.controller_candidate().is_success, "freed runtime owner fails closed")

func _test_restore(sessions: Sessions) -> void:
	var inventory := InventorySimulationSystem.new()
	_check(inventory.configure_defaults().is_success, "restore fixture")
	var owner := InventoryRuntimeControllerOwner.new(inventory)
	var authority := InventoryControllerAuthority.new()
	var principal: StringName = &"local-inventory-actor"
	var body_id: StringName = &"body.human-2"
	var context := _context(principal, &"one")
	_check(authority.initialize(&"world.test", &"region.test", owner, sessions).is_success, "restore authority")
	_check(authority.bind(body_id, principal, &"one", 0).is_success, "restore initial bind")
	var old_token: InventoryControllerToken = authority.pin(context).value
	var snapshot: Dictionary = inventory.capture_snapshot().value
	var invalid: Dictionary = snapshot.duplicate(true)
	invalid["bodies"][0]["control_epoch"] = -1
	_check(not inventory.restore_snapshot_record(invalid, 0).is_success, "invalid restore rejected")
	_check(inventory.capture_snapshot().value == snapshot and inventory.controller_restore_generation() == 0 and authority.pin(context).value == old_token, "failed restore preserves canonical generation and identity")
	_check(not authority.reconcile_after_restore().is_success and authority.pin(context).value == old_token, "reset without restore rejected atomically")
	# Identical snapshot still replaces the canonical lineage in this process.
	_check(inventory.restore_snapshot_record(snapshot, 0).is_success, "same epoch actual runtime restore")
	_check(inventory.capture_snapshot().value == snapshot and inventory.controller_restore_generation() == 1, "restore preserves canonical record and advances only volatile fence")
	_check(not authority.validate(old_token, context, body_id).is_success and not authority.pin(context).is_success, "same epoch cannot revive pre-restore token")
	_check(authority.observation().is_empty() and authority.profiling_counters()["active_controllers"] == 0, "unreconciled restore makes no active claims")
	_check(not authority.bind(body_id, principal, &"two", 1).is_success and not authority.replace(body_id, principal, &"two", 1).is_success and not authority.revoke(body_id, principal, 1).is_success, "lifecycle blocked until explicit reconciliation")
	_check(authority.reconcile_after_restore().is_success and not authority.pin(context).is_success, "reset does not auto-bind session")
	_check(inventory.capture_snapshot().value == snapshot and not authority.observation()[String(body_id)]["active"], "reconciliation preserves canonical epochs and quantities")
	_check(authority.bind(body_id, principal, &"one", 1).value == 2, "fresh explicit session reuse bind")
	var fresh_token: InventoryControllerToken = authority.pin(context).value
	_check(fresh_token != old_token and authority.validate(fresh_token, context, body_id).is_success and not authority.validate(old_token, context, body_id).is_success, "session reuse cannot revive retired object")
	# Roll back and deliberately reuse the same numerical epoch as fresh_token.
	_check(inventory.restore_snapshot_record(snapshot, 0).is_success and authority.reconcile_after_restore().is_success, "older checkpoint reset")
	_check(authority.bind(body_id, principal, &"one", 1).value == 2 and not authority.validate(fresh_token, context, body_id).is_success, "equal epoch after rollback retains identity fence")
	var runner := SimulationRunner.new()
	_check(runner.register_system(inventory), "restore runner registration")
	fresh_token = authority.pin(context).value
	var current: Dictionary = inventory.capture_snapshot().value
	_check(runner.restore_snapshot(0, {"inventory": current}).is_success and not authority.validate(fresh_token, context, body_id).is_success, "runner restore fences tokens too")
	_check(authority.reconcile_after_restore().is_success, "runner explicit reset")
	# Trusted provider callback restoring identical metadata must not publish token.
	sessions.before_permit = func() -> void: inventory.restore_snapshot_record(current, 0)
	_check(not authority.bind(body_id, principal, &"one", 2).is_success, "provider restore cannot publish token")
	sessions.before_permit = Callable()
	_check(inventory.capture_snapshot().value == current and authority.reconcile_after_restore().is_success and not authority.pin(context).is_success, "provider restore preserved epoch and left inactive binding")
	sessions.before_permit = func() -> void:
		inventory.restore_snapshot_record(current, 0)
		authority.reconcile_after_restore()
	_check(not authority.bind(body_id, principal, &"one", 2).is_success, "provider restore plus reset cannot publish pre-reset lifecycle")
	sessions.before_permit = Callable()
	_check(not authority.pin(context).is_success and inventory.capture_snapshot().value == current, "callback reset leaves no token or epoch increment")
	var reassigned: Dictionary = current.duplicate(true)
	for body in reassigned["bodies"]:
		if body["body_id"] == String(body_id):
			body["principal_id"] = "restored-actor"
	sessions.allowed["restored-actor/one"] = true
	_check(inventory.restore_snapshot_record(reassigned, 0).is_success and authority.reconcile_after_restore().is_success, "reset adopts validated restored principal")
	_check(not authority.bind(body_id, principal, &"one", 2).is_success and not authority.pin(context).is_success, "retired principal cannot regain restored body")
	_check(authority.bind(body_id, &"restored-actor", &"one", 2).is_success, "restored principal needs fresh explicit bind")
	_check(inventory.restore_snapshot_record(current, 0).is_success and authority.reconcile_after_restore().is_success, "return to fixture via explicit reset")
	# Test-only private-field injection reaches the exact bound without a huge loop.
	inventory._controller_restore_generation = InventoryControllerAuthority.MAX_EXACT_INTEGER - 1
	_check(inventory.restore_snapshot_record(current, 0).is_success, "last exact restore generation")
	_check(authority.reconcile_after_restore().is_success and authority.bind(body_id, principal, &"one", 2).is_success, "exhausted generation still permits fresh explicit binding")
	fresh_token = authority.pin(context).value
	current = inventory.capture_snapshot().value
	_check(inventory.restore_snapshot_record(current, 0).error_code == &"restore_generation_exhausted", "restore generation cannot wrap")
	_check(not runner.restore_snapshot(0, {"inventory": current}).is_success, "runner prevalidation rejects exhausted restore")
	_check(inventory.capture_snapshot().value == current and inventory.controller_restore_generation() == InventoryControllerAuthority.MAX_EXACT_INTEGER and authority.pin(context).value == fresh_token, "exhausted restore preserves all canonical and token state")
	runner.free()
	inventory.free()

func _body(id: String, principal: String, epoch: Variant) -> Dictionary:
	return {"body_id": id, "principal_id": principal, "body_container_id": id + ".root", "control_epoch": epoch}

func _context(principal: StringName, session: StringName) -> AuthenticatedCommandContext:
	return AuthenticatedCommandContext.from_authenticated_session(principal, session, &"world.test", &"region.test", PackedStringArray(["inventory.operate"]))

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
