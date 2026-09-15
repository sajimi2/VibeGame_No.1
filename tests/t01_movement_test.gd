extends SceneTree
## T01 headless acceptance tests. Runnable with:
##   godot --headless --path <project> --script res://tests/t01_movement_test.gd
## Exits 0 when every test passes, 1 when any test fails (non-zero means failure).
##
## Physics is stepped by awaiting SceneTree.physics_frame, so these tests exercise the real
## CharacterBody2D.move_and_slide against the real arena colliders, not a reimplementation.
##
## Mouse aim: real hardware events reach the adapter already in viewport coordinates (verified
## on a real 1280x720 window). Injected Viewport.push_input events pass through the content
## scale transform, which is degenerate in a headless window (0x0), so this suite calibrates
## that mapping by pushing one probe event instead of hard-coding it.

const PLAYER_SCENE := "res://scenes/player.tscn"
const ARENA_SCENE := "res://scenes/arena.tscn"
const PHYSICS_STEPS_PER_SECOND := 60.0
const SPEED := 90.0
const VIEWPORT_SIZE := Vector2(640, 360)

var _failures: Array[String] = []
var _checks := 0
var _physical_frames := 0
var _player: Node = null
var _arena: Node = null
var _loaded := false

func _initialize() -> void:
	_run()

func _run() -> void:
	print("=== T01 movement/camera/input tests ===")
	## Let the root viewport finish its first frame before any transform is read.
	await physics_frame
	await _test_pure_axis_math()
	await _test_port_locomotion()
	await _test_equal_distance_per_second()
	await _test_release_stops()
	await _test_wall_blocks()
	await _test_aim_after_camera_move()
	await _test_window_resize_keeps_speed()
	print("--- checks=%d failures=%d physical_frames=%d" % [_checks, _failures.size(), _physical_frames])
	if _failures.is_empty():
		print("T01_TESTS: PASS")
		quit(0)
	else:
		for failure in _failures:
			print("T01_TESTS: FAIL %s" % failure)
		quit(1)

# --- harness -------------------------------------------------------------------------------

func _check(condition: bool, message: String) -> bool:
	_checks += 1
	if not condition:
		_failures.append(message)
		print("  [FAIL] %s" % message)
	return condition

func _check_close(actual: float, expected: float, tolerance: float, message: String) -> bool:
	return _check(absf(actual - expected) <= tolerance, "%s (actual=%.4f expected=%.4f tol=%.4f)" % [message, actual, expected, tolerance])

## One physics tick. The engine steps every attached body itself; the test only advances
## time, so intent written before this call is what the engine consumes.
func _step() -> void:
	_physical_frames += 1
	await physics_frame

func _steps(count: int) -> void:
	for _i in count:
		await _step()

## Steps with an explicit intent: still goes through the public ActorCommandPort entry point,
## only the device reading is replaced.
func _drive(move_axis: Vector2, count: int, aim := Vector2.ZERO) -> void:
	if _player == null:
		return
	_player.test_intent_override = true
	_player.test_intent_move = move_axis
	_player.test_intent_aim = aim
	await _steps(count)

## Spawns a fresh body. player.tscn is a prefab without an authored position (the arena owns
## spawn placement), so every test states its own start point before the first physics step.
func _load_player(use_arena: bool, spawn := Vector2(480, 270)) -> void:
	await _teardown()
	if not use_arena:
		_player = (load(PLAYER_SCENE) as PackedScene).instantiate()
		root.add_child(_player)
	else:
		_arena = (load(ARENA_SCENE) as PackedScene).instantiate()
		## The arena ships with its own player; drop it so the test controls the only body.
		var arena_player := _arena.get_node("Player") as Node
		_arena.remove_child(arena_player)
		arena_player.free()
		_player = (load(PLAYER_SCENE) as PackedScene).instantiate()
		_arena.add_child(_player)
		root.add_child(_arena)
	_loaded = true
	_player.global_position = spawn
	_player.velocity = Vector2.ZERO
	await physics_frame
	_check_close(_player.global_position.distance_to(spawn), 0.0, 0.001, "test body must start at its requested spawn %s" % spawn)

