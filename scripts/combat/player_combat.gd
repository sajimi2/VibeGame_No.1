extends Node3D
## 玩家攻击控制器：把输入转换为动作时序、射线命中和投射物。
const Trace = preload("res://scripts/combat/space_trace.gd")
const Motion = preload("res://scripts/combat/motion.gd")
const WeaponArt = preload("res://scripts/presentation/weapon_art.gd")
const PixelWeapon = preload("res://scripts/presentation/pixel_weapon.gd")
var sunlight: DirectionalLight3D
const Arrow = preload("res://scripts/combat/arrow.gd")
const Actions = preload("res://scripts/combat/action_library.gd")
const Accuracy = preload("res://scripts/combat/bow_accuracy.gd")
var weapon_profile: TacticalWeaponData
var attack_action: Resource
var attack_index := 0
var dust: Node3D
var last_drag_point := Vector3.ZERO
var bow_rng := RandomNumberGenerator.new()
var last_spread := 0.0
var impact_emitted := false
var actor: CharacterBody3D
var notify: Callable
var cooldown := 0.0
var swing_time := 0.0
var previous_angle := rad_to_deg(-0.9)
var pending_arrow: Node3D
var bow_target := Vector3.ZERO
var queued_action := 0
var queued_point := Vector3.ZERO
var buffer_time := 0.0
var struck: Dictionary = {}
var locked_direction := Vector3.FORWARD
var weapon: MeshInstance3D
var bow: MeshInstance3D
var bow_time := 0.0
var hand: Node3D
var arrows: Node3D
var melee_hits := 0
var trail: MeshInstance3D
var melee_range := 1.9
var melee_damage := 20
var attack_duration := 0.3
var attack_interval := 0.38
var assist_target: Node3D
var assist_enabled := true
var assist_marker: MeshInstance3D

## 接收玩家和反馈回调，创建手持武器、箭容器、辅助瞄准标记与刀光。
func setup(body: CharacterBody3D, callback: Callable) -> void:
	actor = body
	actor.combat_movement = movement_sample
	bow_rng.randomize()
	notify = callback
	hand = Node3D.new()
	actor.add_child(hand)
	weapon = WeaponArt.melee_model("knife")
	hand.add_child(weapon)
	bow = preload("res://scripts/presentation/weapon_art.gd").bow()
	bow.hide()
	hand.add_child(bow)
	PixelWeapon.attach(bow,actor.camera,sunlight)
	arrows = Node3D.new()
	arrows.name = "Arrows"
	get_parent().add_child(arrows)
	assist_marker=MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius=0.44
	ring.outer_radius=0.50
	ring.rings=32
	ring.ring_segments=6
	assist_marker.mesh=ring
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.albedo_color=Color("ffe4a0")
	assist_marker.material_override=ring_mat
	assist_marker.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	assist_marker.visible=false
	add_child(assist_marker)
	trail=preload("res://scripts/presentation/swing_trail.gd").new()
	add_child(trail)
	dust = preload("res://scripts/presentation/drag_dust.gd").new()
	add_child(dust)
	apply_weapon(preload("res://data/weapons/knife.tres"))
	process_physics_priority = 5

## 返回当前姿态下的世界攻击起点，下蹲时同步降低出刀和发箭高度。
func muzzle() -> Vector3:
	return actor.global_position + Vector3.UP * (0.68 if actor.crouched else 1.15)

## 接收未被界面消费的攻击点击；收招末段允许缓存下一次动作。
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		actor.update_aim(event.position)
		var action := 1 if event.button_index==MOUSE_BUTTON_LEFT else 2 if event.button_index==MOUSE_BUTTON_RIGHT else 0
		if action==0: return
		var point: Vector3 = actor.aim_point if action==1 else assisted_point(actor.aim_point,actor.cursor)
		if cooldown>0 and cooldown<=0.12:
			queued_action=action
			queued_point=point
			buffer_time=0.16
		elif action==1: attack(point)
		else: shoot(point)

## 检查能否出刀，锁定本次方向并启动时序；实际命中由后续物理帧结算。
func attack(point: Vector3) -> bool:
	if get_tree().paused: return false
	if cooldown > 0 or actor.hp<=0: return false
	var sequence := weapon_profile.attack_sequence
	attack_action = Actions.get_action(sequence[attack_index%sequence.size()] if not sequence.is_empty() else "light_rise")
	if attack_action == null: return false
	attack_index += 1
	impact_emitted = false
	locked_direction = (point - muzzle()).normalized()
	if locked_direction.length() < 0.1: locked_direction = Vector3(actor.facing.x, 0, actor.facing.y)
	cooldown = attack_interval
	swing_time = attack_duration
	actor.attack_facing = Vector2(locked_direction.x,locked_direction.z).normalized()
	actor.effects.sound("swing",actor.global_position)
	previous_angle = rad_to_deg(attack_action.sweep_from)
	struck.clear()
	return true

