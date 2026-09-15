class_name PlayerController
extends CharacterBody2D
## Player body shell. Applies the port's commanded velocity to the body and renders the state the
## port reports. It owns no combat rules: health, stamina and hit resolution live in the
## ActorCombatant component, and action legality lives in the ActorCommandPort component.
##
## Step order inside one physics tick is enforced by process_physics_priority in player.tscn:
##   InputAdapter (-100): sample device -> set_intent / request_action
##   ActorActionPort (-50): advance the action state machine
##   ActorCombatant (-10): stamina regeneration
##   ActorHitbox (-5): apply the damage window to whoever is in reach
##   PlayerController (0): read port -> move_and_slide -> refresh visuals
## Both halves of the input path must live in _physics_process: _unhandled_input can run while the
## tree is paused or mid-frame, which would make input timing depend on the render frame rate.

const HIT_FLASH_SECONDS := 0.12
const BLOCK_TINT := Color(0.55, 0.75, 1.0)
const DEAD_TINT := Color(0.35, 0.35, 0.4)

@export var command_port_path: NodePath
@export var combatant_path: NodePath
@export var facing_arrow_path: NodePath
@export var camera_path: NodePath

var _command_port: ActorCommandPort
var _combatant: ActorCombatant
var _facing_arrow: Node2D
var _camera: Camera2D
var _body_visual: Polygon2D
var _knockback := Vector2.ZERO
var _base_color := Color.WHITE
var _flash_timer := 0.0
## Retry returns here instead of reloading the scene.
var spawn_position := Vector2.ZERO

## Headless tests and later cutscenes can drive the port directly instead of the device.
var test_intent_override := false
var test_intent_move := Vector2.ZERO
var test_intent_aim := Vector2.ZERO
var test_intent_block := false

func _ready() -> void:
	_command_port = get_node_or_null(command_port_path) as ActorCommandPort
	_combatant = get_node_or_null(combatant_path) as ActorCombatant
	_facing_arrow = get_node_or_null(facing_arrow_path) as Node2D
	_camera = get_node_or_null(camera_path) as Camera2D
	_body_visual = get_node_or_null("Visual/Body") as Polygon2D
	if _body_visual != null:
		_base_color = _body_visual.color
	if _command_port == null:
		push_error("PlayerController: command_port_path must point at an ActorCommandPort")
	if _camera != null:
		_camera.make_current()
	if _combatant != null:
		_combatant.hurt.connect(_on_hurt)
		_combatant.blocked.connect(_on_blocked)
		_combatant.knockback_applied.connect(_on_knockback)
	spawn_position = global_position

func _physics_process(delta: float) -> void:
	if _command_port == null:
		velocity = Vector2.ZERO
		return
	if test_intent_override:
		_command_port.set_intent(test_intent_move, test_intent_aim, test_intent_block)
	## Knockback rides on top of the commanded velocity, so a hit shoves the body without letting
	## the actor steer during the shove.
	_knockback = ActorMovement.decayed_knockback(_knockback, delta, _damping())
	velocity = _command_port.get_velocity() + _knockback
	move_and_slide()
	_update_facing_visual()
	_update_state_visual(delta)

## Retry: back to the spawn point, full vitals, no leftover impulse or flash.
func reset_for_retry() -> void:
	global_position = spawn_position
	velocity = Vector2.ZERO
	_knockback = Vector2.ZERO
	_flash_timer = 0.0
	if _body_visual != null:
		_body_visual.color = _base_color
	if _command_port is ActorActionPort:
		(_command_port as ActorActionPort).reset_state()
	if _combatant != null:
		_combatant.reset_vitals()

func _damping() -> float:
	if _combatant != null and _combatant.tuning != null:
		return _combatant.tuning.knockback_damping
	return 12.0

## Downstream code reads facing from the port; the arrow is presentation only.
func _update_facing_visual() -> void:
	if _facing_arrow == null:
		return
	var facing: Vector2 = _command_port.get_facing()
	if facing.is_zero_approx():
		return
	_facing_arrow.rotation = facing.angle()

## Placeholder feedback until T06 art: colour states what geometry cannot yet communicate.
func _update_state_visual(delta: float) -> void:
	if _body_visual == null:
		return
	if _flash_timer > 0.0:
		_flash_timer = maxf(0.0, _flash_timer - delta)
		if _flash_timer > 0.0:
			_body_visual.color = Color.WHITE
			return
	var state := _command_port.get_state()
	if state == ActorCommandPort.State.BLOCK:
		_body_visual.color = BLOCK_TINT
	elif state == ActorCommandPort.State.DEAD:
		_body_visual.color = DEAD_TINT
	else:
		_body_visual.color = _base_color

func _on_hurt(_damage: float, _origin: Vector2) -> void:
	_flash_timer = HIT_FLASH_SECONDS

func _on_blocked(_origin: Vector2) -> void:
	_flash_timer = HIT_FLASH_SECONDS * 0.5

func _on_knockback(impulse: Vector2) -> void:
	_knockback = impulse
