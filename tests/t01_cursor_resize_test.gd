extends SceneTree
## T01 R1b regression: the aim must survive a window resize while the cursor stands still.
##
## The defect this pins down: a cursor position cached in viewport coordinates becomes wrong as
## soon as the window->viewport mapping changes, because the same physical cursor point then maps
## to a different viewport point. Measured before the fix: 3.11084 degrees after 1280x720 ->
## 960x540, growing with the size change.
##
## Everything here runs under normal physics scheduling: states are observed at physics_frame
## boundaries and nothing calls a node's _physics_process by hand.
##
## Window sizes are set on the root viewport, which is what the project's canvas_items stretch
## maps through, so this also runs headless. Injected input uses Viewport.push_input with
## in_local_coords = false, i.e. window coordinates put through the real stretch transform.
##
## Runnable with:
##   godot --headless --path <project> --script res://tests/t01_cursor_resize_test.gd
## Exits 0 when every case passes, 1 otherwise.

const PLAYER_SCENE := "res://scenes/player.tscn"
const ANGLE_TOLERANCE_DEGREES := 1.0
const START_SIZE := Vector2i(1280, 720)
const SMALLER_SIZE := Vector2i(960, 540)
const LARGER_SIZE := Vector2i(1600, 900)
const VIEWPORT_SIZE := Vector2(640, 360)
## A window point well inside every tested window and away from the body's straight axes.
const CURSOR_WINDOW_POINT := Vector2(700, 400)

var _failures: Array[String] = []
var _checks := 0
var _player: Node = null
## True when changing the window size really rescales the window->viewport mapping. A headless
## window is 0x0, so the mapping is degenerate and identical at every requested size: the resize
## cases cannot be exercised there and say so instead of passing vacuously.
var _window_rescales_viewport := false

func _initialize() -> void:
	_run()

func _run() -> void:
	print("=== T01 cursor/window-resize tests ===")
	await physics_frame
	await _probe_window_rescales_viewport()
	await _test_resize_smaller_keeps_aim()
	await _test_resize_larger_keeps_aim()
	await _test_round_trip_returns_to_original()
	await _test_first_click_establishes_aim()
	if not _window_rescales_viewport:
		print("T01_CURSOR_RESIZE_TESTS: SKIPPED resize cases — this window does not rescale the")
		print("  viewport mapping (headless reports 0x0), so a resize cannot change the expected")
		print("  aim. Run the same script with a real window to exercise them:")
		print("  godot --path <project> --windowed --script res://tests/t01_cursor_resize_test.gd")
	print("--- checks=%d failures=%d" % [_checks, _failures.size()])
	if _failures.is_empty():
		print("T01_CURSOR_RESIZE_TESTS: PASS")
		quit(0)
	else:
		for failure in _failures:
			print("T01_CURSOR_RESIZE_TESTS: FAIL %s" % failure)
		quit(1)

## Measures whether the window size actually changes the window->viewport scale.
func _probe_window_rescales_viewport() -> void:
	var window_size := DisplayServer.window_get_size()
	root.size = START_SIZE
	await _steps(2)
	var small_scale := root.get_stretch_transform().get_scale()
	root.size = SMALLER_SIZE
	await _steps(2)
	var other_scale := root.get_stretch_transform().get_scale()
	_window_rescales_viewport = small_scale.distance_to(other_scale) > 0.001
	print("  window=%s viewport=%s | stretch scale at %s: %s, at %s: %s -> resize %s" % [
		window_size, root.get_visible_rect().size, START_SIZE, small_scale, SMALLER_SIZE, other_scale,
		"is exercised" if _window_rescales_viewport else "cannot be exercised in this window"])

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

## Independent expectation: the engine's own window->viewport transform, then the camera's canvas
## transform. Deliberately does not consult any adapter state.
func _expected_facing(body: Node2D) -> Vector2:
	var viewport_point: Vector2 = root.get_stretch_transform().affine_inverse() * CURSOR_WINDOW_POINT
	var world_point: Vector2 = root.get_canvas_transform().affine_inverse() * viewport_point
	return (world_point - body.global_position).normalized()

