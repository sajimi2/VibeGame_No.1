extends Node
## T01 window-scaling acceptance test. This is the only T01 check that needs a real window:
## a headless window is 0x0, so DisplayServer.window_set_size cannot change anything there.
##
## Run it with a real window:
##   godot --path <project> --windowed res://tests/stretch_probe.tscn
## Exit code 0 means the body moved at the design speed at every window size; 1 otherwise.
##
## The body is driven through the real input path: the adapter samples the InputMap state that
## Input.parse_input_event produces, and only the ordering is fenced (both nodes' own
## _physics_process are disabled so this scene can advance exactly one step per frame).

const COMMANDED_SPEED := 90.0
const FRAMES_PER_PHASE := 60
const STEP_SECONDS := 1.0 / 60.0
const TOLERANCE := 0.5
const MOVE_KEY := KEY_D
const SIZES: Array[Vector2i] = [
	Vector2i(640, 360),
	Vector2i(160, 90),
	Vector2i(1280, 720),
	Vector2i(1920, 1080),
	Vector2i(1280, 720),
]
## Open floor on the left of the arena, clear of walls and blocks for 90 px of travel.
const RUN_FROM := Vector2(150, 60)

var _player: CharacterBody2D
var _adapter: Node
var _phase_index := 0
var _frames_in_phase := 0
var _elapsed := 0.0
var _phase_start := Vector2.ZERO
var _results: Array[String] = []
var _measured: Array[float] = []
var _log: FileAccess

func _ready() -> void:
	_log = FileAccess.open("res://work/stretch_probe.log", FileAccess.WRITE)
	_player = get_node("Arena/Player") as CharacterBody2D
	_adapter = get_node("Arena/Player/InputAdapter")
	_player.set_physics_process(false)
	_adapter.set_physics_process(false)
	_emit("viewport is fixed at %s while the window changes" % [get_viewport().get_visible_rect().size])
	## Hold the move key down through the real input pipeline for the whole run.
	Input.parse_input_event(_key_event(true))
	await get_tree().physics_frame
	_check_input_active()
	_apply_phase()

func _key_event(pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = MOVE_KEY
	event.keycode = MOVE_KEY
	event.pressed = pressed
	return event

func _check_input_active() -> void:
	if not Input.is_action_pressed(&"move_right"):
		_emit("RESULT: FAIL the injected move key did not reach the input state")
		if _log != null:
			_log.close()
		get_tree().quit(1)

func _emit(line: String) -> void:
	print("STRETCH %s" % line)
	if _log != null:
		_log.store_line(line)
		_log.flush()

func _window_scale() -> Vector2:
	var visible := get_viewport().get_visible_rect().size
	var window := Vector2(DisplayServer.window_get_size())
	if visible.x <= 0.0 or visible.y <= 0.0:
		return Vector2.ZERO
	return window / visible

func _apply_phase() -> void:
	DisplayServer.window_set_size(SIZES[_phase_index])
	_player.global_position = RUN_FROM
	_player.velocity = Vector2.ZERO
	_phase_start = RUN_FROM
	_frames_in_phase = 0
	_elapsed = 0.0
	_emit("requested window %s -> actual %s, viewport->window scale %s" % [
		SIZES[_phase_index], DisplayServer.window_get_size(), _window_scale()])

func _physics_process(delta: float) -> void:
	## Real adapter samples the device, then the production controller moves the body.
	_adapter._physics_process(delta)
	_player._physics_process(delta)
	_frames_in_phase += 1
	_elapsed += delta
	if _frames_in_phase < FRAMES_PER_PHASE:
		return
	var travelled := _player.global_position.distance_to(_phase_start)
	var speed := travelled / _elapsed
	_measured.append(speed)
	_results.append("window %s scale %s: travelled %.3f px in %d steps / %.4f s = %.3f px/s" % [
		DisplayServer.window_get_size(), _window_scale(), travelled, FRAMES_PER_PHASE, _elapsed, speed])
	_emit(_results[_results.size() - 1])
	_phase_index += 1
	if _phase_index < SIZES.size():
		_apply_phase()
		return
	_finish()

func _finish() -> void:
	Input.parse_input_event(_key_event(false))
	var failures: Array[String] = []
	for index in _measured.size():
		if absf(_measured[index] - COMMANDED_SPEED) > TOLERANCE:
			failures.append("%s -> %.3f px/s, expected %.3f +-%.1f" % [SIZES[index], _measured[index], COMMANDED_SPEED, TOLERANCE])
	var lowest: float = _measured.min()
	var highest: float = _measured.max()
	if highest - lowest > TOLERANCE:
		failures.append("speed varies with window size: spread %.3f px/s" % (highest - lowest))
	if failures.is_empty():
		_emit("RESULT: PASS at every window size, %.3f px/s (commanded %.3f)" % [lowest, COMMANDED_SPEED])
	else:
		for failure in failures:
			_emit("RESULT: FAIL %s" % failure)
	if _log != null:
		_log.close()
	get_tree().quit(0 if failures.is_empty() else 1)
