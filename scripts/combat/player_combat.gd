extends Node3D
const Trace = preload("res://scripts/combat/space_trace.gd")
const Motion = preload("res://scripts/combat/motion.gd")
const WeaponArt = preload("res://scripts/presentation/weapon_art.gd")
const Arrow = preload("res://scripts/combat/arrow.gd")
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

func setup(body: CharacterBody3D, callback: Callable) -> void:
	actor = body
	notify = callback
	hand = Node3D.new()
	actor.add_child(hand)
	weapon = preload("res://scripts/presentation/weapon_art.gd").sword()
	hand.add_child(weapon)
	bow = preload("res://scripts/presentation/weapon_art.gd").bow()
	bow.hide()
	hand.add_child(bow)
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
	process_physics_priority = 5

func muzzle() -> Vector3:
	return actor.global_position + Vector3.UP * (0.68 if actor.crouched else 1.15)

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

func attack(point: Vector3) -> bool:
	if get_tree().paused: return false
	if cooldown > 0 or actor.hp<=0: return false
	locked_direction = (point - muzzle()).normalized()
	if locked_direction.length() < 0.1: locked_direction = Vector3(actor.facing.x, 0, actor.facing.y)
	cooldown = attack_interval
	swing_time = attack_duration
	actor.attack_facing = Vector2(locked_direction.x,locked_direction.z).normalized()
	actor.effects.sound("swing",actor.global_position)
	previous_angle = rad_to_deg(-0.9)
	struck.clear()
	return true

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
		var windup := attack_duration*0.25
		var active := attack_duration*0.36
		var motion := Motion.melee(elapsed,windup,active,attack_duration)
		actor.attack_pose=1 if elapsed<windup else 2 if elapsed<windup+active else 3
		actor.attack_arm=motion.arm
		actor.attack_weight=motion.weight
		hand.rotate_object_local(Vector3.UP,motion.angle)
		hand.translate_object_local(Vector3(0,0,-motion.extension))
		if elapsed>=windup and previous_angle<rad_to_deg(0.8):
			var angle := rad_to_deg(motion.angle) if elapsed<windup+active else rad_to_deg(0.8)
			strike(previous_angle,angle)
			previous_angle=angle
	elif bow_time>0:
		actor.attack_pose=4
		var elapsed := 0.45-bow_time
		var draw := Motion.blend(elapsed/0.14) if elapsed<0.14 else 1.0-Motion.blend((elapsed-0.14)/0.075)
		actor.bow_draw=roundi(draw*8)
		actor.attack_weight=roundi(-draw)
		WeaponArt.set_bow_draw(bow,draw,elapsed<0.14)
		if is_instance_valid(pending_arrow):
			pending_arrow.global_position=muzzle()
			if elapsed>=0.14:
				pending_arrow.velocity=Trace.launch_velocity(muzzle(),bow_target)
				pending_arrow.process_mode=Node.PROCESS_MODE_INHERIT
				pending_arrow.visible=true
				pending_arrow=null
				actor.effects.sound("bow",actor.global_position)

	var active := swing_time>attack_duration*0.39 and swing_time<attack_duration*0.75
	var blade_direction := -hand.global_basis.z
	trail.sample_blade(active,muzzle()+blade_direction*melee_range*0.76,muzzle()+blade_direction*melee_range)

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

func assisted_point(raw: Vector3, cursor: Vector2) -> Vector3:
	assist_target=null
	if not assist_enabled or actor.camera==null or Input.is_physical_key_pressed(KEY_SHIFT): return raw
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
		# Keep deliberate head/top shots; assist only small misses outside the body.
		var raw_ray := PhysicsRayQueryParameters3D.create(actor.camera.project_ray_origin(cursor),actor.camera.project_ray_origin(cursor)+actor.camera.project_ray_normal(cursor)*100,1|4|16,[actor.get_rid()])
		var under_cursor := get_world_3d().direct_space_state.intersect_ray(raw_ray)
		if under_cursor.get("collider")==enemy:
			assist_target=enemy
			return raw
		best=distance
		result=target
		assist_target=enemy
	return result

func apply_weapon(profile: TacticalWeaponData) -> void:
	melee_range = profile.reach
	melee_damage = profile.damage
	attack_duration = profile.duration
	attack_interval = profile.interval
	weapon.scale = profile.visual_scale
