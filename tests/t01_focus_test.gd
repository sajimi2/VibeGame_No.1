extends SceneTree
## T01 R1c regression: focus changes must not corrupt a valid cursor sample, and losing focus
## must drop the sample and any pending action edge.
##
## The defect this pins down: a cursor sample is only meaningful as the POSITION + SCALE pair
## captured together. The first fix re-anchored only the scale on focus-in, which re-projected an
## old position through a new mapping and put the 3.11 degree aim error back after a resize.
##
## A headless window does receive application focus notifications, so all of this runs headless
## under normal physics scheduling (states are read at physics_frame boundaries, no node's
## _physics_process is called by hand). What a headless run cannot prove is real focus switching;
## that is listed as unverified in the report.
##
## Runnable with:
##   godot --headless --path <project> --script res://tests/t01_focus_test.gd
## Exits 0 when every case passes, 1 otherwise.

const PLAYER_SCENE := "res://scenes/player.tscn"
const ANGLE_TOLERANCE_DEGREES := 1.0
const START_SIZE := Vector2i(1280, 720)
const SMALLER_SIZE := Vector2i(960, 540)
const VIEWPORT_SIZE := Vector2(640, 360)
const CURSOR_WINDOW_POINT := Vector2(700, 400)

var _failures: Array[String] = []
var _checks := 0
var _player: Node = null
var _recorder: RecordingCommandPort = null
var _window_rescales_viewport := false

func _initialize() -> void:
	_run()

func _run() -> void:
	print("=== T01 focus tests ===")
	await physics_frame
	await _probe_window_rescales_viewport()
	await _test_focus_in_after_resize_keeps_sample()
	await _test_focus_out_then_click_rebuilds_sample()
	await _test_focus_out_drops_pending_action()
	if not _window_rescales_viewport:
		print("T01_FOCUS_TESTS: NOTE this window does not rescale the viewport mapping, so the")
		print("  resize step inside the cases cannot change the expected aim here.")
	print("--- checks=%d failures=%d" % [_checks, _failures.size()])
	if _failures.is_empty():
		print("T01_FOCUS_TESTS: PASS")
		quit(0)
	else:
		for failure in _failures:
			print("T01_FOCUS_TESTS: FAIL %s" % failure)
		quit(1)

# --- harness -------------------------------------------------------------------------------

func _check(condition: bool, message: String) -> bool:
	_checks += 1
	if not condition:
		_failures.append(message)
		print("  [FAIL] %s" % message)
	return condition

func _step() -> void:
	await physics_frame

func _steps(count: int) -> void:
	for _i in count:
		await _step()

func _set_window(size: Vector2i) -> void:
	root.size = size
	await _steps(3)

func _probe_window_rescales_viewport() -> void:
	root.size = START_SIZE
	await _steps(2)
	var first := root.get_stretch_transform().get_scale()
	root.size = SMALLER_SIZE
	await _steps(2)
	var second := root.get_stretch_transform().get_scale()
	_window_rescales_viewport = first.distance_to(second) > 0.001
	print("  stretch scale at %s: %s, at %s: %s -> resize %s" % [
		START_SIZE, first, SMALLER_SIZE, second,
		"changes the mapping" if _window_rescales_viewport else "does not change the mapping"])

## Independent expectation, computed from the engine's own transforms only.
func _expected_facing(body: Node2D) -> Vector2:
	var viewport_point: Vector2 = root.get_stretch_transform().affine_inverse() * CURSOR_WINDOW_POINT
	var world_point: Vector2 = root.get_canvas_transform().affine_inverse() * viewport_point
	return (world_point - body.global_position).normalized()

func _facing() -> Vector2:
	return _player.get_node("ActorActionPort").get_facing()

func _angle_error_degrees(actual: Vector2, expected: Vector2) -> float:
	return absf(rad_to_deg(actual.angle_to(expected)))

func _notify_focus(what: int) -> void:
	_player.get_node("InputAdapter").notification(what)

func _inject_motion_once() -> void:
	var event := InputEventMouseMotion.new()
	event.position = CURSOR_WINDOW_POINT
	root.push_input(event, false)
	await _steps(2)

func _inject_click_once() -> void:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = CURSOR_WINDOW_POINT
	root.push_input(click, false)
	await _steps(2)

