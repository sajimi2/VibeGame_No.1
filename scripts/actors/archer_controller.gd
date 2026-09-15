class_name ArcherController
extends CharacterBody2D
## A ranged bandit archer. Two rules shape everything it does:
##   1. it only starts a shot when it can actually see the player (a wall in between means no shot
##      is fired at all - the spawner enforces this too, so cover works even if a shot was begun),
##   2. it keeps a stand-off distance: backs off when crowded, closes in when too far.
## Like every other actor it acts only through its ActorCommandPort and never touches health.

const DECISION_INTERVAL := 0.1
const STUCK_EPSILON_PIXELS := 1.5
const ATTACK_RETRY_SECONDS := 0.3
const AVOID_ANGLE_DEGREES := 55.0
const AVOID_STEPS := 20

## What this enemy drops when killed.
## Experience granted to the player when this enemy dies.
@export var experience_reward: int = 20
@export var drop_table: DropTable
@export var command_port_path: NodePath
@export var combatant_path: NodePath
@export var spawner_path: NodePath
@export var aim_line_path: NodePath
@export var target_path: NodePath

## Distance it tries to hold from the player, in logical pixels.
@export var preferred_distance_pixels := 150.0
## How far off the preferred distance it tolerates before repositioning.
@export var distance_slack_pixels := 30.0
## Maximum range at which it will begin a shot.
@export var max_fire_distance_pixels := 230.0
## When true the archer never repositions. Used by tests that need a deterministic firing line;
## the shipped archer leaves this false.
@export var hold_position := false

var _command_port: ActorCommandPort
var _combatant: ActorCombatant
var _spawner: AttackSpawner
var _aim_line: Line2D
var _blocked_shots := 0

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
	target_path = path
	_configure()

func _configure() -> void:
	_command_port = get_node_or_null(command_port_path) as ActorCommandPort
	_combatant = get_node_or_null(combatant_path) as ActorCombatant
	_spawner = get_node_or_null(spawner_path) as AttackSpawner
	_aim_line = get_node_or_null(aim_line_path) as Line2D
	if target_path != NodePath() and _spawner != null:
		_spawner.target_path = target_path
	if _spawner != null and not _spawner.shot_blocked_by_wall.is_connected(_on_shot_blocked):
		_spawner.shot_blocked_by_wall.connect(_on_shot_blocked)
	_last_position = global_position

func blocked_shot_count() -> int:
	return _blocked_shots

func _on_shot_blocked() -> void:
	_blocked_shots += 1

func _physics_process(delta: float) -> void:
	if _command_port == null or _combatant == null:
		return
	_attack_timer = maxf(0.0, _attack_timer - delta)
	_update_aim_visual()
	velocity = _command_port.get_velocity()
	move_and_slide()
	if not _combatant.is_alive():
		return
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
	var can_see := CombatLineOfSight.is_clear(get_world_2d(), global_position, target.global_position)

	## Aim before committing; the spawner rechecks cover at release.
	if can_see and distance <= max_fire_distance_pixels and _attack_timer <= 0.0:
		_command_port.set_intent(Vector2.ZERO, direction, false)
		if _command_port.request_action(ActorCommandPort.Action.LIGHT_ATTACK):
			_attack_timer = 0.0
			_move_axis = Vector2.ZERO
			return
		_attack_timer = ATTACK_RETRY_SECONDS

	## Without a clear line it still repositions, which is how it walks around cover.
	if not can_see:
		_move_axis = Vector2.ZERO if hold_position else _steer(direction)
		_command_port.set_intent(_move_axis, direction, false)
		return

	_command_port.set_intent(_move_axis_for(direction, distance), direction, false)

## Keeps the stand-off band: back away when crowded, close in when too far, stand when inside it.
func _move_axis_for(direction: Vector2, distance: float) -> Vector2:
	if hold_position:
		_move_axis = Vector2.ZERO
		return Vector2.ZERO
	if distance < preferred_distance_pixels - distance_slack_pixels:
		_move_axis = -direction
		return _steer(_move_axis)
	if distance > preferred_distance_pixels + distance_slack_pixels:
		_move_axis = direction
		return _steer(_move_axis)
	_move_axis = Vector2.ZERO
	return Vector2.ZERO

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

## Aim telegraph: the line grows through the wind-up and snaps bright just before release, so the
## player can read when the arrow is coming. Purely visual, never used for damage.
func _update_aim_visual() -> void:
	if _aim_line == null:
		return
	var target := get_node_or_null(target_path) as Node2D
	var state := _command_port.get_state()
	if target == null or state == ActorCommandPort.State.DEAD:
		_aim_line.visible = false
		return
	var direction := _command_port.get_facing()
	var distance := minf(global_position.distance_to(target.global_position), max_fire_distance_pixels)
	var spec: AttackSpec = _command_port.get_active_attack()
	match state:
		ActorCommandPort.State.WINDUP:
			var windup: float = spec.windup_seconds if spec != null else 0.5
			var progress := clampf(_command_port.get_state_elapsed() / maxf(windup, 0.001), 0.0, 1.0)
			_aim_line.visible = true
			_aim_line.modulate = Color(1.0, 0.85 - 0.5 * progress, 0.3, 0.35 + 0.55 * progress)
			_aim_line.points = PackedVector2Array([Vector2.ZERO, direction * distance])
		ActorCommandPort.State.ACTIVE:
			_aim_line.visible = true
			_aim_line.modulate = Color(1.0, 0.35, 0.25, 1.0)
			_aim_line.points = PackedVector2Array([Vector2.ZERO, direction * distance])
		_:
			_aim_line.visible = false

## Retry: back to spawn with full vitals and no pending action or blocked-shot tally.
func reset_for_retry() -> void:
	global_position = spawn_position
	velocity = Vector2.ZERO
	_move_axis = Vector2.ZERO
	_attack_timer = 0.0
	_decision_timer = 0.0
	_avoid_steps = 0
	_blocked_shots = 0
	_last_position = global_position
	if _command_port is ActorActionPort:
		(_command_port as ActorActionPort).reset_state()
	if _combatant != null:
		_combatant.reset_vitals()
	if _aim_line != null:
		_aim_line.visible = false

## Experience this enemy is worth to the player, read by the reward path.
func get_experience_reward() -> int:
	return experience_reward
