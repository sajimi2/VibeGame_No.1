extends CharacterBody3D
## 玩家移动与姿态控制；战斗时序由 player_combat 单独处理。
const FrameSpec = preload("res://scripts/art/frame_spec.gd")
@export var art_id := "player"
const STAND_HEIGHT := 1.65
const CROUCH_HEIGHT := 0.95
const WALK_SPEED := 4.2
const RUN_SPEED := 6.8
const JUMP_SPEED := 6.6
var camera: Camera3D
var aim_point := Vector3.ZERO
var cursor := Vector2.ZERO
var shape_node: CollisionShape3D
var crouched := false
var crouch_blend := 0.0
var art_step := -1
var equipment_speed_scale := 1.0
var facing := Vector2(0, 1)
var direction_index := 0
var gait := 0.0
var movement_direction := 0
var shadow: Node3D
var occluded := false
var test_mode := false
var test_motion := Vector2.ZERO
var test_crouch := false
var test_sprint := false
var sprinting := false
var jump_time := 0.0
var jump_frame := -1
var max_hp := 100
var safe_zone := false
var hp := 100
var hurt_time := 0.0
var invulnerable := 0.0
var attack_pose := 0
var attack_arm := -1
var attack_weight := 0
var bow_draw := -1
var attack_facing := Vector2(0,1)
var visual_action := ""
var visual_action_frame := 0
var sprint_blockers: Dictionary = {}
var combat_movement: Callable
var baked_visual: Node3D
var death_art_time := 0.0
var effects: Node3D
var foot_distance := 0.0
var landing_delay := 0.0
var jumped := false
var spawn := Vector3(-6, 0.1, 5)

## 入树后创建胶囊碰撞、离线图集外观和投影；相机与效果系统由关卡注入。
func _ready() -> void:
	cursor = get_viewport().get_mouse_position()
	var listener := AudioListener3D.new()
	listener.position.y = 1.1
	add_child(listener)
	listener.make_current()
	collision_layer = 2
	collision_mask = 1 | 32
	floor_snap_length = 0.35
	floor_constant_speed = true
	floor_max_angle = deg_to_rad(42)
	shape_node = CollisionShape3D.new()
	# 胶囊底部圆滑，避免平底圆柱在坡道凸边卡住。
	# 此形状负责移动碰撞；顶部命中另由命中法线和来袭方向判断。
	var locomotion := CapsuleShape3D.new()
	locomotion.radius = 0.29
	locomotion.height = STAND_HEIGHT
	shape_node.shape = locomotion
	shape_node.position.y = STAND_HEIGHT / 2
	add_child(shape_node)
	shadow = preload("res://scripts/presentation/ground_shadow.gd").new()
	shadow.radius=0.18
	add_child(shadow)
	baked_visual=preload("res://scripts/presentation/baked_human.gd").new()
	baked_visual.name="BakedHuman"
	add_child(baked_visual)
	baked_visual.setup(self,art_id)
	_refresh_art(0)

## 切换胶囊高度；站起前检测头顶净空，受阻则保持下蹲并返回 false。
func set_crouch(value: bool) -> bool:
	if value == crouched: return true
	if not value:
		var query := PhysicsShapeQueryParameters3D.new()
		var standing := CapsuleShape3D.new()
		standing.radius = 0.28
		standing.height = STAND_HEIGHT - 0.04
		query.shape = standing
		query.transform = Transform3D(Basis.IDENTITY, global_position + Vector3.UP * (STAND_HEIGHT / 2 + 0.03))
		query.collision_mask = 1 | 32
		query.exclude = [get_rid()]
		if not get_world_3d().direct_space_state.intersect_shape(query).is_empty(): return false
	crouched = value
	var height := CROUCH_HEIGHT if value else STAND_HEIGHT
	shape_node.shape.height = height
	shape_node.position.y = height / 2
	return true