func _load_player(with_recorder := false) -> void:
	await _teardown()
	_player = (load(PLAYER_SCENE) as PackedScene).instantiate()
	if with_recorder:
		_recorder = RecordingCommandPort.new()
		_recorder.name = "ActorActionPort"
		var replaced := _player.get_node("ActorActionPort")
		_player.remove_child(replaced)
		replaced.free()
		_player.add_child(_recorder)
	root.add_child(_player)
	_player.global_position = Vector2(300, 200)
	_player.velocity = Vector2.ZERO
	var camera := _player.get_node("FollowCamera") as Camera2D
	camera.position_smoothing_enabled = false
	await _steps(3)

func _teardown() -> void:
	if _player != null and is_instance_valid(_player):
		_player.queue_free()
		_player = null
	_recorder = null
	await physics_frame

# --- cases ---------------------------------------------------------------------------------

func _test_focus_in_after_resize_keeps_sample() -> void:
	print("[test] focus-in after a resize must not disturb a valid sample")
	await _load_player()
	await _set_window(START_SIZE)
	await _inject_motion_once()
	await _set_window(SMALLER_SIZE)
	var want := _expected_facing(_player)
	_check(_angle_error_degrees(_facing(), want) <= ANGLE_TOLERANCE_DEGREES, "aim must be correct after the resize (error=%.5f deg)" % _angle_error_degrees(_facing(), want))

	## The production handler must leave the position/scale pair alone here.
	_notify_focus(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await _steps(3)
	var error := _angle_error_degrees(_facing(), want)
	_check(error <= ANGLE_TOLERANCE_DEGREES, "focus-in alone must not move the aim (actual=%s expected=%s error=%.5f deg)" % [_facing(), want, error])
	await _teardown()

func _test_focus_out_then_click_rebuilds_sample() -> void:
	print("[test] focus-out then focus-in then a click rebuilds the aim")
	await _load_player()
	await _set_window(START_SIZE)
	await _inject_motion_once()
	var want_before := _expected_facing(_player)
	var facing_before := _facing()

	## Losing focus drops the sample: the port keeps its previous facing instead of aiming at a
	## cursor position that may no longer be over this window.
	_notify_focus(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await _steps(3)
	_check(_facing().distance_to(facing_before) < 0.0001, "with no valid sample the previous facing must be kept (before=%s after=%s)" % [facing_before, _facing()])

	## Focus returns, then the first click must restore a full position + scale sample.
	_notify_focus(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await _steps(2)
	await _set_window(SMALLER_SIZE)
	await _inject_click_once()
	var want_after := _expected_facing(_player)
	var error := _angle_error_degrees(_facing(), want_after)
	_check(error <= ANGLE_TOLERANCE_DEGREES, "the first click after focus must rebuild the aim (actual=%s expected=%s error=%.5f deg)" % [_facing(), want_after, error])
	_check(want_before.distance_to(want_after) > 0.001, "the resize must still change the expected aim for this case to be meaningful")
	await _teardown()

func _test_focus_out_drops_pending_action() -> void:
	print("[test] an action queued before focus loss must not arrive afterwards")
	await _load_player(true)
	var recorder := _recorder
	_check(recorder != null, "recording port must be installed")
	if recorder == null:
		await _teardown()
		return

	## Queue an action edge, then lose focus before the physics step that would submit it.
	var event := InputEventKey.new()
	event.physical_keycode = KEY_SPACE
	event.keycode = KEY_SPACE
	event.pressed = true
	Input.parse_input_event(event)
	await _step()
	var arrived_before_focus_out := recorder.received_actions.size()
	_notify_focus(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await _steps(3)
	_check(recorder.received_actions.size() == arrived_before_focus_out, "neither the delivered action nor a new one may appear from the focus change (before=%d after=%d)" % [arrived_before_focus_out, recorder.received_actions.size()])

	## Returning focus is not an input event: it must not replay or invent an action.
	_notify_focus(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await _steps(3)
	_check(recorder.received_actions.size() == arrived_before_focus_out, "focus-in must not replay a cleared action (got %d)" % recorder.received_actions.size())

	## A fresh press after focus returns is still delivered exactly once.
	Input.parse_input_event(event)
	await _steps(2)
	_check(recorder.received_actions.size() == arrived_before_focus_out + 1, "a press after focus must be delivered once (got %d)" % recorder.received_actions.size())
	await _teardown()
