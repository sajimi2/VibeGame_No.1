class_name ActorMovement
extends RefCounted
## Pure, node-free movement math for actors. Keeps speed decisions in one place so
## cardinal and diagonal input produce the same distance per second (no sqrt(2) gain).

const MIN_AXIS_LENGTH := 0.001

## Returns a direction whose length is at most 1: diagonal input is normalized,
## analog input below full deflection keeps its magnitude.
static func normalized_axis(move_axis: Vector2) -> Vector2:
	var length := move_axis.length()
	if length <= MIN_AXIS_LENGTH:
		return Vector2.ZERO
	if length > 1.0:
		return move_axis / length
	return move_axis

## Velocity for one physics step. Never exceeds speed_pixels_per_second.
static func velocity_for(move_axis: Vector2, speed_pixels_per_second: float) -> Vector2:
	return normalized_axis(move_axis) * speed_pixels_per_second

## Facing is the last non-zero aim; a zero aim preserves the previous facing.
static func resolve_facing(aim_direction: Vector2, previous_facing: Vector2) -> Vector2:
	if aim_direction.length() <= MIN_AXIS_LENGTH:
		return previous_facing
	return aim_direction.normalized()

## Direction of a dodge started with the given intent: the requested direction when there is
## one, otherwise the direction the actor already faces (DESIGN: zero input dodges forward).
static func dodge_direction(move_axis: Vector2, facing: Vector2) -> Vector2:
	var direction := normalized_axis(move_axis)
	if direction == Vector2.ZERO:
		return facing.normalized()
	return direction.normalized()

## Knockback decays exponentially so a hit shoves the body without an endless slide.
static func decayed_knockback(current: Vector2, delta: float, damping: float) -> Vector2:
	if damping <= 0.0:
		return Vector2.ZERO
	return current * exp(-damping * delta)
