class_name PlayerInputAdapter
extends Node
## Only place in the project allowed to poll Input. Runs as the FIRST step of each physics
## tick (see process_physics_priority in player.tscn): sample input -> submit intent/actions
## -> the body's own _physics_process moves it -> the controller refreshes visuals.
## Sampling later than the body step would delay every input by one physics frame.

const MOVE_ACTIONS: Dictionary = {
	&"move_up": Vector2.UP,
	&"move_down": Vector2.DOWN,
	&"move_left": Vector2.LEFT,
	&"move_right": Vector2.RIGHT,
}

const ACTION_BY_NAME: Dictionary = {
	&"attack_light": ActorCommandPort.Action.LIGHT_ATTACK,
	&"attack_heavy": ActorCommandPort.Action.HEAVY_ATTACK,
	&"dodge": ActorCommandPort.Action.DODGE,
}

@export var command_port_path: NodePath

var _command_port: ActorCommandPort
var _viewport: Viewport
## Action edge seen by _unhandled_input, consumed exactly once inside the next physics step.
var _queued_action: int = -1
## Latest cursor position, in viewport coordinates as of the moment it was sampled, plus the
## window->viewport scale in force at that moment. A raw viewport position cannot be cached
## across a window resize: the same physical cursor point maps to a different viewport point
## once the stretch changes (1280x720 -> 960x540 moves a cursor from viewport 350 to 466.67).
## Keeping the capture scale lets each physics step rescale it onto the current mapping, so a
## stationary cursor stays correct after a resize without waiting for a new motion event.
var _cursor_viewport := Vector2.ZERO
var _cursor_scale := Vector2.ONE
## False until a cursor sample arrives; a device that never delivered one must not invent a
## facing direction, so the adapter reports zero aim (the port then keeps its default).
var _has_cursor := false

func _ready() -> void:
	_command_port = get_node_or_null(command_port_path) as ActorCommandPort
	if _command_port == null:
		push_error("PlayerInputAdapter: command_port_path must point at an ActorCommandPort")
	_viewport = get_viewport()

func _unhandled_input(event: InputEvent) -> void:
	if _command_port == null or event.is_echo():
		return
	_remember_cursor(event)
	if event is InputEventKey or event is InputEventMouseButton:
		for action_name in ACTION_BY_NAME:
			if event.is_action_pressed(action_name):
				## Edge-triggered, queued for the next physics step so press ordering matches the
				## physics timeline. A second press in the same step overwrites: no input buffering.
				_queued_action = ACTION_BY_NAME[action_name] as ActorCommandPort.Action

## Records the cursor from any mouse event that carries one. Clicks count: a press also states
## where the cursor is, and the first click of a session would otherwise leave the aim unusable
## until the mouse moved.
func _remember_cursor(event: InputEvent) -> void:
	var position := Vector2.ZERO
	if event is InputEventMouseMotion:
		position = (event as InputEventMouseMotion).position
	elif event is InputEventMouseButton:
		position = (event as InputEventMouseButton).position
	else:
		return
	## The engine hands this over in viewport coordinates: a real 1280x720 window reports at most
	## 640x360, and an injected event goes through the same window->viewport transform. The scale is
	## recorded together with the position because a sample is only valid as that pair; see the
	## focus handler below for why the two must never be updated separately.
	_cursor_viewport = position
	_cursor_scale = _current_window_scale()
	_has_cursor = true

## Focus loss invalidates a cached cursor sample: the window may have moved to another monitor,
## been rescaled, or simply no longer have the cursor over it. A sample is only valid as the
## POSITION + SCALE pair captured together, so this never rewrites one half of it -- doing that
## re-introduced a 3.11 degree aim error after a resize. Losing focus therefore drops the sample
## and any pending action edge; the first mouse motion or click after focus returns rebuilds both.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_has_cursor = false
		_queued_action = -1

func _physics_process(_delta: float) -> void:
	if _command_port == null:
		return
	_command_port.set_intent(_read_move_axis(), _read_aim_direction(), Input.is_action_pressed(&"block"))
	if _queued_action >= 0:
		var action := _queued_action as ActorCommandPort.Action
		_queued_action = -1
		_command_port.request_action(action)

func _read_move_axis() -> Vector2:
	var axis := Vector2.ZERO
	for action_name in MOVE_ACTIONS:
		if Input.is_action_pressed(action_name):
			axis += MOVE_ACTIONS[action_name] as Vector2
	return axis

## Cursor position -> world position -> unit direction from the body, recomputed every physics
## step. Both the window->viewport rescale and the canvas transform are read fresh each step, so
## the aim stays correct while the cursor stands still and any of these change: the camera moves,
## the body moves, or the window is resized.
func _read_aim_direction() -> Vector2:
	var body := _command_port.get_parent() as Node2D
	if body == null:
		return Vector2.ZERO
	if _viewport == null:
		_viewport = body.get_viewport()
		if _viewport == null:
			return Vector2.ZERO
	if not _has_cursor:
		return Vector2.ZERO
	var viewport_position := _rescale_cursor_to_current_window()
	var world_position := _viewport.get_canvas_transform().affine_inverse() * viewport_position
	var offset := world_position - body.global_position
	if offset.length() <= ActorMovement.MIN_AXIS_LENGTH:
		return Vector2.ZERO
	return offset.normalized()

## Re-expresses the sampled cursor on the window mapping in force right now. Without a resize
## this is the identity; after a resize it moves the cursor to the viewport point that the same
## physical position now maps to. Physical position = viewport * scale, so converting back to a
## viewport point means multiplying by capture_scale / current_scale.
func _rescale_cursor_to_current_window() -> Vector2:
	var current := _current_window_scale()
	if absf(current.x) <= 0.0001 or absf(current.y) <= 0.0001:
		return _cursor_viewport
	return _cursor_viewport * (_cursor_scale / current)

## Viewport-to-window scale of the root viewport. A headless 0x0 window reports a degenerate
## transform, in which case the sampled position is used as-is (that is how injected test input
## and the project's fixed 640x360 viewport behave).
func _current_window_scale() -> Vector2:
	if _viewport == null:
		return Vector2.ONE
	var scale := _viewport.get_screen_transform().get_scale()
	if absf(scale.x) <= 0.0001 or absf(scale.y) <= 0.0001:
		return Vector2.ONE
	return scale
