class_name BanditController
extends CharacterBody2D
## A single melee bandit. It only ever acts through its ActorCommandPort: it sets an intent and
## requests actions, exactly like the player input adapter. It never touches the player's health
## or any other actor's state directly - damage only happens when the shared hitbox hands a
## DamageEvent to the target's CombatantPort.
##
## Requirement: approach, show a readable wind-up, attack, recover.

const DECISION_INTERVAL := 0.08
const STUCK_EPSILON_PIXELS := 1.5
## Back-off after a refused attack so a blocked/starved actor does not retry every decision tick.
const ATTACK_RETRY_SECONDS := 0.25
## Obstacle sidestep: how far off the direct line, and how long before trying the direct line again.
const AVOID_ANGLE_DEGREES := 55.0
const AVOID_STEPS := 20

## What this enemy drops when killed.
## Experience granted to the player when this enemy dies.
@export var experience_reward: int = 20
@export var drop_table: DropTable
@export var command_port_path: NodePath
@export var combatant_path: NodePath
@export var weapon_path: NodePath
@export var target_path: NodePath

## Extra distance kept between bodies, on top of the two hurtbox radii.
@export var keep_distance_pixels := 16.0
## Seconds before another attack may start after the previous one finished.
@export var attack_cooldown_seconds := 0.9

var _command_port: ActorCommandPort
var _combatant: ActorCombatant
var _weapon: Node2D
var _target_path: NodePath

var _decision_timer := 0.0
var _attack_timer := 0.0
var _move_axis := Vector2.ZERO
var _last_position := Vector2.ZERO
var _avoid_sign := 1.0
var _avoid_steps := 0
var spawn_position := Vector2.ZERO

func _ready() -> void:
	_configure()
	spawn_position = global_position
	_last_position = global_position

func set_target_path(path: NodePath) -> void:
	_target_path = path
	_configure()

func _configure() -> void:
	_command_port = get_node_or_null(command_port_path) as ActorCommandPort
	_combatant = get_node_or_null(combatant_path) as ActorCombatant
	_weapon = get_node_or_null(weapon_path) as Node2D
	_last_position = global_position

func _physics_process(delta: float) -> void:
	if _command_port == null or _combatant == null:
		return
	_attack_timer = maxf(0.0, _attack_timer - delta)
	_update_weapon_visual()
	## Apply the last intent to the body: without this the AI would only ever set intent and
	## stand still. Both the AI and the player shell drive the same port contract.
	velocity = _command_port.get_velocity()
	move_and_slide()
	if not _combatant.is_alive():
		return
	## While an action is running there is nothing to decide: the port owns the actor until the
	## action finishes, which is what stops the AI from cancelling its own wind-up.
	if not ActionRules.allows_locomotion(_command_port.get_state()):
		return
	_decision_timer -= delta
	if _decision_timer > 0.0:
		return
	_decision_timer = DECISION_INTERVAL
	_decide()

func _decide() -> void:
	var target := get_node_or_null(_target_path) as Node2D
	var target_port := _target_combatant()
	if target == null or target_port == null or not target_port.is_alive():
		_move_axis = Vector2.ZERO
		_command_port.set_intent(Vector2.ZERO, Vector2.ZERO, false)
		return

	var to_target := target.global_position - global_position
	var distance := to_target.length()
	var direction := to_target.normalized() if distance > 0.001 else Vector2.RIGHT

	## Attack only when in reach and off cooldown, so a refused request is never spammed every
	## decision tick; the port stays the single authority on whether the action actually starts.
	if distance <= _attack_reach() and _attack_timer <= 0.0:
		if _command_port.request_action(ActorCommandPort.Action.LIGHT_ATTACK):
			_attack_timer = attack_cooldown_seconds
			_move_axis = Vector2.ZERO
			return
		_attack_timer = ATTACK_RETRY_SECONDS

	## In melee reach: hold still and keep facing the player so the next swing is telegraphed.
	if distance <= _desired_distance():
		_move_axis = Vector2.ZERO
		_command_port.set_intent(Vector2.ZERO, direction, false)
		return

	_move_axis = _steer(direction)
	_command_port.set_intent(_move_axis, direction, false)

func _desired_distance() -> float:
	return keep_distance_pixels

## How far the bandit will commit to a swing. Slightly beyond the keep-distance so it does not
## spend the whole fight walking into the player.
func _attack_reach() -> float:
	return keep_distance_pixels + 8.0

## Walks toward the player, sidestepping for a moment when an obstacle stops progress. The detour
## is bounded: once it expires the bandit tries the direct line again, so it cannot drift off
## course around a long obstacle forever.
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
	var target := get_node_or_null(_target_path)
	if target == null:
		return null
	for child in target.get_children():
		if child is ActorCombatant:
			return child as ActorCombatant
	return null

## Placeholder wind-up readability: the weapon pulls back, then thrusts while damage is live.
func _update_weapon_visual() -> void:
	if _weapon == null:
		return
	var spec: AttackSpec = _command_port.get_active_attack()
	var state := _command_port.get_state()
	var reach := 22.0
	var lift := 0.0
	match state:
		ActorCommandPort.State.WINDUP:
			var windup: float = spec.windup_seconds if spec != null else 0.2
			var progress := clampf(_command_port.get_state_elapsed() / maxf(windup, 0.001), 0.0, 1.0)
			reach = lerpf(14.0, 8.0, progress)
			lift = -6.0 * progress
		ActorCommandPort.State.ACTIVE:
			reach = 30.0
		ActorCommandPort.State.RECOVERY:
			reach = 18.0
		ActorCommandPort.State.STAGGER:
			reach = 10.0
		ActorCommandPort.State.DEAD:
			reach = 6.0
		_:
			reach = 20.0
	_weapon.rotation = _command_port.get_facing().angle()
	_weapon.position = Vector2(reach * 0.5, lift)
	if _weapon is Line2D:
		(_weapon as Line2D).points = PackedVector2Array([Vector2(-reach * 0.5, 0), Vector2(reach * 0.5, 0)])

## Retry: back to the spawn point with full vitals and no pending action.
func reset_for_retry() -> void:
	global_position = spawn_position
	velocity = Vector2.ZERO
	_move_axis = Vector2.ZERO
	_attack_timer = 0.0
	_decision_timer = 0.0
	_avoid_steps = 0
	_last_position = global_position
	if _command_port is ActorActionPort:
		(_command_port as ActorActionPort).reset_state()
	if _combatant != null:
		_combatant.reset_vitals()
	if _weapon != null:
		_weapon.rotation = 0.0
		_weapon.position = Vector2.ZERO

## Experience this enemy is worth to the player, read by the reward path.
func get_experience_reward() -> int:
	return experience_reward
