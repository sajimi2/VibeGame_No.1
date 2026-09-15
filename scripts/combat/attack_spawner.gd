class_name AttackSpawner
extends Node2D
## Turns an open damage window into either a melee sweep or one projectile. The ACTIVE window is
## owned by the ActorCommandPort; this node only acts on it, and only once per attack id.
##
## A ranged attack additionally requires line of sight at the moment the window opens: a shot into
## a wall is not fired at all. That is what stops an archer behind cover from attacking "through"
## it, and it keeps the rule in one place instead of in each AI.

signal hit_landed(target: CombatantPort, result: HitResult)
signal projectile_spawned(projectile: CombatProjectile)
signal shot_blocked_by_wall

@export var command_port_path: NodePath
@export var combatant_path: NodePath
## Layer holding target hurtboxes.
@export_flags_2d_physics var target_layer: int = 4
## Who to test line of sight against for ranged attacks. Optional for melee-only actors.
@export var target_path: NodePath
## Muzzle offset along the attack direction, so an arrow never starts inside its own shooter.
@export var muzzle_offset_pixels := 12.0

var _command_port: ActorCommandPort
var _combatant: ActorCombatant
var _applied_attack_id := 0

func _ready() -> void:
	_command_port = get_node_or_null(command_port_path) as ActorCommandPort
	_combatant = get_node_or_null(combatant_path) as ActorCombatant
	if _command_port == null:
		push_error("AttackSpawner: command_port_path must point at an ActorCommandPort")
	if _combatant == null:
		push_error("AttackSpawner: combatant_path must point at an ActorCombatant")

func _physics_process(_delta: float) -> void:
	if _command_port == null or _combatant == null:
		return
	## A port without attacks (a test double) never opens a window.
	if not _command_port.has_method("is_attack_window_open"):
		return
	if not _command_port.is_attack_window_open():
		return
	var spec: AttackSpec = _command_port.get_active_attack()
	if spec == null:
		return
	var attack_id := _command_port.get_attack_id()
	if attack_id == _applied_attack_id:
		return
	_applied_attack_id = attack_id
	if spec.spawns_projectile:
		_fire_projectile(spec, attack_id)
	else:
		_apply_melee(spec, attack_id)

func attack_direction() -> Vector2:
	var facing := _command_port.get_facing()
	return facing.normalized() if facing != Vector2.ZERO else Vector2.RIGHT

# --- melee ---------------------------------------------------------------------------------

func _apply_melee(spec: AttackSpec, attack_id: int) -> void:
	var owner_body := _combatant.get_parent() as Node2D
	if owner_body == null:
		return
	var direction := attack_direction()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(spec.range_pixels, spec.half_height_pixels * 2.0)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(direction.angle(), global_position + direction * (spec.forward_offset_pixels + spec.range_pixels * 0.5))
	query.collision_mask = target_layer
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var space := get_world_2d().direct_space_state
	if space == null:
		return
	for hit in space.intersect_shape(query, 16):
		var collider: Variant = hit.collider
		if not (collider is Node):
			continue
		var target := _find_combatant(collider as Node)
		if target == null or target == _combatant:
			continue
		_apply_hit(target, spec, attack_id, owner_body.global_position)

func _apply_hit(target: ActorCombatant, spec: AttackSpec, attack_id: int, origin: Vector2) -> void:
	if not target.is_alive():
		return
	if target.has_seen(_combatant.get_instance_id(), attack_id):
		return
	target.mark_seen(_combatant.get_instance_id(), attack_id)
	var event := DamageEvent.new()
	event.source_id = _combatant.get_instance_id()
	event.attack_id = attack_id
	event.team_id = _combatant.tuning.team_id if _combatant.tuning != null else 0
	## Weapon bonuses add to the attack's base damage; the shared spec resource is never modified.
	event.raw_damage = spec.damage + _combatant.attack_bonus()
	event.stamina_damage = spec.stamina_damage
	event.stagger_seconds = spec.stagger_seconds
	event.origin = origin
	event.knockback = _command_port.get_facing() * spec.knockback_pixels
	hit_landed.emit(target, target.receive_hit(event))

# --- ranged --------------------------------------------------------------------------------

func _fire_projectile(spec: AttackSpec, attack_id: int) -> void:
	if not _has_line_of_sight():
		## The window is spent but nothing is fired: shooting into a wall is not an attack.
		shot_blocked_by_wall.emit()
		return
	if spec.projectile_scene == null:
		push_error("AttackSpawner: ranged attack has no projectile_scene")
		return
	var instance := spec.projectile_scene.instantiate()
	if not (instance is CombatProjectile):
		push_error("AttackSpawner: projectile_scene is not a CombatProjectile")
		instance.free()
		return
	var projectile := instance as CombatProjectile
	var direction := attack_direction()
	var owner_body := _combatant.get_parent() as Node2D
	# Include the muzzle offset in wall detection, including a muzzle inside a wall.
	var muzzle := global_position + direction * muzzle_offset_pixels
	var muzzle_query := PhysicsRayQueryParameters2D.create(global_position, muzzle, 1)
	muzzle_query.hit_from_inside = true
	if not get_world_2d().direct_space_state.intersect_ray(muzzle_query).is_empty():
		projectile.free()
		shot_blocked_by_wall.emit()
		return
	var parent := get_parent()
	if parent == null:
		projectile.free()
		return
	# Keep lifecycle ownership for retry/scene cleanup without inheriting shooter movement.
	projectile.top_level = true
	parent.add_child(projectile)
	projectile.global_position = muzzle
	projectile.setup(
		direction,
		_combatant.tuning.team_id if _combatant.tuning != null else 0,
		spec,
		owner_body.get_instance_id() if owner_body != null else 0,
		attack_id)
	projectile_spawned.emit(projectile)

func _has_line_of_sight() -> bool:
	var target := get_node_or_null(target_path) as Node2D
	if target == null:
		return true
	return CombatLineOfSight.is_clear(get_world_2d(), global_position, target.global_position)

# --- shared --------------------------------------------------------------------------------

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
