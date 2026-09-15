class_name ActionRules
extends RefCounted
## Pure, node-free rules for the actor action state machine: which transitions are legal, how
## long each phase lasts, and which phases may deal damage or be damaged. Keeping this free of
## nodes is what makes the timing boundaries testable without a running scene.

## States that no new request may interrupt.
const LOCKED_STATES: Array[int] = [
	ActorCommandPort.State.STAGGER,
	ActorCommandPort.State.DEAD,
]

## States whose elapsed time drives a phase transition.
const TIMED_STATES: Array[int] = [
	ActorCommandPort.State.WINDUP,
	ActorCommandPort.State.ACTIVE,
	ActorCommandPort.State.RECOVERY,
	ActorCommandPort.State.DODGE,
	ActorCommandPort.State.STAGGER,
]

## During these states stamina does not regenerate (DESIGN: attacks, dodge and block pause it).
const STAMINA_REGEN_PAUSED_STATES: Array[int] = [
	ActorCommandPort.State.WINDUP,
	ActorCommandPort.State.ACTIVE,
	ActorCommandPort.State.RECOVERY,
	ActorCommandPort.State.DODGE,
	ActorCommandPort.State.BLOCK,
]

static func locomotion_state(has_movement: bool) -> ActorCommandPort.State:
	return ActorCommandPort.State.MOVE if has_movement else ActorCommandPort.State.IDLE

## True while the actor has full control back and may start a new action.
static func allows_locomotion(state: ActorCommandPort.State) -> bool:
	if state in LOCKED_STATES:
		return false
	return state in [ActorCommandPort.State.IDLE, ActorCommandPort.State.MOVE, ActorCommandPort.State.BLOCK]

static func stamina_regenerates(state: ActorCommandPort.State) -> bool:
	return not (state in STAMINA_REGEN_PAUSED_STATES)

## Attacker may deal damage only in ACTIVE. Dodge is the only damage-avoiding state.
static func deals_damage(state: ActorCommandPort.State) -> bool:
	return state == ActorCommandPort.State.ACTIVE

static func is_invulnerable(state: ActorCommandPort.State, elapsed: float, invuln_start: float, invuln_end: float) -> bool:
	if state != ActorCommandPort.State.DODGE:
		return false
	return elapsed >= invuln_start and elapsed < invuln_end

## Phase the actor moves into when the current phase's time is up. LOCKED states stay put: they
## are ended by their own code path, never by the phase timer.
static func next_phase(state: ActorCommandPort.State, elapsed: float, spec: AttackSpec, tuning: ActorTuning) -> ActorCommandPort.State:
	match state:
		ActorCommandPort.State.WINDUP:
			if spec != null and elapsed >= spec.windup_seconds:
				return ActorCommandPort.State.ACTIVE
		ActorCommandPort.State.ACTIVE:
			if spec != null and elapsed >= spec.active_seconds:
				return ActorCommandPort.State.RECOVERY
		ActorCommandPort.State.RECOVERY:
			if spec != null and elapsed >= spec.recovery_seconds:
				return ActorCommandPort.State.IDLE
		ActorCommandPort.State.DODGE:
			if tuning != null and elapsed >= tuning.dodge_seconds:
				return ActorCommandPort.State.IDLE
		ActorCommandPort.State.STAGGER:
			if tuning != null and elapsed >= tuning.hit_stagger_seconds:
				return ActorCommandPort.State.IDLE
		_:
			pass
	return state
