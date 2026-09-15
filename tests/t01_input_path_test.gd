extends SceneTree
## T01 input-path regression tests (round 2). Covers the real input adapter instead of the
## production test override:
##   - R1: the aim is recomputed every physics step, so a stationary cursor stays correct while
##         the camera or the body moves.
##   - R2: input is sampled before the body step, so press/release take effect on the very next
##         physics step (no one-frame lag) and an action edge is consumed exactly once.
##   - R3: the facing arrow carries a real gradient resource.
##
## Injected mouse events use root.push_input(event, true): the second argument keeps the position
## in viewport-local coordinates, so expectations need no calibration of engine internals.
##
## Runnable with:
##   godot --headless --path <project> --script res://tests/t01_input_path_test.gd
## Exits 0 when every test passes, 1 when any test fails.

const PLAYER_SCENE := "res://scenes/player.tscn"
const SPEED := 90.0
const STEP_SECONDS := 1.0 / 60.0
const VIEWPORT_SIZE := Vector2(640, 360)

var _failures: Array[String] = []
var _checks := 0
var _player: Node = null
var _recorder: RecordingCommandPort = null
var _camera_node: Camera2D = null

func _initialize() -> void:
	_run()

func _run() -> void:
	print("=== T01 input path tests ===")
	await physics_frame
	await _test_stationary_cursor_tracks_camera()
	await _test_stationary_cursor_tracks_body()
	await _test_press_release_same_step()
	await _test_action_edge_consumed_once()
	await _test_facing_arrow_gradient()
	print("--- checks=%d failures=%d" % [_checks, _failures.size()])
	if _failures.is_empty():
		print("T01_INPUT_TESTS: PASS")
		quit(0)
	else:
		for failure in _failures:
			print("T01_INPUT_TESTS: FAIL %s" % failure)
		quit(1)

# --- harness -------------------------------------------------------------------------------

func _check(condition: bool, message: String) -> bool:
	_checks += 1
	if not condition:
		_failures.append(message)
		print("  [FAIL] %s" % message)
	return condition

func _check_close(actual: float, expected: float, tolerance: float, message: String) -> bool:
	return _check(absf(actual - expected) <= tolerance, "%s (actual=%.6f expected=%.6f tol=%.6f)" % [message, actual, expected, tolerance])

func _step() -> void:
	await physics_frame

func _steps(count: int) -> void:
	for _i in count:
		await _step()

func _load_player(spawn: Vector2) -> void:
	await _teardown()
	_player = (load(PLAYER_SCENE) as PackedScene).instantiate()
	root.add_child(_player)
	_player.global_position = spawn
	_player.velocity = Vector2.ZERO
	_recorder = null
	_camera_node = _player.get_node("FollowCamera") as Camera2D
	await _step()

## Loads the player with the real port replaced by a recording double, so action submission
## timing is observable. The whole subtree is built before entering the tree, which is when the
## adapter resolves its command_port_path.
func _load_player_with_recorder(spawn: Vector2) -> void:
	await _teardown()
	_player = (load(PLAYER_SCENE) as PackedScene).instantiate()
	_recorder = RecordingCommandPort.new()
	_recorder.name = "ActorActionPort"
	var replaced := _player.get_node("ActorActionPort")
	_player.remove_child(replaced)
	replaced.free()
	_player.add_child(_recorder)
	root.add_child(_player)
	_player.global_position = spawn
	_player.velocity = Vector2.ZERO
	await _step()

func _teardown() -> void:
	if _camera_node != null and is_instance_valid(_camera_node) and _camera_node.get_parent() == root:
		root.remove_child(_camera_node)
		_camera_node.free()
	_camera_node = null
	if _player != null and is_instance_valid(_player):
		_player.queue_free()
		_player = null
	_recorder = null
	await physics_frame

func _port() -> Node:
	return _player.get_node("ActorActionPort")

func _adapter() -> Node:
	return _player.get_node("InputAdapter")

func _camera() -> Camera2D:
	return _camera_node

## Freezes the camera at an explicit position so the canvas transform is known exactly.
## The camera is reparented out of the body: as a child it re-centres on the body every frame,
## which would silently move the canvas transform whenever the body moves.
func _place_camera(at: Vector2) -> void:
	var camera := _camera()
	if camera == null:
		return
	if camera.get_parent() != root:
		camera.get_parent().remove_child(camera)
		root.add_child(camera)
	camera.position_smoothing_enabled = false
	camera.global_position = at
	camera.reset_smoothing()
	camera.make_current()
	await _steps(2)

