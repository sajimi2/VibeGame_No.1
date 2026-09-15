class_name ActorActionPort
extends ActorCommandPort
## Concrete ActorCommandPort. Owns the whole action state machine for one actor: locomotion,
## light/heavy attacks, dodge, directional block, stagger and death. It is the single place that
## decides legality and pays stamina; the body only asks for a velocity, and the hitbox only
## asks whether the ACTIVE window is open.
##
## Busy actions are never queued or replayed: a refused request changes nothing at all.

## Emitted when an attack leaves WINDUP and its damage window opens (hitbox uses this to arm).
signal attack_window_opened(spec: AttackSpec)
signal attack_window_closed(spec: AttackSpec)
signal attack_started(spec: AttackSpec)
signal action_refused(action: Action)

@export var tuning: ActorTuning
## ActorCombatant component that owns health/stamina and answers try_spend_stamina.
@export var combatant_path: NodePath

var _state: ActorCommandPort.State = ActorCommandPort.State.IDLE
var _state_elapsed := 0.0
var _move_axis := Vector2.ZERO
var _facing := Vector2.RIGHT
var _block_held := false
var _active_spec: AttackSpec = null
var _attack_id := 0
var _attack_direction := Vector2.RIGHT
var _dodge_direction := Vector2.RIGHT
var _combatant: ActorCombatant
var _stagger_override := -1.0

func _ready() -> void:
	_combatant = get_node_or_null(combatant_path) as ActorCombatant
	if tuning == null:
		push_error("ActorActionPort: tuning resource is required")

# --- contract -----------------------------------------------------------------------------

func set_intent(move_axis: Vector2, aim_direction: Vector2, block_held: bool) -> void:
	_move_axis = ActorMovement.normalized_axis(move_axis)
	_block_held = block_held
	## Facing is locked for the whole of an attack so a swing cannot be steered, and while
	## staggered or dead the actor does not re-aim at all.
	if _facing_locked():
		return
	_facing = ActorMovement.resolve_facing(aim_direction, _facing)
	if not ActionRules.allows_locomotion(_state):
		return
	## While the guard is held the actor stays in BLOCK and merely turns; movement is refused so
	## the shield direction cannot be re-aimed mid-swing by walking around.
	if block_held:
		_set_state(ActorCommandPort.State.BLOCK)
	else:
		_set_state(ActionRules.locomotion_state(_move_axis != Vector2.ZERO))

func request_action(action: Action) -> bool:
	if _state == ActorCommandPort.State.DEAD or _state == ActorCommandPort.State.STAGGER:
		action_refused.emit(action)
		return false
	match action:
		Action.LIGHT_ATTACK:
			return _try_start_attack(tuning.light_attack)
		Action.HEAVY_ATTACK:
			return _try_start_attack(tuning.heavy_attack)
		Action.DODGE:
			return _try_start_dodge()
		Action.DASH:
			## A beast's lunge is an ordinary attack whose spec carries a charge distance, so it
			## reuses the same commit/damage/lock rules instead of a parallel state.
			return _try_start_attack(tuning.dash_attack)
		_:
			return false

func get_state() -> State:
	return _state

func get_state_elapsed() -> float:
	return _state_elapsed

func get_attack_id() -> int:
	return _attack_id

func get_facing() -> Vector2:
	return _facing

## Commands are only accepted while the actor is free; an in-progress action keeps its own
## velocity (dodge travel, attack charge) and a locked state stops the body.
func get_velocity() -> Vector2:
	if tuning == null:
		return Vector2.ZERO
	match _state:
		ActorCommandPort.State.DEAD, ActorCommandPort.State.STAGGER, ActorCommandPort.State.BLOCK:
			return Vector2.ZERO
		ActorCommandPort.State.DODGE:
			return _dodge_direction * tuning.dodge_speed
		ActorCommandPort.State.WINDUP, ActorCommandPort.State.ACTIVE, ActorCommandPort.State.RECOVERY:
			return _attack_charge_velocity()
		_:
			return ActorMovement.velocity_for(_move_axis, _move_speed())

## Base tuning speed plus equipment bonuses. Never below zero, so heavy armour slows but cannot
## reverse movement.
func _move_speed() -> float:
	var bonus := _combatant.equipment_modifier(ActorCombatant.STAT_MOVE_SPEED) if _combatant != null else 0.0
	return maxf(0.0, tuning.move_speed + bonus)

## A charging attack (beast lunge) drags the body along the locked attack direction; a normal
## attack stands still. Speed is derived from the spec so the distance stays the tuning knob.
func _attack_charge_velocity() -> Vector2:
	if _active_spec == null or _active_spec.charge_distance_pixels <= 0.0:
		return Vector2.ZERO
	var total := _active_spec.windup_seconds + _active_spec.active_seconds + _active_spec.recovery_seconds
	if total <= 0.0:
		return Vector2.ZERO
	return _attack_direction * (_active_spec.charge_distance_pixels / total)