## 锁定目标并创建暂不运动的箭，等拉弓前摇结束后才放行。
func shoot(point: Vector3):
	if get_tree().paused or cooldown > 0 or actor.hp<=0: return null
	cooldown = 0.45
	bow_time = 0.45
	bow_target=point
	locked_direction=(point-muzzle()).normalized()
	actor.attack_facing=Vector2(locked_direction.x,locked_direction.z).normalized()
	var arrow := Arrow.new()
	arrow.process_mode=Node.PROCESS_MODE_DISABLED
	arrow.visible=false
	arrows.add_child(arrow)
	arrow.global_position=muzzle()
	arrow.notify=notify
	pending_arrow=arrow
	return arrow

## 推进冷却和动作时间，消费输入缓存，并让姿态、武器和命中窗口同步。
## 死亡会取消尚未放出的箭和排队动作。
func _physics_process(delta: float) -> void:
	if actor.hp<=0:
		if is_instance_valid(pending_arrow): pending_arrow.queue_free()
		pending_arrow=null
		queued_action=0
		swing_time=0
		bow_time=0
	if not actor.test_mode:
		assisted_point(actor.aim_point,actor.cursor)
		assist_marker.visible=is_instance_valid(assist_target) and actor.hp>0
		if assist_marker.visible: assist_marker.global_position=assist_target.global_position+Vector3.UP*0.04
	cooldown=maxf(0,cooldown-delta)
	buffer_time=maxf(0,buffer_time-delta)
	# 先清空缓存再执行，避免同一点击跨多个物理帧重复触发。
	if queued_action!=0 and cooldown<=0 and buffer_time>0:
		var action := queued_action
		queued_action=0
		if action==1: attack(queued_point)
		else: shoot(queued_point)
	if buffer_time<=0: queued_action=0
	swing_time=maxf(0,swing_time-delta)
	bow_time=maxf(0,bow_time-delta)
	actor.attack_arm=-1
	actor.attack_weight=0
	actor.bow_draw=-1
	actor.attack_pose=0
	actor.visual_action = weapon_profile.idle_action
	actor.visual_action_frame = 0
	hand.global_position=muzzle()
	var direction := locked_direction if swing_time>0 or bow_time>0 else Vector3(actor.facing.x,0,actor.facing.y)
	if direction.cross(Vector3.UP).length()>0.01:
		var desired := Basis.looking_at(direction.normalized(),Vector3.UP)
		if swing_time>0 or bow_time>0: hand.global_basis=desired
		else:
			var current := hand.global_basis.orthonormalized()
			var angle := current.get_rotation_quaternion().angle_to(desired.get_rotation_quaternion())
			hand.global_basis=current.slerp(desired,minf(1.0,14.0*delta/maxf(angle,0.001)))
	bow.visible=bow_time>0
	weapon.visible=bow_time<=0
	if swing_time>0:
		var elapsed := attack_duration-swing_time
		var phase := elapsed/attack_duration
		actor.attack_pose=1 if phase<attack_action.windup_end else 2 if phase<attack_action.active_end else 3
		actor.visual_action = attack_action.id
		actor.visual_action_frame = roundi(phase*32)
		# 命中扫描和身体/刀刃共享同一动作窗口；每次攻击的去重集合仍只结算一次。
		if phase>=attack_action.windup_end and previous_angle<rad_to_deg(attack_action.sweep_to):
			var fraction := clampf((phase-attack_action.windup_end)/(attack_action.active_end-attack_action.windup_end),0,1)
			var angle := rad_to_deg(lerpf(attack_action.sweep_from,attack_action.sweep_to,Motion.blend(fraction)))
			strike(previous_angle,angle)
			previous_angle=angle
	elif bow_time>0:
		actor.visual_action = ""
		actor.attack_pose=4
		var elapsed := 0.45-bow_time
		var draw := Motion.blend(elapsed/0.14) if elapsed<0.14 else 1.0-Motion.blend((elapsed-0.14)/0.075)
		actor.bow_draw=roundi(draw*8)
		actor.attack_weight=roundi(-draw)
		WeaponArt.set_bow_draw(bow,draw,elapsed<0.14)
		if is_instance_valid(pending_arrow):
			pending_arrow.global_position=muzzle()
			# 拉弓前摇结束后才启动飞行，出生位置取玩家此刻的手部位置。
			if elapsed>=0.14:
				last_spread = Accuracy.spread_degrees(actor.crouched,Vector2(actor.velocity.x,actor.velocity.z).length()>0.2,not actor.is_on_floor())
				pending_arrow.velocity=Accuracy.deviate(Trace.launch_velocity(muzzle(),bow_target),last_spread,bow_rng)
				pending_arrow.process_mode=Node.PROCESS_MODE_INHERIT
				pending_arrow.visible=true
				pending_arrow=null
				actor.effects.sound("bow",actor.global_position)

	# 战斗在玩家移动后更新；同帧刷新上肢与握点，避免武器领先纸片一帧。
	var view := Vector3(actor.facing.x, 0, actor.facing.y).rotated(Vector3.UP, -actor.camera.rotation.y)
	if swing_time > 0 or bow_time > 0:
		view = locked_direction.rotated(Vector3.UP, -actor.camera.rotation.y)
	actor.direction_index = posmod(roundi(atan2(view.x, view.z) / (PI / 6)), 12)
	actor._refresh_art(actor.art_step)
	hand.global_position = actor.baked_visual.last_grip
	var idle_visual := Actions.get_action(weapon_profile.idle_action)
	var visual: Resource = attack_action if swing_time>0 else idle_visual
	var phase := (attack_duration-swing_time)/attack_duration if swing_time>0 else 0.0
	if visual != null: weapon.rotation = visual.sample(phase).blade
	if idle_visual != null and idle_visual.ground_drag and bow_time<=0:
		align_drag(phase)
	if swing_time>0 and attack_action.ground_impact:
		align_impact(phase)
	var active: bool = swing_time>0 and attack_action!=null and phase>=attack_action.windup_end and phase<attack_action.active_end
	trail.sample_blade(active,weapon.to_global(weapon.get_meta("blade_base",Vector3(0,0,-0.24))),weapon.to_global(weapon.get_meta("blade_tip",Vector3(0,0,-1.7))))

