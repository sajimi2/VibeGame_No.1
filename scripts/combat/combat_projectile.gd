class_name CombatProjectile
extends Node2D
## A travelling arrow. It owns only its own flight: it asks the physics space what it would hit
## along this step (walls block it, a hostile hurtbox takes the hit) and hands the target a
## DamageEvent through the same CombatantPort entry point every other attack uses. It never
## changes health itself and never picks a target by name.

const WALL_LAYER := 1
const HURTBOX_LAYER := 4
## Grace during which the shooter's own body is ignored, so an arrow cannot hit its archer.
const SPAWN_GRACE_SECONDS := 0.03

signal expired
signal impacted(target: CombatantPort, result: HitResult)

@export var speed_pixels := 210.0
@export var max_range_pixels := 260.0

var _direction := Vector2.RIGHT
var _source_team := 0
var _source_id := 0
var _attack_id := 0
var _spec: AttackSpec
var _travelled := 0.0
var _grace := SPAWN_GRACE_SECONDS
var _exclude: Array[RID] = []

func setup(direction: Vector2, team_id: int, spec: AttackSpec, source_id: int, attack_id: int) -> void:
	_direction = direction.normalized() if direction != Vector2.ZERO else Vector2.RIGHT
	_source_team = team_id
	_source_id = source_id
	_attack_id = attack_id
	_spec = spec
	rotation = _direction.angle()
	if spec != null:
		speed_pixels = spec.projectile_speed_pixels
		max_range_pixels = spec.projectile_max_range_pixels
	_exclude = _build_exclusion()

func _physics_process(delta: float) -> void:
	if _grace > 0.0:
		_grace = maxf(0.0, _grace - delta)
	var step := speed_pixels * delta
	if _resolve_step(step):
		return
	global_position += _direction * step
	_travelled += step
	if _travelled >= max_range_pixels:
		_despawn()

## Returns true when the arrow's flight ended this step (wall or target).
func _resolve_step(step: float) -> bool:
	var query := PhysicsRayQueryParameters2D.create(global_position, global_position + _direction * step)
	query.collision_mask = WALL_LAYER | HURTBOX_LAYER
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.hit_from_inside = true
	query.exclude = _exclude
	var space := get_world_2d().direct_space_state
	if space == null:
		return false
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return false
	var collider: Variant = hit.get("collider")
	if collider is Node:
		var target := _find_combatant(collider as Node)
		if target != null and _is_hostile(target):
			_apply_hit(target)
			return true
	## Anything else is a wall: the arrow stops and is gone.
	_despawn()
	return true

## Only the shooter's own body is ignored, and only while the grace lasts.
func _build_exclusion() -> Array[RID]:
	if _source_id == 0:
		return []
	var shooter := instance_from_id(_source_id)
	if shooter is CollisionObject2D:
		return [(shooter as CollisionObject2D).get_rid()]
	return []

func _is_hostile(target: ActorCombatant) -> bool:
	if target.tuning == null:
		return false
	return target.tuning.team_id != _source_team

func _apply_hit(target: ActorCombatant) -> void:
	if _spec == null:
		_despawn()
		return
	## Same per-target dedup key as melee: (source_id, attack_id).
	if target.has_seen(_source_id, _attack_id):
		_despawn()
		return
	target.mark_seen(_source_id, _attack_id)
	var event := DamageEvent.new()
	event.source_id = _source_id
	event.attack_id = _attack_id
	event.team_id = _source_team
	event.raw_damage = _spec.damage
	event.stamina_damage = _spec.stamina_damage
	event.stagger_seconds = _spec.stagger_seconds
	event.origin = global_position
	event.knockback = _direction * _spec.knockback_pixels
	var result := target.receive_hit(event)
	impacted.emit(target, result)
	_despawn()

func _despawn() -> void:
	expired.emit()
	queue_free()

## Targets are found by walking up from the collider to the actor body that owns a CombatantPort.
func _find_combatant(from: Node) -> ActorCombatant:
	var node: Node = from
	while node != null:
		for child in node.get_children():
			if child is ActorCombatant:
				return child as ActorCombatant
		node = node.get_parent()
		if node is Viewport:
			break
	return null
