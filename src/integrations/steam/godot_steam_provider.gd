extends Node
class_name GodotSteamProvider

## Project-owned adapter for the GodotSteam GDExtension.
## Gameplay and simulation systems should depend on this adapter, not Steam globals.

var is_initialized: bool = false
var _steam: Object
var _embed_callbacks: bool = false


func initialize(app_id: int, embed_callbacks: bool = false) -> GamePromise:
	var promise := GamePromise.new()
	if is_initialized:
		promise.resolve(ServiceResult.success({"status": 0, "already_initialized": true}))
		return promise
	if app_id <= 0:
		promise.reject(ServiceResult.failure(&"invalid_app_id", "A positive Steam application ID is required."))
		return promise
	if not Engine.has_singleton("Steam"):
		promise.reject(ServiceResult.failure(&"steam_extension_missing", "GodotSteam is not available in this build."))
		return promise

	_steam = Engine.get_singleton("Steam")
	_embed_callbacks = embed_callbacks
	var result: Variant = _steam.call("steamInitEx", app_id, embed_callbacks)
	if not result is Dictionary or int(result.get("status", 1)) != 0:
		var detail: String = str(result.get("verbal", "Steam initialization failed.")) if result is Dictionary else "GodotSteam returned an unexpected initialization response."
		promise.reject(ServiceResult.failure(&"steam_initialization_failed", detail))
		return promise

	is_initialized = true
	promise.resolve(ServiceResult.success(result))
	return promise


func shutdown() -> void:
	if not is_initialized or _steam == null:
		return
	_steam.call("steamShutdown")
	is_initialized = false
	_steam = null


func _process(_delta: float) -> void:
	if is_initialized and not _embed_callbacks:
		_steam.call("run_callbacks")


func _exit_tree() -> void:
	shutdown()