## True only while the damage window is open. The hitbox polls this, so the ACTIVE window is
## decided in exactly one place.
func is_attack_window_open() -> bool:
	return _state == ActorCommandPort.State.ACTIVE and _active_spec != null

func get_active_attack() -> AttackSpec:
	return _active_spec

func get_tuning() -> ActorTuning:
	return tuning

# --- external events ----------------------------------------------------------------------

## Interrupts the actor (a landed hit, or a broken guard). Ignored once dead.
func apply_stagger(seconds: float) -> void:
	if _state == ActorCommandPort.State.DEAD:
		return
	_active_spec = null
	_stagger_override = seconds
	_set_state(ActorCommandPort.State.STAGGER)

## Exactly-once death transition; further calls are no-ops.
func apply_death() -> void:
	if _state == ActorCommandPort.State.DEAD:
		return
	_active_spec = null
	_move_axis = Vector2.ZERO
	_set_state(ActorCommandPort.State.DEAD)

## Restores the machine for a retry.
func reset_state() -> void:
	_state = ActorCommandPort.State.IDLE
	_state_elapsed = 0.0
	_move_axis = Vector2.ZERO
	_block_held = false
	_active_spec = null
	_stagger_override = -1.0

# --- per-step advance ---------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if tuning == null:
		return
	_state_elapsed += delta
	var next := ActionRules.next_phase(_state, _state_elapsed, _active_spec, tuning)
	if _state == ActorCommandPort.State.STAGGER and _stagger_override >= 0.0 and _state_elapsed >= _stagger_override:
		next = ActorCommandPort.State.IDLE
	if _state == ActorCommandPort.State.BLOCK:
		return
	if next != _state:
		_leave_state(_state)
		_enter_state(next)

# --- transitions --------------------------------------------------------------------------

## Spending is atomic: a refused payment leaves state untouched. An attack that costs nothing (an
## archer's shot) is not a payment at all, so it must not be routed through try_spend_stamina,
## which correctly refuses non-positive amounts.
func _pay_stamina(cost: float) -> bool:
	if cost <= 0.0:
		return true
	if _combatant == null:
		return false
	return _combatant.try_spend_stamina(cost)

func _try_start_attack(spec: AttackSpec) -> bool:
	if spec == null:
		return false
	## Attacks may start from a free state or straight out of a held guard, but never out of
	## another attack, a dodge or a stagger.
	if not ActionRules.allows_locomotion(_state):
		action_refused.emit(ActorCommandPort.Action.LIGHT_ATTACK)
		return false
	if not _pay_stamina(spec.stamina_cost):
		action_refused.emit(ActorCommandPort.Action.LIGHT_ATTACK)
		return false
	_active_spec = spec
	_attack_id += 1
	_attack_direction = _facing
	_block_held = false
	attack_started.emit(spec)
	_leave_state(_state)
	_set_state(ActorCommandPort.State.WINDUP)
	return true

func _try_start_dodge() -> bool:
	if not ActionRules.allows_locomotion(_state):
		action_refused.emit(ActorCommandPort.Action.DODGE)
		return false
	if not _pay_stamina(_dodge_cost()):
		action_refused.emit(ActorCommandPort.Action.DODGE)
		return false
	_dodge_direction = ActorMovement.dodge_direction(_move_axis, _facing)
	_block_held = false
	_leave_state(_state)
	_set_state(ActorCommandPort.State.DODGE)
	return true

func _dodge_cost() -> float:
	return tuning.dodge_stamina_cost

func _leave_state(left: ActorCommandPort.State) -> void:
	if left == ActorCommandPort.State.ACTIVE and _active_spec != null:
		attack_window_closed.emit(_active_spec)

func _enter_state(next: ActorCommandPort.State) -> void:
	var previous := _state
	_state = next
	_state_elapsed = 0.0
	if next == ActorCommandPort.State.ACTIVE and _active_spec != null:
		attack_window_opened.emit(_active_spec)
	if next == ActorCommandPort.State.IDLE or next == ActorCommandPort.State.MOVE:
		_active_spec = null
		_stagger_override = -1.0
	if next == ActorCommandPort.State.BLOCK:
		_active_spec = null
	state_changed.emit(previous, next)

func _set_state(next: ActorCommandPort.State) -> void:
	if next == _state:
		return
	_enter_state(next)

## Facing is locked during attacks so the windup direction is committed, and during stagger/death
## because the actor is not in control.
func _facing_locked() -> bool:
	return _state in [
		ActorCommandPort.State.WINDUP,
		ActorCommandPort.State.ACTIVE,
		ActorCommandPort.State.RECOVERY,
		ActorCommandPort.State.STAGGER,
		ActorCommandPort.State.DEAD,
	]
