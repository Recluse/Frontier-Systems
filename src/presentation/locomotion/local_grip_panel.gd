extends VBoxContainer
class_name LocalGripPanel

## Disposable development presentation. Scoped observations in, queued intents out.
var _world: WorldRuntime
var _configured: bool = false
var _principal_picker: OptionButton
var _target_picker: OptionButton
var _hand_picker: OptionButton
var _action_picker: OptionButton
var _session_picker: OptionButton
var _status: Label
var _hands_label: Label
var _join_button: Button
var _release_button: Button
var _resume_button: Button
var _observation: Dictionary = {}
var _pending: String = ""
var _feedback: String = ""
var _elapsed: float = 0.0
var _nonce: String = str(Time.get_ticks_usec())


func configure(world: WorldRuntime) -> ServiceResult:
	if _configured or not is_instance_valid(world) or world.get_simulation_system(InventorySimulationSystem.SYSTEM_ID) == null:
		return ServiceResult.failure(&"grip_panel_configuration", "Configure one local world per grip panel.")
	_configured = true
	_world = world
	_world.command_completed.connect(_on_command_completed)
	_world.tree_exiting.connect(_on_world_closed)
	var title := Label.new()
	title.text = "Grips and cooperative handling (development)"
	add_child(title)
	var explanation := Label.new()
	explanation.text = "Grips reserve hands and check capability. Fixture bodies and objects do not move yet."
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(explanation)
	_principal_picker = _picker("Choose a development body.")
	_principal_picker.add_item("Actor")
	_principal_picker.set_item_metadata(0, "local-inventory-actor")
	_principal_picker.add_item("Target (development control)")
	_principal_picker.set_item_metadata(1, "local-inventory-target")
	_principal_picker.item_selected.connect(func(_index: int) -> void: refresh())
	_hands_label = Label.new()
	_hands_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_hands_label)
	_target_picker = _picker("Choose a reachable logical target.")
	_target_picker.item_selected.connect(func(_index: int) -> void: refresh())
	_hand_picker = _picker("Choose one free profile hand.")
	_action_picker = _picker("Choose a sustained grip action.")
	_action_picker.item_selected.connect(func(_index: int) -> void: refresh())
	_join_button = _button("Grip / join selected target", _action.bind("grip_join"))
	_session_picker = _picker("Only this body's sessions are listed.")
	_session_picker.item_selected.connect(func(_index: int) -> void: refresh())
	_release_button = _button("Release selected grip", _action.bind("grip_release"))
	_resume_button = _button("Resume selected solo grip", _action.bind("grip_resume"))
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)
	refresh()
	return ServiceResult.success()


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= 0.1:
		_elapsed = 0.0
		refresh()


func refresh() -> void:
	if not is_instance_valid(_world) or _status == null:
		return
	var observed: ServiceResult = _inventory().local_grip_observation(_context())
	if not observed.is_success:
		_clear("Grip fixtures unavailable for this body.")
		return
	_observation = observed.value
	var hands: Array = []
	var labels: PackedStringArray = []
	for hand in _observation["hands"]:
		labels.append("%s: %s" % [hand["hand_id"], hand["state"]])
		if hand["state"] == "free":
			hands.append(hand["hand_id"])
	_hands_label.text = "Hands: " + (", ".join(labels) if not labels.is_empty() else "no manipulators")
	_fill(_hand_picker, hands)
	var targets: Array = []
	for target in _observation["targets"]:
		targets.append(target["target_id"])
	_fill(_target_picker, targets)
	var selected_target: Dictionary = _find(_observation["targets"], "target_id", _selected(_target_picker))
	var actions: Array = selected_target.get("actions", []).duplicate()
	if selected_target.get("session_id", "") != "":
		actions = [selected_target["session_action"]]
	else:
		# Prefer the actual crate/ladder interaction, while retaining a valid user's choice.
		if actions.has("move_world_object"):
			actions.erase("move_world_object")
			actions.push_front("move_world_object")
		elif actions.has("pull_along"):
			actions.erase("pull_along")
			actions.push_front("pull_along")
	_fill(_action_picker, actions)
	var sessions: Array = []
	var descriptions: PackedStringArray = []
	var already_joined: bool = false
	for session in _observation["sessions"]:
		sessions.append(session["session_id"])
		already_joined = already_joined or session["target_id"] == selected_target.get("target_id", "")
		var state: String = "paused" if session["paused"] else ("capability ready" if session["movement_available"] else "waiting / unavailable")
		descriptions.append("%s: %s (%d participants)" % [session["target_id"], state, session["participant_count"]])
	_fill(_session_picker, sessions)
	var selected_session: Dictionary = _find(_observation["sessions"], "session_id", _selected(_session_picker))
	var busy: bool = not _pending.is_empty()
	_principal_picker.disabled = busy
	_target_picker.disabled = busy or targets.is_empty()
	_hand_picker.disabled = busy or hands.is_empty()
	_action_picker.disabled = busy or actions.is_empty()
	_session_picker.disabled = busy or sessions.is_empty()
	_join_button.disabled = busy or hands.is_empty() or actions.is_empty() or not selected_target.get("reachable", false) or selected_target.get("session_paused", false) or already_joined
	_release_button.disabled = busy or selected_session.is_empty()
	var session_target: Dictionary = _find(_observation["targets"], "target_id", selected_session.get("target_id", ""))
	_resume_button.disabled = busy or not selected_session.get("paused", false) or selected_session.get("participant_count", 0) != 1 or not session_target.get("reachable", false)
	_status.text = "%s\n%s\nTarget: %s" % ["\n".join(descriptions) if not descriptions.is_empty() else "No grips", _feedback, "within reach" if selected_target.get("reachable", false) else "out of reach"]