## 重击末端把刀尖贴到真实落点；不改身体关键姿态，空中或隔墙不凭空冒尘。
func align_impact(phase: float) -> void:
	if phase<attack_action.windup_end or phase>0.86 or not actor.is_on_floor(): return
	var forward := Vector3(locked_direction.x,0,locked_direction.z).normalized()
	var tip: Vector3 = weapon.get_meta("blade_tip")
	var length := (tip*weapon.scale).length()
	var height: float = hand.global_position.y-actor.global_position.y
	if absf(height)>=length: return
	var point := hand.global_position+forward*sqrt(length*length-height*height)
	var query := PhysicsRayQueryParameters3D.create(point+Vector3.UP,point+Vector3.DOWN*3.0,1|32,[actor.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or hit.normal.y<0.65 or absf(hit.position.y-actor.global_position.y)>0.6: return
	var target: Vector3 = hit.position+Vector3.UP*0.03
	query.from = hand.global_position
	query.to = target+Vector3.UP*0.03
	if not get_world_3d().direct_space_state.intersect_ray(query).is_empty(): return
	var goal := Basis.looking_at(hand.global_basis.inverse()*(target-hand.global_position).normalized(),Vector3.UP).get_rotation_quaternion()
	var impact: float = attack_action.active_end
	var blend := smoothstep(maxf(attack_action.windup_end,impact-0.04),impact,phase) if phase<impact else 1.0-smoothstep(impact,0.86,phase)
	if phase>=impact and not impact_emitted: blend = 1
	weapon.quaternion = weapon.quaternion.slerp(goal,blend)
	if phase>=impact and not impact_emitted:
		impact_emitted = true
		dust.burst(target,forward)

## 玩家在同帧移动前查询下一步动作曲线；战斗不直接移动角色，前冲不会绕过碰撞。
func movement_sample(delta: float) -> Dictionary:
	if swing_time<=0 or attack_action==null or actor.hp<=0: return {}
	var phase := clampf((attack_duration-swing_time+delta)/attack_duration,0,1)
	var forward := Vector3(locked_direction.x,0,locked_direction.z).normalized()
	return {"control":attack_action.control_scale,"velocity":forward*attack_action.forward_speed(phase)}

## 刀尖长度与手心高度解出拖地角；坡道重新采样地面，离地/站定/挥刀时不产生尘土。
func align_drag(phase: float) -> void:
	var tip: Vector3 = weapon.get_meta("blade_tip",Vector3(0,0,-1.7))
	var length := (tip*weapon.scale).length()
	var backward := Vector3(actor.facing.x,0,actor.facing.y).normalized()*-1
	var height: float = hand.global_position.y-actor.global_position.y
	var ground := {}
	var target := hand.global_position
	for i in 2:
		var distance := sqrt(maxf(0.01,length*length-height*height))
		var point := hand.global_position+backward*distance
		var query := PhysicsRayQueryParameters3D.create(point+Vector3.UP,point+Vector3.DOWN*3.5,1|32,[actor.get_rid()])
		ground = get_world_3d().direct_space_state.intersect_ray(query)
		if ground.is_empty() or ground.normal.y<0.65: return
		target = ground.position+Vector3.UP*0.02
		height = hand.global_position.y-target.y
	if absf(height)>=length: return
	var local := hand.global_basis.inverse()*(target-hand.global_position).normalized()
	var goal := Basis.looking_at(local,Vector3.UP).get_rotation_quaternion()
	var blend := 1.0 if swing_time<=0 else 1.0-smoothstep(0.0,0.15,phase) if phase<0.15 else smoothstep(0.88,1.0,phase)
	weapon.quaternion = weapon.quaternion.slerp(goal,blend)
	var contact := weapon.to_global(tip)
	if swing_time<=0 and actor.is_on_floor() and actor.get_real_velocity().length()>0.2 and absf(contact.y-target.y)<0.065:
		if contact.distance_to(last_drag_point)>0.14: dust.contact(target); last_drag_point=contact

## 在前后两次刀刃角度间补采样射线，防止挥刀过快漏判。
## struck 按实例 ID 去重，使同一挥刀对每个目标或布帘只生效一次。
func strike(from_angle: float, to_angle: float) -> void:
	var samples := maxi(1, ceili(absf(to_angle - from_angle) / 3))
	for sample in samples + 1:
		var angle := lerpf(from_angle, to_angle, float(sample) / samples)
		var direction := locked_direction.rotated(Vector3.UP, deg_to_rad(angle))
		var hit := Trace.trace(get_world_3d(), muzzle(), muzzle() + direction * melee_range)
		for cloth in hit.get("penetrated", []):
			if not struck.has(cloth.get_instance_id()):
				struck[cloth.get_instance_id()] = true
				Trace.apply_cloth(cloth)
		if not hit.has("collider"): continue
		var target: Object = hit.collider
		if struck.has(target.get_instance_id()): continue
		struck[target.get_instance_id()] = true
		if target.has_method("receive_strike"):
			melee_hits += 1
			var region: String = target.receive_strike(hit.position, hit.normal, direction, melee_damage) if target.is_in_group("tactical_enemies") else target.receive_strike(hit.position, hit.normal, direction)
			if notify.is_valid(): notify.call("近战命中：" + region)

## 在光标附近选择可见且射线可达的敌人，返回轻微修正后的目标点；Ctrl 临时关闭辅助。
func assisted_point(raw: Vector3, cursor: Vector2) -> Vector3:
	assist_target=null
	if not assist_enabled or actor.camera==null or Input.is_physical_key_pressed(KEY_CTRL): return raw
	var best := 26.0
	var result := raw
	for enemy in get_tree().get_nodes_in_group("tactical_enemies"):
		if enemy.hp<=0: continue
		var target: Vector3=enemy.global_position+Vector3.UP*1.0
		if actor.camera.is_position_behind(target) or muzzle().distance_to(target)>16: continue
		var distance: float=actor.camera.unproject_position(target).distance_to(cursor)
		if distance>=best: continue
		var excluded: Array[RID]=[actor.get_rid(),enemy.get_rid()]
		var origin: Vector3=actor.camera.project_ray_origin(actor.camera.unproject_position(target))
		var sight := PhysicsRayQueryParameters3D.create(origin,target,1|4,excluded)
		if not get_world_3d().direct_space_state.intersect_ray(sight).is_empty(): continue
		sight.from=muzzle()
		if not get_world_3d().direct_space_state.intersect_ray(sight).is_empty(): continue
		# 保留鼠标直接瞄准顶部的结果；只修正偏离身体的小幅误差。
		var raw_ray := PhysicsRayQueryParameters3D.create(actor.camera.project_ray_origin(cursor),actor.camera.project_ray_origin(cursor)+actor.camera.project_ray_normal(cursor)*100,1|4|16,[actor.get_rid()])
		var under_cursor := get_world_3d().direct_space_state.intersect_ray(raw_ray)
		if under_cursor.get("collider")==enemy:
			assist_target=enemy
			return raw
		best=distance
		result=target
		assist_target=enemy
	return result

## 应用武器资源中的距离、伤害、时序和模型比例；成长模块通过此接口换装。
func apply_weapon(profile: TacticalWeaponData) -> void:
	actor.set_sprint_block(&"equipped_weapon",not profile.allows_sprint())
	actor.equipment_speed_scale = profile.movement_scale()
	if weapon_profile == profile: return
	weapon_profile = profile
	swing_time = 0
	attack_index = 0
	actor.visual_action = profile.idle_action
	actor.visual_action_frame = 0
	weapon.hide()
	weapon.queue_free()
	weapon = WeaponArt.melee_model(profile.model_id)
	hand.add_child(weapon)
	melee_range = profile.reach
	melee_damage = profile.damage
	attack_duration = profile.duration
	attack_interval = profile.interval
	weapon.scale = profile.visual_scale
	PixelWeapon.attach(weapon,actor.camera,sunlight)
