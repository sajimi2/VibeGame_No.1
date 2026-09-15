class_name CombatLineOfSight
extends RefCounted
## Pure-ish physics helpers shared by ranged AI and tests: "can A see B without a wall between".
## Kept in one place so the archer's decision and the test's expectation cannot drift apart.

const WALL_LAYER := 1

## True when nothing on the wall layer sits between `from` and `to`.
static func is_clear(world: World2D, from: Vector2, to: Vector2) -> bool:
	if world == null:
		return false
	var space := world.direct_space_state
	if space == null:
		return false
	var query := PhysicsRayQueryParameters2D.create(from, to)
	query.collision_mask = WALL_LAYER
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return space.intersect_ray(query).is_empty()