func _action(operation: String) -> void:
	if not is_instance_valid(_world) or not _pending.is_empty():
		return
	refresh() # Click-time revalidation before building an intent from visible IDs.
	if _observation.is_empty():
		return
	var payload: Dictionary
	if operation == "grip_join":
		if _join_button.disabled:
			return
		var target: Dictionary = _find(_observation["targets"], "target_id", _selected(_target_picker))
		var session_id: String = target["session_id"]
		if session_id.is_empty():
			session_id = "grip-ui-session-%s-%s" % [_nonce, _world.next_local_request_id()]
		payload = {"session_id": session_id, "expected_revision": _observation["grip_revision"], "target_id": target["target_id"], "action": _selected(_action_picker), "hand_ids": [_selected(_hand_picker)]}
	elif operation in ["grip_release", "grip_resume"]:
		if (operation == "grip_release" and _release_button.disabled) or (operation == "grip_resume" and _resume_button.disabled):
			return
		payload = {"session_id": _selected(_session_picker), "expected_revision": _observation["grip_revision"]}
	else:
		return
	var command := InventoryDevelopmentCommand.new()
	command.command_id = StringName("grip-ui-command-%s-%s" % [_nonce, _world.next_local_request_id()])
	command.authenticated_context = _context()
	command.operation = operation
	command.payload = payload
	var queued: ServiceResult = _world.enqueue_command(command)
	_pending = String(command.command_id) if queued.is_success else ""
	_feedback = "Queued " + operation if queued.is_success else queued.message
	refresh()


func _on_command_completed(command: SimulationCommand, result: ServiceResult) -> void:
	if not command is InventoryDevelopmentCommand or _pending.is_empty() or String(command.command_id) != _pending:
		return
	_pending = ""
	_feedback = "Applied " + command.operation if result.is_success else "Rejected: " + result.message
	refresh()


func _on_world_closed() -> void:
	_world = null
	_pending = ""
	_clear("World closed")


func _clear(message: String) -> void:
	_observation = {}
	for picker in [_target_picker, _hand_picker, _action_picker, _session_picker]:
		picker.clear()
		picker.disabled = true
	for button in [_join_button, _release_button, _resume_button]:
		button.disabled = true
	_principal_picker.disabled = not is_instance_valid(_world) or not _pending.is_empty()
	_hands_label.text = "Hands: unavailable"
	_status.text = message


func _inventory() -> InventorySimulationSystem:
	return _world.get_simulation_system(InventorySimulationSystem.SYSTEM_ID) as InventorySimulationSystem


func _context() -> AuthenticatedCommandContext:
	return AuthenticatedCommandContext.for_local_development(StringName(_selected(_principal_picker)), _world.world_id, _world.region_id)


func _picker(hint: String) -> OptionButton:
	var picker := OptionButton.new()
	picker.tooltip_text = hint
	add_child(picker)
	return picker


func _button(title: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.pressed.connect(callback)
	add_child(button)
	return button


static func _selected(picker: OptionButton) -> String:
	return String(picker.get_item_metadata(picker.selected)) if picker.selected >= 0 else ""


static func _find(records: Array, field: String, id: String) -> Dictionary:
	for record in records:
		if record[field] == id:
			return record
	return {}


static func _fill(picker: OptionButton, ids: Array) -> void:
	var previous: String = _selected(picker)
	var unchanged: bool = picker.item_count == ids.size()
	for index in range(ids.size()):
		if not unchanged or picker.get_item_metadata(index) != ids[index]:
			unchanged = false
			break
	if unchanged:
		return
	picker.clear()
	for id in ids:
		picker.add_item(id)
		picker.set_item_metadata(picker.item_count - 1, id)
		if id == previous:
			picker.select(picker.item_count - 1)
