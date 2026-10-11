extends SceneTree

## Disposable presentation-only fixture. No commands, sessions or world state.
var failures: int = 0
var remote: RemoteWorldRuntime


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func settle() -> void:
	for _frame in range(6):
		await process_frame


func panel_fixture() -> PlayerInventoryPanel:
	var scroll := ScrollContainer.new()
	scroll.size = Vector2(420, 240)
	root.add_child(scroll)
	var panel := PlayerInventoryPanel.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(panel)
	panel.configure(remote)
	panel._result.text = "Exact request feedback remains readable."
	return panel


func run() -> void:
	root.size = Vector2i(800, 600)
	remote = RemoteWorldRuntime.new()
	root.add_child(remote)
	# Free before either layout callback can run.
	var panel: PlayerInventoryPanel = panel_fixture()
	await settle()
	panel._pending = "request.early-free"
	panel._reveal_feedback(panel._pending)
	panel.get_parent().free()
	await settle()
	# Free after the first layout frame, with the second phase outstanding.
	panel = panel_fixture()
	await settle()
	panel._pending = "request.between-frames"
	panel._reveal_feedback(panel._pending)
	await process_frame
	panel.get_parent().free()
	await settle()
	# Surviving panels still wait for both layout frames and reveal exact feedback.
	panel = panel_fixture()
	await settle()
	var scroll: ScrollContainer = panel.get_parent()
	check(panel._result.get_global_rect().position.y > scroll.get_global_rect().end.y, "feedback initially outside the viewport")
	panel._pending = "request.live"
	panel._reveal_feedback(panel._pending)
	panel._reveal_feedback(panel._pending)
	check(scroll.scroll_vertical == 0, "reveal is not immediate")
	await process_frame
	check(scroll.scroll_vertical == 0, "first layout frame does not reveal feedback")
	panel._reveal_feedback(panel._pending)
	await settle()
	check(scroll.scroll_vertical > 0 and scroll.get_global_rect().encloses(panel._result.get_global_rect()), "living panel reveals feedback after layout")
	# Replacing the pending request in either phase must suppress the old reveal.
	for elapsed_frames in [0, 1]:
		scroll.scroll_vertical = 0
		panel._pending = "request.stale"
		panel._reveal_feedback(panel._pending)
		for _frame in range(elapsed_frames):
			await process_frame
		panel._pending = "request.replacement"
		await settle()
		check(scroll.scroll_vertical == 0, "stale request cannot scroll in phase %d" % elapsed_frames)
	# Detached controls and scheduled deletion are also ineligible for reveal.
	scroll.scroll_vertical = 0
	panel._pending = "request.detached"
	panel._reveal_feedback(panel._pending)
	scroll.remove_child(panel)
	await settle()
	check(scroll.scroll_vertical == 0, "detached panel cannot reveal feedback")
	panel.free()
	scroll.free()
	panel = panel_fixture()
	await settle()
	panel._pending = "request.queued-free"
	panel._reveal_feedback(panel._pending)
	panel.get_parent().queue_free()
	await settle()
	remote.free()
	print("Inventory feedback lifetime: %d failures; presentation-only fixture" % failures)
	quit(1 if failures else 0)
