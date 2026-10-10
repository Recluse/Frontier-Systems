extends RefCounted
class_name BoundedTtlCache

## Bounded LRU cache for non-authoritative derived data, with monotonic TTLs.
## Do not use this cache for canonical world state or durable player data.

var max_entries: int
var _entries: Dictionary = {}
var _access_sequence: int = 0
var _hits: int = 0
var _misses: int = 0
var _evictions: int = 0
var _expirations: int = 0


func _init(capacity: int = 256) -> void:
	max_entries = maxi(1, capacity)


func store(key: String, value: Variant, ttl_seconds: float = -1.0) -> void:
	_expire_if_needed(key)
	_access_sequence += 1
	var expires_at_usec: int = -1
	if ttl_seconds >= 0.0:
		expires_at_usec = Time.get_ticks_usec() + int(ttl_seconds * 1_000_000.0)
	_entries[key] = {
		"value": value,
		"expires_at_usec": expires_at_usec,
		"last_access": _access_sequence,
	}
	_evict_to_capacity()


func fetch(key: String, default_value: Variant = null) -> Variant:
	_expire_if_needed(key)
	if not _entries.has(key):
		_misses += 1
		return default_value

	_hits += 1
	_access_sequence += 1
	var entry: Dictionary = _entries[key]
	entry["last_access"] = _access_sequence
	_entries[key] = entry
	return entry["value"]


func contains_key(key: String) -> bool:
	_expire_if_needed(key)
	return _entries.has(key)


func erase_key(key: String) -> void:
	_entries.erase(key)


func clear() -> void:
	_entries.clear()


func metrics() -> Dictionary:
	return {
		"entries": _entries.size(),
		"capacity": max_entries,
		"hits": _hits,
		"misses": _misses,
		"evictions": _evictions,
		"expirations": _expirations,
	}


func _expire_if_needed(key: String) -> void:
	if not _entries.has(key):
		return
	var entry: Dictionary = _entries[key]
	var expires_at_usec: int = entry["expires_at_usec"]
	if expires_at_usec >= 0 and Time.get_ticks_usec() >= expires_at_usec:
		_entries.erase(key)
		_expirations += 1


func _evict_to_capacity() -> void:
	while _entries.size() > max_entries:
		var least_recent_key: String = ""
		var least_recent_access: int = 9223372036854775807
		for key in _entries:
			var access_sequence: int = _entries[key]["last_access"]
			if access_sequence < least_recent_access:
				least_recent_access = access_sequence
				least_recent_key = key
		_entries.erase(least_recent_key)
		_evictions += 1