## 每个固定物理帧依次处理输入、重力、碰撞移动和表现；delta 的单位是秒。
## 移动与攻击独立，实际行走距离驱动步态，避免顶墙时原地跑步。
func _physics_process(delta: float) -> void:
	death_art_time=death_art_time+delta if hp<=0 else 0.0
	hurt_time = maxf(0,hurt_time-delta)
	invulnerable = maxf(0,invulnerable-delta)
	var move := test_motion if test_mode else Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if hp <= 0: move = Vector2.ZERO
	set_crouch(test_crouch if test_mode else Input.is_physical_key_pressed(KEY_C))
	# 碰撞即时响应蹲键，外观用六级关节姿态过渡；站起受阻时仍保持蹲姿。
	crouch_blend = move_toward(crouch_blend, 1.0 if crouched else 0.0, delta / 0.16)
	# 屏幕方向输入转到世界 X/Z 平面，使 WASD 与固定斜角镜头一致。
	if not test_mode and camera != null:
		var world_move := camera.global_basis.x * move.x + Vector3(camera.global_basis.z.x, 0, camera.global_basis.z.z).normalized() * move.y
		move = Vector2(world_move.x, world_move.z)
	# 疾跑只提高站立移动速度；仍允许移动攻击，下蹲和死亡不会带入疾跑速度。
	var run_held := test_sprint if test_mode else Input.is_physical_key_pressed(KEY_SHIFT)
	sprinting = run_held and sprint_blockers.is_empty() and not crouched and hp > 0 and move.length() > 0.1
	var speed := 2.0 if crouched else RUN_SPEED if sprinting else WALK_SPEED
	var combat_move: Dictionary = combat_movement.call(delta) if combat_movement.is_valid() else {}
	speed *= equipment_speed_scale*float(combat_move.get("control",1.0))
	landing_delay=maxf(0,landing_delay-delta)
	# 落地时直接响应输入；跳跃途中减缓水平速度变化，保留起跳惯性。
	if is_on_floor() or not jumped:
		velocity.x = move.x * speed
		velocity.z = move.y * speed
	else:
		velocity.x = move_toward(velocity.x,move.x*speed,delta*3.0)
		velocity.z = move_toward(velocity.z,move.y*speed,delta*3.0)
	velocity.y -= 20 * delta
	# 动作前冲与输入速度合并后仍走 move_and_slide，墙、巨石和坡道照常阻挡。
	var impulse: Vector3 = combat_move.get("velocity",Vector3.ZERO) if hp>0 and is_on_floor() else Vector3.ZERO
	velocity += impulse
	var previous_position := global_position
	var was_airborne := not is_on_floor()
	move_and_slide()
	velocity -= impulse
	if jumped: jump_time += delta
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
		gait += planar_distance / (2.6 if sprinting else 1.8) * TAU
	if not test_mode and camera != null and attack_pose == 0: update_aim(cursor)
	if attack_pose > 0: facing = attack_facing
	var view_facing := Vector3(facing.x, 0, facing.y)
	if camera != null: view_facing = view_facing.rotated(Vector3.UP, -camera.rotation.y)
	direction_index = posmod(roundi(atan2(view_facing.x, view_facing.z) / (PI / 6)), 12)
	var walk_direction := Vector3(move.x, 0, move.y)
	if camera != null: walk_direction = walk_direction.rotated(Vector3.UP, -camera.rotation.y)
	movement_direction = posmod(roundi(atan2(walk_direction.x, walk_direction.z) / (PI / 6)), 12)
	# 跳跃由真实垂直速度分段，顶头或提前落地也能正确切到下落/缓冲帧。
	jump_frame = -1
	if not is_on_floor():
		jump_frame = 0 if jumped and jump_time < 0.075 and velocity.y > 0 else 1 if velocity.y > 1.8 else 2 if velocity.y > -1.5 else 3
	elif landing_delay > 0: jump_frame = 4
	_refresh_art(posmod(int(gait / TAU * 8), 8) if move.length()>0.1 and planar_distance > 0.002 and is_on_floor() else -1)
	_update_occlusion()
	if global_position.y < -5: reset_position()

