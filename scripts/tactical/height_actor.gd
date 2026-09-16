extends CharacterBody3D
const Art = preload("res://scripts/tactical/directional_art.gd")
const STAND_HEIGHT := 1.65
const CROUCH_HEIGHT := 0.95
var camera: Camera3D
var aim_point := Vector3.ZERO
var cursor := Vector2.ZERO
var shape_node: CollisionShape3D
var sprite: Sprite3D
var outline: Sprite3D
var crouched := false
var facing := Vector2(0, 1)
var direction_index := 0
var gait := 0.0
var movement_direction := 0
var shadow: Node3D
var world_shadow: MeshInstance3D
var occluded := false
var test_mode := false
var test_motion := Vector2.ZERO
var test_crouch := false
var max_hp := 100
var safe_zone := false
var hp := 100
var hurt_time := 0.0
var invulnerable := 0.0
var attack_pose := 0
var attack_facing := Vector2(0,1)
var effects: Node3D
var foot_distance := 0.0
var landing_delay := 0.0
var jumped := false
var spawn := Vector3(-6, 0.1, 5)

func _ready() -> void:
	cursor = get_viewport().get_mouse_position()
	var listener := AudioListener3D.new()
	listener.position.y = 1.1
	add_child(listener)
	listener.make_current()
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.35
	floor_constant_speed = true
	floor_max_angle = deg_to_rad(42)
	shape_node = CollisionShape3D.new()
	# Rounded locomotion shape avoids flat cylinder rims snagging convex ramp edges.
	# Combat body/top hit regions remain a separate future component.
	var locomotion := CapsuleShape3D.new()
	locomotion.radius = 0.29
	locomotion.height = STAND_HEIGHT
	shape_node.shape = locomotion
	shape_node.position.y = STAND_HEIGHT / 2
	add_child(shape_node)
	sprite = _sprite(false)
	outline = _sprite(true)
	outline.visible = false
	shadow = preload("res://scripts/tactical/ground_shadow.gd").new()
	shadow.radius=0.18
	add_child(shadow)
	world_shadow=preload("res://scripts/tactical/world_lighting.gd").actor_shadow(self)
	_refresh_art(0)

func _sprite(is_outline: bool) -> Sprite3D:
	var item := Sprite3D.new()
	item.pixel_size = 0.04
	item.offset = Vector2(0, 24)
	item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	item.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	item.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	item.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	item.no_depth_test = is_outline
	item.render_priority = 10 if is_outline else 0
	add_child(item)
	return item

func set_crouch(value: bool) -> bool:
	if value == crouched: return true
	if not value:
		var query := PhysicsShapeQueryParameters3D.new()
		var standing := CapsuleShape3D.new()
		standing.radius = 0.28
		standing.height = STAND_HEIGHT - 0.04
		query.shape = standing
		query.transform = Transform3D(Basis.IDENTITY, global_position + Vector3.UP * (STAND_HEIGHT / 2 + 0.03))
		query.collision_mask = 1
		query.exclude = [get_rid()]
		if not get_world_3d().direct_space_state.intersect_shape(query).is_empty(): return false
	crouched = value
	var height := CROUCH_HEIGHT if value else STAND_HEIGHT
	shape_node.shape.height = height
	shape_node.position.y = height / 2
	return true

