class_name BeastController
extends CharacterBody2D
## A short-range beast: it closes in, then commits to a lunge that carries its body forward. The
## lunge is an Action.DASH attack whose spec carries a charge distance, so it obeys the same
## wind-up / damage-window / recovery commitment as every other attack instead of having its own
## movement rules.

const DECISION_INTERVAL := 0.07
const STUCK_EPSILON_PIXELS := 1.5
const ATTACK_RETRY_SECONDS := 0.25
const AVOID_ANGLE_DEGREES := 60.0
const AVOID_STEPS := 16

## What this enemy drops when killed.
## Experience granted to the player when this enemy dies.
@export var experience_reward: int = 20
@export var drop_table: DropTable
@export var command_port_path: NodePath
@export var combatant_path: NodePath
@export var target_path: NodePath

## Distance at which it commits to a lunge.
@export var lunge_range_pixels := 58.0
## Distance it tries to hold while waiting for the lunge to come up.
@export var standoff_pixels := 26.0
## Extra wait between lunges.
@export var lunge_cooldown_seconds := 0.55

var _command_port: ActorCommandPort
var _combatant: ActorCombatant

var _decision_timer := 0.0
var _lunge_timer := 0.0
var _move_axis := Vector2.ZERO
var _last_position := Vector2.ZERO
var _avoid_sign := 1.0
var _avoid_steps := 0
var spawn_position := Vector2.ZERO

func _ready() -> void:
	_command_port = get_node_or_null(command_port_path) as ActorCommandPort
	_combatant = get_node_or_null(combatant_path) as ActorCombatant
	spawn_position = global_position
	_last_position = global_position

func set_target_path(path: NodePath) -> void:
	target_path = path
	_last_position = global_position

func _physics_process(delta: float) -> void:
	if _command_port == null or _combatant == null:
		return
	_lunge_timer = maxf(0.0, _lunge_timer - delta)
	velocity = _command_port.get_velocity()
	move_and_slide()
	if not _combatant.is_alive():
		return
	## A lunge is committed once started; the beast cannot steer out of its own charge.
	if not ActionRules.allows_locomotion(_command_port.get_state()):
		return
	_decision_timer -= delta
	if _decision_timer > 0.0:
		return
	_decision_timer = DECISION_INTERVAL
	_decide()

func _decide() -> void:
	var target := get_node_or_null(target_path) as Node2D
	var target_combatant := _target_combatant()
	if target == null or target_combatant == null or not target_combatant.is_alive():
		_move_axis = Vector2.ZERO
		_command_port.set_intent(Vector2.ZERO, Vector2.ZERO, false)
		return

	var to_target := target.global_position - global_position
	var distance := to_target.length()
	var direction := to_target.normalized() if distance > 0.001 else Vector2.RIGHT

	if distance <= lunge_range_pixels and _lunge_timer <= 0.0:
		if _command_port.request_action(ActorCommandPort.Action.DASH):
			_lunge_timer = lunge_cooldown_seconds
			_move_axis = Vector2.ZERO
			_command_port.set_intent(Vector2.ZERO, direction, false)
			return
		_lunge_timer = ATTACK_RETRY_SECONDS

	## Circle at the edge of lunge range instead of standing still, so the approach reads as a
	## stalking animal rather than a turret waiting on cooldown.
	if distance <= standoff_pixels:
		_move_axis = Vector2.ZERO
		_command_port.set_intent(Vector2.ZERO, direction, false)
		return
	_move_axis = _steer(direction)
	_command_port.set_intent(_move_axis, direction, false)

func _steer(direction: Vector2) -> Vector2:
	var travelled := global_position.distance_to(_last_position)
	_last_position = global_position
	if _avoid_steps > 0:
		_avoid_steps -= 1
		return direction.rotated(deg_to_rad(_avoid_sign * AVOID_ANGLE_DEGREES))
	if travelled < STUCK_EPSILON_PIXELS and _command_port.get_state() == ActorCommandPort.State.MOVE:
		_avoid_steps = AVOID_STEPS
		_avoid_sign = -_avoid_sign
		return direction.rotated(deg_to_rad(_avoid_sign * AVOID_ANGLE_DEGREES))
	return direction

func _target_combatant() -> ActorCombatant:
	var target := get_node_or_null(target_path)
	if target == null:
		return null
	for child in target.get_children():
		if child is ActorCombatant:
			return child as ActorCombatant
	return null

func reset_for_retry() -> void:
	global_position = spawn_position
	velocity = Vector2.ZERO
	_move_axis = Vector2.ZERO
	_lunge_timer = 0.0
	_decision_timer = 0.0
	_avoid_steps = 0
	_last_position = global_position
	if _command_port is ActorActionPort:
		(_command_port as ActorActionPort).reset_state()
	if _combatant != null:
		_combatant.reset_vitals()

## Experience this enemy is worth to the player, read by the reward path.
func get_experience_reward() -> int:
	return experience_reward