func _facing() -> Vector2:
	return _player.get_node("ActorActionPort").get_facing()

func _angle_error_degrees(actual: Vector2, expected: Vector2) -> float:
	return absf(rad_to_deg(actual.angle_to(expected)))

## Injects a cursor sample in window coordinates, exactly once per test case.
func _inject_cursor_once() -> void:
	var event := InputEventMouseMotion.new()
	event.position = CURSOR_WINDOW_POINT
	root.push_input(event, false)
	await _steps(2)

func _load_player() -> void:
	await _teardown()
	_player = (load(PLAYER_SCENE) as PackedScene).instantiate()
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
	await physics_frame

# --- cases ---------------------------------------------------------------------------------

func _test_resize_smaller_keeps_aim() -> void:
	print("[test] cursor stands still while the window shrinks")
	await _load_player()
	await _set_window(START_SIZE)
	await _inject_cursor_once()
	var want_before := _expected_facing(_player)
	_check(_angle_error_degrees(_facing(), want_before) <= ANGLE_TOLERANCE_DEGREES, "aim must match before the resize (error=%.5f deg)" % _angle_error_degrees(_facing(), want_before))

	## Only the window changes; no further mouse event is sent. 1280x720 -> 960x540 moves the
	## expected aim by about 3.1 degrees, so require a change clearly above the 1 degree tolerance.
	await _set_window(SMALLER_SIZE)
	var want_after := _expected_facing(_player)
	if _window_rescales_viewport:
		_check(absf(want_after.dot(want_before) - 1.0) > 0.0005, "the resize must actually change the expected aim (dot=%.6f)" % want_after.dot(want_before))
	var error := _angle_error_degrees(_facing(), want_after)
	_check(error <= ANGLE_TOLERANCE_DEGREES, "stationary cursor must follow the resized window (actual=%s expected=%s error=%.5f deg)" % [_facing(), want_after, error])
	await _teardown()

func _test_resize_larger_keeps_aim() -> void:
	print("[test] cursor stands still while the window grows")
	await _load_player()
	await _set_window(START_SIZE)
	await _inject_cursor_once()
	await _set_window(LARGER_SIZE)
	var want := _expected_facing(_player)
	var error := _angle_error_degrees(_facing(), want)
	_check(error <= ANGLE_TOLERANCE_DEGREES, "stationary cursor must follow an enlarged window (actual=%s expected=%s error=%.5f deg)" % [_facing(), want, error])
	await _teardown()

func _test_round_trip_returns_to_original() -> void:
	print("[test] resize away and back returns to the original aim")
	await _load_player()
	await _set_window(START_SIZE)
	await _inject_cursor_once()
	var want_start := _expected_facing(_player)
	await _set_window(SMALLER_SIZE)
	await _set_window(START_SIZE)
	var want_back := _expected_facing(_player)
	_check(want_back.distance_to(want_start) < 0.0001, "returning to the original size must restore the original expected aim")
	var error := _angle_error_degrees(_facing(), want_back)
	_check(error <= ANGLE_TOLERANCE_DEGREES, "aim must return to its original value (actual=%s expected=%s error=%.5f deg)" % [_facing(), want_back, error])
	await _teardown()

func _test_first_click_establishes_aim() -> void:
	print("[test] a click before any mouse motion still establishes the aim")
	await _load_player()
	await _set_window(START_SIZE)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = CURSOR_WINDOW_POINT
	root.push_input(click, false)
	await _steps(2)
	var want := _expected_facing(_player)
	var error := _angle_error_degrees(_facing(), want)
	_check(error <= ANGLE_TOLERANCE_DEGREES, "a press carries the cursor position (actual=%s expected=%s error=%.5f deg)" % [_facing(), want, error])
	await _teardown()
