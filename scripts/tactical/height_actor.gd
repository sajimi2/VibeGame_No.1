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
var occluded := false
var test_mode := false
var test_motion := Vector2.ZERO
var test_crouch := false
var spawn := Vector3(-6, 0.1, 5)

func _ready() -> void:
	cursor = get_viewport().get_mouse_position()
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
	_refresh_art(0)

func _sprite(is_outline: bool) -> Sprite3D:
	var item := Sprite3D.new()
	item.pixel_size = 0.06
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
	var move := test_motion if test_mode else Input.get_vector("move_left", "move_right", "move_up", "move_down")
	set_crouch(test_crouch if test_mode else Input.is_physical_key_pressed(KEY_C))
	if not test_mode and camera != null:
		var world_move := camera.global_basis.x * move.x + Vector3(camera.global_basis.z.x, 0, camera.global_basis.z.z).normalized() * move.y
		move = Vector2(world_move.x, world_move.z)
	var speed := 2.0 if crouched else 4.2
	velocity.x = move.x * speed
	velocity.z = move.y * speed
	velocity.y -= 20 * delta
	move_and_slide()
	if move.length() > 0.1:
		facing = move.normalized()
		gait += delta * speed * 2.8
	if not test_mode and camera != null: update_aim(cursor)
	var view_facing := Vector3(facing.x, 0, facing.y)
	if camera != null: view_facing = view_facing.rotated(Vector3.UP, -camera.rotation.y)
	direction_index = posmod(roundi(atan2(view_facing.x, view_facing.z) / (PI / 6)), 12)
	_refresh_art(posmod(int(gait * 2), 4) if move.length() > 0.1 else 0)
	_update_occlusion()
	if global_position.y < -5: reset_position()

func _refresh_art(step: int) -> void:
	var height := CROUCH_HEIGHT if crouched else STAND_HEIGHT
	for item in [sprite, outline]:
		item.position.y = height * 0.53
		item.scale.y = 0.7 if crouched else 1.0
	sprite.texture = Art.texture(direction_index, step, crouched)
	outline.texture = Art.texture(direction_index, step, crouched, true)

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
	global_position = spawn
	velocity = Vector3.ZERO


func _input(event: InputEvent) -> void:
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
