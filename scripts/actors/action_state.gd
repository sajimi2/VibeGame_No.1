class_name ActionState
extends RefCounted
## Pure state-transition helper for ActorCommandPort.State. Contains no node logic and
## no combat timing: T01 only ever produces IDLE or MOVE.

## States that must not be interrupted or overridden by a later implementation.
const LOCKED_STATES: Array[int] = [
	ActorCommandPort.State.DEAD,
	ActorCommandPort.State.STAGGER,
]

## State an actor with the given movement takes while it is free to move.
static func locomotion_state(has_movement: bool) -> ActorCommandPort.State:
	return ActorCommandPort.State.MOVE if has_movement else ActorCommandPort.State.IDLE

## True while full control has been given back to the actor.
static func allows_locomotion(state: ActorCommandPort.State) -> bool:
	if state in LOCKED_STATES:
		return false
	return state in [ActorCommandPort.State.IDLE, ActorCommandPort.State.MOVE]