## 按朝向、步态和攻击姿态选择纹理，使本体与遮挡轮廓同步。
func _refresh_art(step: int) -> void:
	art_step = step
	var crouch_frame := roundi(crouch_blend * FrameSpec.CROUCH_FRAMES)
	var running := sprinting and step >= 0
	var state := FrameSpec.character(direction_index,step,crouched,movement_direction,attack_pose,attack_arm,attack_weight,bow_draw,crouch_frame,running,jump_frame)
	state = FrameSpec.with_action(state,visual_action,visual_action_frame)
	if hp<=0: state=FrameSpec.with_action(FrameSpec.character(direction_index,-1,false),"death_fall",clampi(roundi(death_art_time/.85*32),0,32))
	if is_instance_valid(baked_visual):
		baked_visual.tint=Color(0.72,0.70,0.68) if hp<=0 else Color(1.8,.8,.7) if hurt_time>0 else Color.WHITE
	baked_visual.apply_frame(state)

## 限制按来源独立登记；换回轻武器只解除装备限制，不能误解除将来技能/状态的限制。
func set_sprint_block(source: StringName, blocked: bool) -> void:
	if blocked: sprint_blockers[source] = true
	else: sprint_blockers.erase(source)
	if not sprint_blockers.is_empty(): sprinting = false

## 敌方箭共用身体附着接口；根节点不旋转，因此用实际身体朝向提供独立坐标系。
func projectile_attachment_frame(_region: String) -> Transform3D:
	return Transform3D(Basis(Vector3.UP,atan2(facing.x,facing.y)),global_position)

## 只修正纸片的视觉嵌入深度，不改变敌方箭的真实命中点或伤害。
func projectile_attachment_point(_region: String, point: Vector3, _incoming: Vector3) -> Vector3:
	return preload("res://scripts/combat/impact_attachment.gd").body_point(global_position,point)

func projectile_anchor_alive() -> bool:
	return hp > 0

## 插在玩家身上的箭短暂停留后淡出；敌人未提供该策略时继续保留至死亡。
func projectile_attachment_duration() -> float:
	return 4.0

## 从相机向角色发射射线；被实体或树冠遮挡时显示轮廓。
func _update_occlusion() -> void:
	if camera == null: return
	var target := global_position + Vector3.UP * (0.5 if crouched else 0.95)
	var screen := camera.unproject_position(target)
	var origin := camera.project_ray_origin(screen)
	var query := PhysicsRayQueryParameters3D.create(origin, target, 1 | 4)
	query.exclude = [get_rid()]
	occluded = not get_world_3d().direct_space_state.intersect_ray(query).is_empty()
	baked_visual.set_occluded(occluded)

## 初始化或掉出地图时回到出生点，恢复生命并清除移动、跳跃状态。
func reset_position() -> void:
	hp = max_hp
	invulnerable = 0
	global_position = spawn
	velocity = Vector3.ZERO
	jumped=false
	landing_delay=0
	jump_time=0
	jump_frame=-1
	sprinting=false


## 记录鼠标位置并响应跳跃；攻击按键由 player_combat 处理。
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==KEY_SPACE: request_jump()
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		cursor = event.position

## 把屏幕鼠标坐标投射到世界，优先瞄准实际碰撞点；未命中时使用角色附近的水平面。
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

## 统一处理玩家扣血；死亡、受击无敌期及营地安全区内忽略伤害。
func receive_damage(amount: int, _direction: Vector3) -> void:
	if hp <= 0 or invulnerable > 0 or safe_zone: return
	hp = maxi(0,hp-amount)
	hurt_time = 0.18
	invulnerable = 0.65
	if is_instance_valid(effects): effects.impact(global_position+Vector3.UP,amount,hp==0)

## 仅允许存活、站立且落地的角色起跳；返回是否成功，防止空中连跳。
func request_jump() -> bool:
	if hp<=0 or crouched or not is_on_floor() or jumped or landing_delay>0: return false
	velocity.y=JUMP_SPEED
	jumped=true
	jump_time=0
	if is_instance_valid(effects): effects.sound("step",global_position)
	return true