func _physics_process(delta: float) -> void:
	hurt_time = maxf(0,hurt_time-delta)
	invulnerable = maxf(0,invulnerable-delta)
	sprite.modulate = Color(0.55,0.55,0.55) if hp<=0 else Color(1.8,0.8,0.7) if hurt_time>0 else Color.WHITE
	sprite.rotation.z = -0.7 if hp<=0 else 0
	world_shadow.visible = hp>0
	var move := test_motion if test_mode else Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if hp <= 0: move = Vector2.ZERO
	set_crouch(test_crouch if test_mode else Input.is_physical_key_pressed(KEY_C))
	if not test_mode and camera != null:
		var world_move := camera.global_basis.x * move.x + Vector3(camera.global_basis.z.x, 0, camera.global_basis.z.z).normalized() * move.y
		move = Vector2(world_move.x, world_move.z)
	var speed := 2.0 if crouched else 4.2
	landing_delay=maxf(0,landing_delay-delta)
	if is_on_floor() or not jumped:
		velocity.x = move.x * speed
		velocity.z = move.y * speed
	else:
		velocity.x = move_toward(velocity.x,move.x*speed,delta*3.0)
		velocity.z = move_toward(velocity.z,move.y*speed,delta*3.0)
	velocity.y -= 20 * delta
	var previous_position := global_position
	var was_airborne := not is_on_floor()
	move_and_slide()
	if was_airborne and is_on_floor() and jumped:
		jumped=false
		landing_delay=0.12
		if is_instance_valid(effects): effects.landing(global_position)
	var traveled := global_position - previous_position
	var planar_distance := Vector2(traveled.x, traveled.z).length()
	foot_distance += planar_distance
	if foot_distance > 1.0 and is_on_floor():
		foot_distance = 0
		if is_instance_valid(effects): effects.sound("step",global_position)
	if move.length() > 0.1:
		if attack_pose == 0: facing = move.normalized()
		gait += planar_distance / 1.8 * TAU
	if not test_mode and camera != null and attack_pose not in [1,2,3]: update_aim(cursor)
	if attack_pose in [1,2,3]: facing = attack_facing
	var view_facing := Vector3(facing.x, 0, facing.y)
	if camera != null: view_facing = view_facing.rotated(Vector3.UP, -camera.rotation.y)
	direction_index = posmod(roundi(atan2(view_facing.x, view_facing.z) / (PI / 6)), 12)
	var walk_direction := Vector3(move.x, 0, move.y)
	if camera != null: walk_direction = walk_direction.rotated(Vector3.UP, -camera.rotation.y)
	movement_direction = posmod(roundi(atan2(walk_direction.x, walk_direction.z) / (PI / 6)), 12)
	_refresh_art(posmod(int(gait / TAU * 8), 8) if planar_distance > 0.002 and is_on_floor() else -1)
	_update_occlusion()
	if global_position.y < -5: reset_position()

func _refresh_art(step: int) -> void:
	var height := CROUCH_HEIGHT if crouched else STAND_HEIGHT
	for item in [sprite, outline]:
		item.position = Vector3.ZERO
		item.scale.y = 0.7 if crouched else 0.92 if jumped else 1.0
	sprite.texture = Art.texture(direction_index, step, crouched, false, movement_direction, attack_pose)
	outline.texture = Art.texture(direction_index, step, crouched, true, movement_direction, attack_pose)

func _update_occlusion() -> void:
	if camera == null: return
	var target := global_position + Vector3.UP * (0.5 if crouched else 0.95)
	var screen := camera.unproject_position(target)
	var origin := camera.project_ray_origin(screen)
	var query := PhysicsRayQueryParameters3D.create(origin, target, 1 | 4)
	query.exclude = [get_rid()]
	occluded = not get_world_3d().direct_space_state.intersect_ray(query).is_empty()
	outline.visible = occluded

func reset_position() -> void:
	hp = max_hp
	invulnerable = 0
	global_position = spawn
	velocity = Vector3.ZERO
	jumped=false
	landing_delay=0


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==KEY_SPACE: request_jump()
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		cursor = event.position

func update_aim(mouse: Vector2) -> void:
	if camera == null: return
	var origin := camera.project_ray_origin(mouse)
	var ray := camera.project_ray_normal(mouse)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + ray * 100, 1 | 8 | 16)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var target = hit.get("position", Plane(Vector3.UP, global_position.y + 0.65).intersects_ray(origin, ray))
	if target != null:
		aim_point = target
		var aim: Vector3 = target - global_position
		if Vector2(aim.x, aim.z).length() > 0.2: facing = Vector2(aim.x, aim.z).normalized()

func receive_damage(amount: int, _direction: Vector3) -> void:
	if hp <= 0 or invulnerable > 0 or safe_zone: return
	hp = maxi(0,hp-amount)
	hurt_time = 0.18
	invulnerable = 0.65
	if is_instance_valid(effects): effects.impact(global_position+Vector3.UP,amount,hp==0)

func request_jump() -> bool:
	if hp<=0 or crouched or not is_on_floor() or jumped or landing_delay>0: return false
	velocity.y=5.3
	jumped=true
	if is_instance_valid(effects): effects.sound("step",global_position)
	return true
