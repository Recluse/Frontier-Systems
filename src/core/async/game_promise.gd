extends RefCounted
class_name GamePromise

## A small, callback-based promise for asynchronous game-service boundaries.
## Settlement continuations are always queued through PromiseDispatcher.

enum State {
	PENDING,
	FULFILLED,
	REJECTED,
}

var state: State = State.PENDING
var value: Variant
var _dispatcher: Variant
var _reactions: Array[Dictionary] = []


func _init(dispatcher: Node = null) -> void:
	_dispatcher = dispatcher if dispatcher != null else _default_dispatcher()


func then(on_fulfilled: Callable = Callable(), on_rejected: Callable = Callable()) -> GamePromise:
	var next := GamePromise.new(_dispatcher)
	var reaction: Dictionary = {
		"fulfilled": on_fulfilled,
		"rejected": on_rejected,
		"next": next,
	}
	if state == State.PENDING:
		_reactions.append(reaction)
	else:
		_schedule_reaction(reaction)
	return next


func catch_error(on_rejected: Callable) -> GamePromise:
	return then(Callable(), on_rejected)


func resolve(result: Variant = null) -> void:
	if state != State.PENDING:
		return
	if result == self:
		reject("A promise cannot resolve to itself.")
		return
	if result is GamePromise:
		result.then(
			func(resolved_value: Variant) -> void: resolve(resolved_value),
			func(reason: Variant) -> void: reject(reason)
		)
		return

	state = State.FULFILLED
	value = result
	_flush_reactions()


func reject(reason: Variant) -> void:
	if state != State.PENDING:
		return
	state = State.REJECTED
	value = reason
	_flush_reactions()


func _flush_reactions() -> void:
	var pending: Array[Dictionary] = _reactions
	_reactions = []
	for reaction in pending:
		_schedule_reaction(reaction)


func _schedule_reaction(reaction: Dictionary) -> void:
	var next: GamePromise = reaction["next"]
	if _dispatcher == null or not is_instance_valid(_dispatcher):
		next.reject(ServiceResult.failure(&"promise_dispatcher_unavailable", "Promise continuations require a live PromiseDispatcher."))
		return
	# A bound Callable does not retain its RefCounted owner. The queued record must
	# keep this settled promise alive until its deferred continuation has executed.
	reaction["source"] = self
	if not _dispatcher.enqueue(_run_reaction.bind(reaction)):
		next.reject(ServiceResult.failure(&"promise_queue_full", "Promise continuation queue is full."))


func _run_reaction(reaction: Dictionary) -> void:
	var next: GamePromise = reaction["next"]
	var is_fulfilled: bool = state == State.FULFILLED
	var handler: Callable = reaction["fulfilled"] if is_fulfilled else reaction["rejected"]
	if not handler.is_valid():
		if is_fulfilled:
			next.resolve(value)
		else:
			next.reject(value)
		return

	var result: Variant = handler.call(value)
	if result == next:
		next.reject("A promise reaction cannot resolve to its own result.")
	else:
		next.resolve(result)


func _default_dispatcher() -> Node:
	var scene_tree: SceneTree = Engine.get_main_loop() as SceneTree
	if scene_tree == null:
		return null
	return scene_tree.root.get_node_or_null("PromiseDispatcher")