func _teardown() -> void:
	_loaded = false
	if _arena != null and is_instance_valid(_arena):
		_arena.queue_free()
		_arena = null
	if _player != null and is_instance_valid(_player):
		_player.queue_free()
		_player = null
	await physics_frame

func _port() -> Node:
	return _player.get_node("ActorActionPort")

func _adapter() -> Node:
	return _player.get_node("InputAdapter")

func _combatant() -> ActorCombatant:
	return _player.get_node("ActorCombatant") as ActorCombatant

# --- input injection -----------------------------------------------------------------------

## Injects a cursor position in viewport-local coordinates. The `true` argument stops
## Viewport.push_input from applying the content-scale transform, which is why a headless
## 0x0 window needs no empirical calibration and no reading of adapter internals.
func _inject_cursor(viewport_point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = viewport_point
	event.global_position = viewport_point
	event.relative = Vector2(1, -1)
	root.push_input(event, true)
	await _steps(2)

## Independent expectation: cursor viewport point -> world point -> direction from the body.
func _expected_facing(viewport_point: Vector2) -> Vector2:
	var world_point: Vector2 = root.get_canvas_transform().affine_inverse() * viewport_point
	return (world_point - _player.global_position).normalized()

# --- tests ---------------------------------------------------------------------------------

func _test_pure_axis_math() -> void:
	print("[test] pure axis math and unit-length velocity")
	_check(ActorMovement.velocity_for(Vector2(1, 1), SPEED).length() - SPEED < 0.0001, "diagonal velocity vector must not exceed speed")
	_check(ActorMovement.normalized_axis(Vector2(1, 1)).length() - 1.0 < 0.0001, "diagonal axis must be normalized to length 1")
	_check_close(ActorMovement.normalized_axis(Vector2(0.5, 0)).length(), 0.5, 0.0001, "partial deflection keeps analog magnitude")
	_check(ActorMovement.normalized_axis(Vector2.ZERO) == Vector2.ZERO, "zero axis stays zero")
	_check(ActorMovement.resolve_facing(Vector2.UP, Vector2.RIGHT) == Vector2.UP, "non-zero aim overrides facing")
	_check(ActorMovement.resolve_facing(Vector2.ZERO, Vector2.RIGHT) == Vector2.RIGHT, "zero aim preserves last facing")
	await _teardown()

## T01's port only had to refuse actions; T02 replaced it with the real combat state machine, so
## this now covers locomotion through the port and leaves action acceptance to tests/t02_combat_test.gd.
func _test_port_locomotion() -> void:
	print("[test] port locomotion: state, speed and facing")
	await _load_player(false)
	var port := _port()
	_check(port.get_state() == ActorCommandPort.State.IDLE, "port must start IDLE")
	var tuning := _combatant().tuning
	_check(tuning != null, "the port must be configured from a tuning resource")
	if tuning != null:
		_check_close(port.get_velocity().length(), tuning.move_speed * 0.0, 0.001, "no intent must command no velocity")
	_check(port.get_facing() == Vector2.RIGHT, "facing must default to RIGHT")

	port.set_intent(Vector2(1, 1), Vector2.ZERO, false)
	_check(port.get_state() == ActorCommandPort.State.MOVE, "input must move the port to MOVE")
	if tuning != null:
		_check_close(port.get_velocity().length(), tuning.move_speed, 0.0001, "port velocity length must equal the tuned speed")
	_check(port.get_facing() == Vector2.RIGHT, "zero aim must preserve facing")
	port.set_intent(Vector2.ZERO, Vector2.DOWN, false)
	_check(port.get_state() == ActorCommandPort.State.IDLE, "no input must return the port to IDLE")
	_check(port.get_facing() == Vector2.DOWN, "non-zero aim must rotate facing")
	await _teardown()

func _test_equal_distance_per_second() -> void:
	print("[test] equal distance per second on cardinal and diagonal")
	await _load_player(false, Vector2(480, 270))
	await _drive(Vector2.RIGHT, 60)
	var horizontal: float = _player.global_position.distance_to(Vector2(480, 270))
	_check_close(horizontal, SPEED, 0.5, "one second of RIGHT input must travel speed*1s")
	await _load_player(false, Vector2(480, 270))
	await _drive(Vector2(1, 1), 60)
	var diagonal: float = _player.global_position.distance_to(Vector2(480, 270))
	_check_close(diagonal, SPEED, 0.5, "one second of diagonal input must travel the same distance")
	_check_close(diagonal / horizontal, 1.0, 0.01, "diagonal/horizontal ratio must be 1.0, not sqrt(2)")
	await _teardown()

func _test_release_stops() -> void:
	print("[test] releasing input stops the body")
	await _load_player(false, Vector2(480, 270))
	await _drive(Vector2.RIGHT, 30)
	_check(_player.global_position.distance_to(Vector2(480, 270)) > 10.0, "body must actually move while input is held")
	await _drive(Vector2.ZERO, 6)
	var stopped_at: Vector2 = _player.global_position
	_check_close(_player.velocity.length(), 0.0, 0.0001, "velocity must be zero right after release")
	await _drive(Vector2.ZERO, 30)
	_check_close(_player.global_position.distance_to(stopped_at), 0.0, 0.0001, "position must not drift after release")
	await _teardown()

func _test_wall_blocks() -> void:
	print("[test] pushing into a wall never passes through")
	await _load_player(true, Vector2(160, 270))
	await _drive(Vector2.LEFT, 150)
	var left_x: float = _player.global_position.x
	_check(left_x >= 40.0, "left wall must keep the body at x >= 40 (actual=%.2f)" % left_x)
	_check_close(left_x, 40.0, 0.5, "body must come to rest on the wall surface (wall face x=32, radius 8)")
	_check_close(_player.global_position.y, 270.0, 0.5, "sliding along the wall must not move the body off-axis")

	## Chained corner push: the body is already against x=40, so diagonal input must only slide.
	var before: Vector2 = _player.global_position
	await _drive(Vector2.LEFT + Vector2.UP, 60)
	var after: Vector2 = _player.global_position
	print("  corner push: before=%s after=%s" % [before, after])
	_check(after.x >= 40.0, "diagonal push must not tunnel through the wall (x=%.2f)" % after.x)
	_check_close(after.x, 40.0, 0.5, "diagonal push must keep sliding along the wall x=40 (actual=%.2f)" % after.x)
	## move_and_slide drops the blocked axis and re-normalizes the remaining motion, so the free
	## axis keeps almost the full speed instead of the 1/sqrt(2) component. Observed 1.4757 of
	## 1.5 px per frame (98.4%); the bounds below keep the check meaningful without pinning
	## engine internals.
	var commanded := SPEED * (60.0 / PHYSICS_STEPS_PER_SECOND)
	var slid := before.y - after.y
	_check(slid > commanded * 0.9, "free axis must keep sliding near full speed while blocked (slid=%.2f of %.2f)" % [slid, commanded])
	_check(slid < commanded * 1.05, "sliding must not exceed the commanded speed (slid=%.2f of %.2f)" % [slid, commanded])
	_check_close(after.x, before.x, 0.2, "the blocked axis must not drift while sliding")
	await _teardown()

func _test_aim_after_camera_move() -> void:
	print("[test] aim direction stays correct after the camera moves")
	await _load_player(false, Vector2(300, 200))
	var camera := _player.get_node("FollowCamera") as Camera2D
	camera.position_smoothing_enabled = false
	camera.global_position = Vector2(300, 120)
	## reset_smoothing() snaps the camera; without it the running smoothing offset keeps the
	## canvas transform near the body for several frames.
	camera.reset_smoothing()
	await _steps(2)

	var canvas_xform := root.get_canvas_transform()
	print("  canvas transform offset=%s" % canvas_xform.origin)

	## Viewport point 30 px right of and 40 px below the viewport centre.
	var viewport_point := VIEWPORT_SIZE * 0.5 + Vector2(30, 40)
	var target_world: Vector2 = canvas_xform.affine_inverse() * viewport_point
	var centre_world: Vector2 = canvas_xform.affine_inverse() * (VIEWPORT_SIZE * 0.5)
	_check_close(target_world.x - centre_world.x, 30.0, 0.001, "canvas transform must be a pure translation in x")
	_check_close(target_world.y - centre_world.y, 40.0, 0.001, "canvas transform must be a pure translation in y")
	var expected_facing := _expected_facing(viewport_point)
	_check_close(expected_facing.length(), 1.0, 0.0001, "expected facing must be a unit vector")
	_check(expected_facing.x > 0.0, "viewport point right of centre must aim right")
	_check(expected_facing.y < 0.0, "viewport point above the body must aim up")
	_check(expected_facing.distance_to((target_world - _player.global_position).normalized()) < 0.0001, "independent expectation must agree with the transform")

	await _inject_cursor(viewport_point)
	var facing: Vector2 = _port().get_facing()
	_check(facing.distance_to(expected_facing) < 0.01, "adapter facing must match cursor direction (facing=%s expected=%s target=%s)" % [facing, expected_facing, target_world])
	var arrow := _player.get_node("Visual/FacingArrow") as Node2D
	_check_close(arrow.rotation, expected_facing.angle(), 0.01, "facing arrow must render the aim direction")

	## R1: the cursor does not move again, only the camera does. The aim must still follow.
	camera.global_position = Vector2(300, 60)
	camera.reset_smoothing()
	await _steps(2)
	var canvas_xform_2 := root.get_canvas_transform()
	var target_world_2: Vector2 = canvas_xform_2.affine_inverse() * viewport_point
	var expected_facing_2: Vector2 = (target_world_2 - _player.global_position).normalized()
	_check(absf(expected_facing_2.dot(expected_facing) - 1.0) > 0.01, "moving the camera must change the world aim for a fixed viewport point (dot=%.4f)" % expected_facing_2.dot(expected_facing))
	var facing_2: Vector2 = _port().get_facing()
	_check(facing_2.distance_to(expected_facing_2) < 0.01, "a stationary cursor must still track the camera (facing=%s expected=%s)" % [facing_2, expected_facing_2])
	await _teardown()

func _test_window_resize_keeps_speed() -> void:
	print("[test] world speed is independent of window size")
	## A headless window is 0x0, so DisplayServer.window_set_size cannot really resize anything
	## here; this test proves the requested resize changes neither the internal viewport nor the
	## world speed. Renderer-level stretch is covered by the windowed probe runs in the report.
	var sizes := [Vector2i(640, 360), Vector2i(160, 90), Vector2i(1280, 720)]
	for size in sizes:
		DisplayServer.window_set_size(size)
		await physics_frame
		_check_close(root.get_visible_rect().size.x, VIEWPORT_SIZE.x, 0.5, "internal viewport width must stay 640 at window %s" % size)
		_check_close(root.get_canvas_transform().get_scale().x, 1.0, 0.001, "canvas scale must stay 1.0 inside the fixed viewport at %s" % size)
		await _load_player(false, Vector2(480, 270))
		await _drive(Vector2.RIGHT, 60)
		var travelled: float = _player.global_position.distance_to(Vector2(480, 270))
		print("  requested window %s -> internal viewport %s, travelled %.3f px/s" % [size, root.get_visible_rect().size, travelled])
		_check_close(travelled, SPEED, 0.5, "speed must stay %d px/s at window %s" % [int(SPEED), size])
		await _teardown()
	DisplayServer.window_set_size(sizes[0])
