extends SceneTree

class FixtureRemote extends RemoteWorldRuntime:
	var attempts: int = 0
	var fail_connect: bool = false
	func connect_host(_url: String, _key: String) -> ServiceResult:
		attempts += 1
		return ServiceResult.failure(&"remote_connect", "Cannot connect to the host.") if fail_connect else ServiceResult.success()

class FixtureClient extends FirstPlayableBootstrap:
	func _create_client_remote() -> RemoteWorldRuntime:
		return FixtureRemote.new()

var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	var client := FixtureClient.new()
	root.add_child(client)
	var remote: FixtureRemote = client._remote
	check(remote.attempts == 1 and client._reconnect.disabled, "initial connection waits with retry disabled")
	client._connect_client()
	check(remote.attempts == 1, "duplicate pending attempt suppressed")
	remote._connecting = true
	check(not super_connect(remote).is_success, "adapter independently rejects duplicate connection")
	remote._connecting = false
	remote._authenticated = true
	check(not remote.connection_ready(), "authentication alone cannot enable actions")
	var command := CheckpointRequest.new()
	command.command_id = &"pending-save"
	check(not remote.enqueue_command(command).is_success, "no command before fresh observation")
	remote._requests["pending-save"] = command
	var completed: Array = []
	remote.command_completed.connect(func(_command: SimulationCommand, result: ServiceResult) -> void: completed.append(result))
	remote._projection.record = {"stale": true}
	remote._observation = {"stale": true}
	remote._terrain_record = {"stale": true}
	remote._connecting = true
	remote._process(0.0)
	check(remote._requests.is_empty() and completed.size() == 1 and not completed[0].is_success, "disconnect abandons pending command once")
	check(remote._observation.is_empty() and remote._projection.record.is_empty() and remote._terrain_record.is_empty(), "adapter clears stale observations")
	check(client._latest.is_empty() and not client._reconnect.disabled and not client._body_initialized, "shell offers manual recovery after disconnect")
	for action in client._host_actions: check(action.disabled, "direct host action unavailable")
	remote.fail_connect = true
	client._reconnect.pressed.emit()
	check(remote.attempts == 2 and not client._reconnect.disabled and client._connection_status.text.contains("Cannot connect"), "failed attempt remains visible and retryable")
	remote.fail_connect = false
	client._reconnect.pressed.emit()
	client._reconnect.pressed.emit()
	check(remote.attempts == 3 and client._reconnect.disabled, "manual retry suppresses duplicate activation")
	remote.connection_closed.emit("Host rejected authentication or session; check the configured invite and retry.")
	check(not client._reconnect.disabled and client._connection_status.text.contains("rejected"), "auth rejection visible and retryable")
	check(remote._requests.is_empty(), "reconnect never resubmits abandoned command")
	client.free()
	PlayerInputSettings.instance().release_all()
	await process_frame
	print("Manual reconnect adapter and client shell: %d failures" % failures)
	quit(0 if failures == 0 else 1)

func super_connect(remote: RemoteWorldRuntime) -> ServiceResult:
	# A separate real adapter exercises the guard without opening a socket.
	var actual := RemoteWorldRuntime.new()
	root.add_child(actual)
	actual._connecting = remote._connecting
	var result: ServiceResult = actual.connect_host("ws://127.0.0.1:27849", "fixture-unused-key-0000000000000000")
	actual.free()
	return result
