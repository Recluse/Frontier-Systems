extends Node

## Runs promise continuations outside physics callbacks with a per-frame work budget.
## Continuations must stay short; expensive work belongs on a worker or remote service.

@export_range(1, 4096, 1) var callbacks_per_frame: int = 128
@export_range(1, 1000000, 1) var callback_budget_usec: int = 1000
@export_range(1, 65536, 1) var max_pending_callbacks: int = 8192

var _queue: Array[Callable] = []
var _head: int = 0
var _enqueued_count: int = 0
var _completed_count: int = 0
var _rejected_count: int = 0
var _invalid_callback_count: int = 0
var _max_queue_depth: int = 0
var _last_frame_usec: int = 0
var _max_callback_usec: int = 0
var _slow_callback_count: int = 0


func enqueue(callback: Callable) -> bool:
	if not callback.is_valid():
		_invalid_callback_count += 1
		return false
	if _queue.size() - _head >= max_pending_callbacks:
		_rejected_count += 1
		return false

	_queue.append(callback)
	_enqueued_count += 1
	_max_queue_depth = maxi(_max_queue_depth, _queue.size() - _head)
	return true


func metrics() -> Dictionary:
	return {
		"pending_callbacks": _queue.size() - _head,
		"enqueued_count": _enqueued_count,
		"completed_count": _completed_count,
		"rejected_count": _rejected_count,
		"invalid_callback_count": _invalid_callback_count,
		"max_queue_depth": _max_queue_depth,
		"max_pending_callbacks": max_pending_callbacks,
		"last_frame_usec": _last_frame_usec,
		"max_callback_usec": _max_callback_usec,
		"slow_callback_count": _slow_callback_count,
	}


func _process(_delta: float) -> void:
	var frame_started_usec: int = Time.get_ticks_usec()
	var processed: int = 0
	while _head < _queue.size() and processed < callbacks_per_frame:
		if processed > 0 and Time.get_ticks_usec() - frame_started_usec >= callback_budget_usec:
			break
		var callback: Callable = _queue[_head]
		_head += 1
		processed += 1
		if callback.is_valid():
			var callback_started_usec: int = Time.get_ticks_usec()
			callback.call()
			var callback_duration_usec: int = Time.get_ticks_usec() - callback_started_usec
			_max_callback_usec = maxi(_max_callback_usec, callback_duration_usec)
			if callback_duration_usec > callback_budget_usec:
				_slow_callback_count += 1
			_completed_count += 1
	_last_frame_usec = Time.get_ticks_usec() - frame_started_usec

	if _head == _queue.size():
		_queue.clear()
		_head = 0
	elif _head >= 256 and _head * 2 >= _queue.size():
		var remaining: Array[Callable] = []
		for index in range(_head, _queue.size()):
			remaining.append(_queue[index])
		_queue = remaining
		_head = 0