## Injects a cursor position in viewport-local coordinates.
func _inject_cursor(viewport_point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = viewport_point
	event.global_position = viewport_point
	event.relative = Vector2(1, -1)
	root.push_input(event, true)
	await _steps(2)

## Independent expectation: cursor viewport point -> world point -> direction from the body.
func _expected_facing(body: Node2D, viewport_point: Vector2) -> Vector2:
	var world_point: Vector2 = root.get_canvas_transform().affine_inverse() * viewport_point
	return (world_point - body.global_position).normalized()

func _angle_error_degrees(actual: Vector2, expected: Vector2) -> float:
	return absf(rad_to_deg(actual.angle_to(expected)))

## Injects a real key event for an InputMap action through Input.parse_input_event, which both
## updates the action state that movement polling reads AND dispatches the event to
## _unhandled_input that action edges are read from. (Viewport.push_input only delivers the
## event, and Input.action_press only flips the state, so neither alone drives the adapter.)
func _push_key(action: StringName, pressed: bool) -> void:
	Input.parse_input_event(_key_event(action, pressed))

func _press_key(action: StringName) -> void:
	_push_key(action, true)
	await _step()

func _release_key(action: StringName) -> void:
	_push_key(action, false)
	await _step()

func _key_event(action: StringName, pressed: bool) -> InputEventKey:
	var keycode := _keycode_for(action)
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.keycode = keycode
	event.pressed = pressed
	return event

func _keycode_for(action: StringName) -> Key:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			return (event as InputEventKey).physical_keycode as Key
	return KEY_NONE

# --- R1 ------------------------------------------------------------------------------------

func _test_stationary_cursor_tracks_camera() -> void:
	print("[test] R1 stationary cursor: camera moves, cursor does not")
	await _load_player(Vector2(300, 200))
	await _place_camera(Vector2(300, 120))
	var cursor := VIEWPORT_SIZE * 0.5 + Vector2(30, 40)

	await _inject_cursor(cursor)
	var want_before := _expected_facing(_player, cursor)
	_check_close(_angle_error_degrees(_port().get_facing(), want_before), 0.0, 0.5, "facing must match the cursor before the camera moves")

	## No further mouse injection: only the camera moves.
	await _place_camera(Vector2(300, 60))
	var want_after := _expected_facing(_player, cursor)
	_check(absf(want_after.dot(want_before) - 1.0) > 0.01, "the camera move must actually change the expected aim")
	var actual: Vector2 = _port().get_facing()
	_check(_angle_error_degrees(actual, want_after) <= 1.0, "stationary cursor must track the camera (actual=%s expected=%s error=%.5f deg)" % [actual, want_after, _angle_error_degrees(actual, want_after)])

	## And the arrow must render it.
	var arrow := _player.get_node("Visual/FacingArrow") as Node2D
	_check_close(arrow.rotation, want_after.angle(), 0.01, "facing arrow must follow the recomputed aim")
	await _teardown()

func _test_stationary_cursor_tracks_body() -> void:
	print("[test] R1 stationary cursor: body moves, cursor does not")
	await _load_player(Vector2(300, 200))
	await _place_camera(Vector2(300, 120))
	var cursor := VIEWPORT_SIZE * 0.5 + Vector2(60, 0)
	await _inject_cursor(cursor)
	var want_before := _expected_facing(_player, cursor)
	_check_close(_angle_error_degrees(_port().get_facing(), want_before), 0.0, 0.5, "facing must match the cursor before the body moves")

	## Only the body moves (no cursor event, camera pinned). Move sideways off the sight line so
	## the new expectation cannot coincide with the old one.
	_player.global_position = Vector2(250, 200)
	await _steps(2)
	var want_after := _expected_facing(_player, cursor)
	_check(absf(want_after.dot(want_before) - 1.0) > 0.01, "the body move must actually change the expected aim (dot=%.5f)" % want_after.dot(want_before))
	var actual: Vector2 = _port().get_facing()
	_check(_angle_error_degrees(actual, want_after) <= 1.0, "stationary cursor must track the body (actual=%s expected=%s error=%.5f deg)" % [actual, want_after, _angle_error_degrees(actual, want_after)])
	await _teardown()

# --- R2 ------------------------------------------------------------------------------------

func _test_press_release_same_step() -> void:
	print("[test] R2 an accepted press moves the body on the very next physics step")
	await _load_player(Vector2(480, 270))

	## The engine applies an injected event at the start of the following frame. From the step
	## that first sees the press, the body must already move: no extra frame of lag behind the
	## input state. (A real device event arrives the same way, one frame before its first step.)
	_push_key(&"move_right", true)
	await _step()
	_check(Input.is_action_pressed(&"move_right"), "the press must be visible to the input state on the following frame")
	var before: Vector2 = _player.global_position
	await _step()
	var moved: float = _player.global_position.distance_to(before)
	_check(moved > 0.0, "the body must move on the first physics step that observes the press (moved=%.4f)" % moved)
	_check_close(moved, SPEED * STEP_SECONDS, 0.5, "the first pressed step must move a full step distance")

	## Holding keeps moving at exactly the commanded speed (10 steps at 90 px/s = 15 px; the bound
	## allows one extra applied step from injection granularity but still rejects a frozen state).
	await _steps(10)
	var held: float = _player.global_position.distance_to(before)
	var expected_hold := SPEED * 10.0 * STEP_SECONDS
	_check(held >= expected_hold - 0.5, "holding must keep moving the body (moved=%.2f, expected ~%.2f)" % [held, expected_hold])
	_check(held <= expected_hold + 1.6, "holding must not outrun the commanded speed (moved=%.2f, expected ~%.2f)" % [held, expected_hold])
	_push_key(&"move_right", false)
	await _step()
	_check(not Input.is_action_pressed(&"move_right"), "the release must be visible to the input state on the following frame")
	var released_at: Vector2 = _player.global_position
	await _step()
	var drift: float = _player.global_position.distance_to(released_at)
	_check_close(drift, 0.0, 0.0001, "no physics step after the release may move the body")
	_check_close(_player.velocity.length(), 0.0, 0.0001, "velocity must be zero once released")
	await _teardown()

func _test_action_edge_consumed_once() -> void:
	print("[test] R2 action edges are consumed once, inside the physics step")
	await _load_player_with_recorder(Vector2(480, 270))
	var recorder := _recorder
	_check(recorder != null, "recording port must be installed")
	if recorder == null:
		await _teardown()
		return
	_check(recorder.received_actions.is_empty(), "no action may be submitted before any press")

	## The edge must be queued by the input handler and delivered by the physics step that
	## follows, exactly once. parse_input_event dispatches on the next frame, so push and then
	## observe the step.
	_push_key(&"dodge", true)
	await _step()
	_check(recorder.received_actions.is_empty(), "the edge must not be submitted before the step that observes it")
	await _step()
	_check(recorder.received_actions.size() == 1, "the press must reach the port once in the step that observes it (got %d)" % recorder.received_actions.size())
	if recorder.received_actions.size() == 1:
		_check(recorder.received_actions[0] == ActorCommandPort.Action.DODGE, "the submitted action must be DODGE")
	_check(recorder.intent_count > 0, "the adapter must submit intent through the same component")

	await _release_key(&"dodge")
	await _steps(3)
	_check(recorder.received_actions.size() == 1, "a press must not be replayed on later steps (got %d)" % recorder.received_actions.size())
	await _teardown()

# --- R3 ------------------------------------------------------------------------------------

func _test_facing_arrow_gradient() -> void:
	print("[test] R3 facing arrow carries a real gradient")
	await _load_player(Vector2(480, 270))
	var arrow := _player.get_node("Visual/FacingArrow") as Line2D
	_check(arrow != null, "FacingArrow must exist")
	var gradient: Gradient = arrow.gradient
	_check(gradient != null, "Line2D.gradient must not be null")
	if gradient != null:
		_check(gradient.get_point_count() >= 2, "gradient must have at least two points")
		var start := gradient.get_color(0)
		var end := gradient.get_color(gradient.get_point_count() - 1)
		_check(absf(start.a - 1.0) < 0.01, "gradient must start opaque")
		_check(end.a < 1.0, "gradient must fade out along the arrow")
		_check(start.r > 0.5 and start.g > 0.5 and start.b < 0.5, "gradient must be the configured yellow-green")
	await _teardown()
