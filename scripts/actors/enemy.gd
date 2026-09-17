extends CharacterBody3D
const Motion = preload("res://scripts/combat/motion.gd")
const WeaponArt = preload("res://scripts/presentation/weapon_art.gd")
const Art = preload("res://scripts/presentation/directional_art.gd")
var player: CharacterBody3D
var camera: Camera3D
var routes: Node
var effects: Node3D
var home := Vector3(2,0,-0.5)
var hp := 60
var max_hp := 60
var ranged := false
var attack_cycle := 0
var action_duration := 0.32
var recovery_duration := 0.75
var strike_pending := false
var thrust := false
var volley_left := 0
var block_flash := 0.0
var hurt_recovery := false
var reaction_angle := 0.0
var motion_angle := 0.0
var draw_from := 0.0
var health_bar: Sprite3D
var locked_target := Vector3.ZERO
var retreat_goal := Vector3.ZERO
var retreat_timer := 0.0
var state := "guard"
var last_seen := Vector3.ZERO
var facing := Vector3(0,0,1)
var target_visible := false
var lost_time := 10.0
var sight_grace := 0.75
var route := PackedVector3Array()
var route_index := 0
var repath := 0.0
var search_time := 0.0
var attack_time := 0.0
var cooldown := 0.0
var hurt := 0.0
var gait := 0.0
var clock := 0.0
var knockback := Vector3.ZERO
var locked_direction := Vector3.FORWARD
var world_shadow: MeshInstance3D
var outline: Sprite3D
var occluded := false
var sprite: Sprite3D
var sword: Node3D
var shield_node: Node3D
var trail: MeshInstance3D
var marker: Label3D
var ai_enabled := true
var navigation_excluded: Array[RID] = []
func _ready() -> void:
	name = "OutpostGuard"
	add_to_group("tactical_enemies")
	navigation_excluded.append(get_rid())
	collision_layer = 1|16
	collision_mask = 1|2
	floor_snap_length = 0.35
	floor_constant_speed = true
	floor_max_angle = deg_to_rad(42)
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.height = 1.65
	capsule.radius = 0.29
	shape.shape = capsule
	shape.position.y = 0.825
	add_child(shape)
	sprite = Sprite3D.new()
	sprite.texture = Art.texture(0,-1,false,false,0,0,true)
	sprite.pixel_size = 0.04
	sprite.offset = Vector2(0,24)
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sprite)
	outline = sprite.duplicate()
	outline.no_depth_test = true
	outline.render_priority = 10
	outline.modulate = Color("f1a36e")
	outline.visible = false
	add_child(outline)
	world_shadow=preload("res://scripts/presentation/world_lighting.gd").actor_shadow(self)
	marker = Label3D.new()
	marker.position.y = 2.45
	marker.pixel_size = 0.015
	marker.font_size = 28
	marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(marker)
	sword = Node3D.new()
	add_child(sword)
	var held: MeshInstance3D = preload("res://scripts/presentation/weapon_art.gd").bow() if ranged else preload("res://scripts/presentation/weapon_art.gd").sword()
	sword.add_child(held)
	if not ranged:
		var shield=preload("res://scripts/presentation/weapon_art.gd")
		shield_node=Node3D.new()
		add_child(shield_node)
		shield.block(shield_node,Vector3(0.48,0.65,0.11),Vector3(0.36,-0.12,-0.25),"596f72")
		shield.block(shield_node,Vector3(0.50,0.07,0.13),Vector3(0.36,-0.12,-0.25),"c3a873")
	trail=preload("res://scripts/presentation/swing_trail.gd").new()
	add_child(trail)
	health_bar=preload("res://scripts/presentation/enemy_health.gd").new()
	add_child(health_bar)
	health_bar.set_health(hp,max_hp)
func can_see_target() -> bool:
	if player.hp<=0 or player.safe_zone: return false
	var eye := global_position+Vector3.UP*1.4
	var target := player.global_position+Vector3.UP*(0.65 if player.crouched else 1.2)
	var offset := target-eye
	if offset.length()>sight_range(): return false
	var planar := Vector3(offset.x,0,offset.z)
	var close_awareness := planar.length()<2.8 and lost_time<2.0 and state not in ["guard","return"]
	if not close_awareness and planar.length()>0.1 and facing.dot(planar.normalized())<0.42: return false
	# Head and torso samples prevent a nearby ledge from hiding the entire actor.
	for height in ([0.65] if player.crouched else [1.5,1.1]):
		var ray := PhysicsRayQueryParameters3D.create(eye,player.global_position+Vector3.UP*height,1|4,[get_rid()])
		if get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): return true
	return false
func _physics_process(delta: float) -> void:
	if not ai_enabled: return
	clock+=delta
	cooldown=maxf(0,cooldown-delta)
	hurt=maxf(0,hurt-delta)
	block_flash=maxf(0,block_flash-delta)
	health_bar.set_health(hp,max_hp)
	if hp<=0:
		sword.hide()
		trail.hide()
		if is_instance_valid(shield_node): shield_node.hide()
		world_shadow.hide()
		outline.hide()
		marker.text=""
		sprite.rotation.z=-PI*0.45
		sprite.modulate=Color(0.6,0.6,0.6,0.6)
		return
	var before := global_position
	update_senses(delta)
	var move := choose_movement(delta)
	if move.length()>0.1:
		facing=(Vector3(last_seen.x,global_position.y,last_seen.z)-global_position).normalized() if ranged and target_visible else move
	var committed_step := Vector3.ZERO
	if not ranged and state=="recover" and not hurt_recovery:
		var active_time := recovery_duration-attack_time
		if active_time<0.18:
			committed_step=Vector3(locked_direction.x,0,locked_direction.z).normalized()*sin(active_time/0.18*PI)*(1.8 if thrust else 1.0)
	velocity=committed_step+move*(2.75 if state=="chase" else 1.8)+knockback+Vector3.UP*(velocity.y-20*delta)
	knockback=knockback.move_toward(Vector3.ZERO,delta*14)
	move_and_slide()
	var travel := Vector2(position.x-before.x,position.z-before.z).length()
	gait+=travel/1.8*TAU
	update_visuals(travel)

func update_visuals(travel: float) -> void:
	var view := facing.rotated(Vector3.UP,-camera.rotation.y)
	var direction := posmod(roundi(atan2(view.x,view.z)/(PI/6)),12)
	var pose := 4 if ranged and state in ["windup","nock","recover"] else 1 if state=="windup" else 3 if state=="recover" else 0
	var step := posmod(int(gait/TAU*8),8) if travel>0.002 else -1
	var motion := {"angle":0.0,"arm":-1,"weight":0,"extension":0.0}
	var draw_phase := -1
	if not ranged and state in ["windup","recover"]:
		if hurt_recovery:
			motion.angle=lerpf(reaction_angle,0,Motion.blend(1-attack_time/0.35))
			motion.arm=clampi(roundi((motion.angle+0.9)/1.7*24),0,24)
			motion.weight=-1 if attack_time>0.15 else 0
		else:
			var elapsed := action_duration-attack_time if state=="windup" else action_duration+recovery_duration-attack_time
			motion=Motion.melee(elapsed,action_duration,0.16,recovery_duration+action_duration,thrust)
	if ranged:
		var draw := 0.0
		var nocked := state=="windup"
		if state=="windup": draw=lerpf(draw_from,1.0,Motion.blend(1-attack_time/action_duration))
		elif state=="nock":
			var elapsed := 0.65-attack_time
			draw=1.0-Motion.blend(elapsed/0.075) if elapsed<0.075 else 0.35*Motion.blend((elapsed-0.12)/0.53)
			nocked=elapsed>0.12
		elif state=="recover" and not hurt_recovery: draw=1.0-Motion.blend((recovery_duration-attack_time)/0.075)
		WeaponArt.set_bow_draw(sword.get_child(0),draw,nocked)
		draw_phase=roundi(draw*8)
	motion_angle=motion.angle
	sprite.texture=Art.texture(direction,step,false,false,direction,pose,true,motion.arm,motion.weight,draw_phase)
	outline.texture=Art.texture(direction,step,false,true,direction,pose,true,motion.arm,motion.weight,draw_phase)
	update_occlusion()
	sprite.modulate=Color(1.8,1.5,1.2) if hurt>0 else Color("bbd1b5") if ranged else Color.WHITE
	marker.text={"guard":"弓箭手" if ranged else "守卫","chase":"!","windup":"瞄准！" if ranged else "突刺！" if thrust else "横斩！","nock":"搭箭…","recover":"收招 · 破绽","investigate":"? 调查","search":"? 搜索","return":"返回"}.get(state,state)
	if block_flash>0: marker.text="格挡 · 绕侧/等收招"
	marker.modulate=Color("f1a36e") if state=="windup" else Color("e5d5ac")
	if is_instance_valid(shield_node):
		shield_node.position=Vector3(0,1.1,0)
		shield_node.look_at(global_position+Vector3.UP*1.1+facing)
	sword.position=Vector3(0,1.1,0)
	if facing.length()>0.01: sword.look_at(global_position+Vector3.UP*1.1+facing)
	if not ranged:
		sword.rotate_object_local(Vector3.UP,motion.angle)
		sword.translate_object_local(Vector3(0,0,-motion.extension))
	var active := not ranged and state=="recover" and not hurt_recovery and recovery_duration-attack_time<0.16
	var reach := 2.55 if thrust else 1.85
	var blade_direction := -sword.global_basis.z
	trail.sample_blade(active,sword.global_position+blade_direction*reach*0.78,sword.global_position+blade_direction*reach)
func perform_attack() -> void:
	if ranged:
		# Fire at the committed aim point, not the player's new hidden position.
		var arrow := preload("res://scripts/combat/arrow.gd").new()
		arrow.hostile=true
		arrow.hit_mask=1|2|8|16
		arrow.pierced.append(get_rid())
		get_parent().add_child(arrow)
		arrow.global_position=global_position+Vector3.UP*1.15
		arrow.velocity=preload("res://scripts/combat/space_trace.gd").launch_velocity(arrow.global_position,locked_target,14)
		effects.sound("bow",global_position)
		return
	effects.sound("swing",global_position)
	var start := global_position+Vector3.UP*1.1
	for angle in ([-0.04,0.0,0.04] if thrust else [-0.28,-0.14,0.0,0.14,0.28]):
		var ray := PhysicsRayQueryParameters3D.create(start,start+locked_direction.rotated(Vector3.UP,angle)*(2.55 if thrust else 1.85),1|2|8,[get_rid()])
		var hit := get_world_3d().direct_space_state.intersect_ray(ray)
		if not hit.is_empty() and hit.collider==player:
			player.receive_damage(25 if thrust else 20,locked_direction)
			break
func receive_strike(_point: Vector3, normal: Vector3, incoming: Vector3, base_damage: int = 20) -> String:
	if hp<=0: return "已倒下"
	var top := normal.y>0.65 and incoming.y<-0.05
	var toward_attacker := Vector3(-incoming.x,0,-incoming.z).normalized()
	var blocking := not ranged and not top and state in ["guard","chase","return"] and facing.dot(toward_attacker)>0.5
	var damage := maxi(1,roundi(base_damage*0.3)) if blocking else roundi(base_damage*1.5) if top else base_damage
	hp = maxi(0,hp-damage)
	health_bar.set_health(hp,max_hp)
	hurt = 0.15
	knockback = Vector3(incoming.x,0,incoming.z).normalized()*2
	if hp==0:
		state="dead"
		collision_layer=0
		collision_mask=0
	elif blocking:
		block_flash=0.4
		knockback*=0.15
	else:
		volley_left=0
		strike_pending=false
		state="recover"
		hurt_recovery=true
		reaction_angle=motion_angle
		attack_time=0.35
		if not target_visible: last_seen = global_position-Vector3(incoming.x,0,incoming.z).normalized()*2.5
		search_time=5
	effects.impact(global_position+Vector3.UP,damage,hp==0)
	return "格挡" if blocking else "顶部" if top else "身体"

func update_occlusion() -> void:
	var target := global_position+Vector3.UP*0.95
	var origin := camera.project_ray_origin(camera.unproject_position(target))
	var query := PhysicsRayQueryParameters3D.create(origin,target,1|4,[get_rid()])
	occluded = not get_world_3d().direct_space_state.intersect_ray(query).is_empty()
	outline.visible = occluded and hp>0

func find_retreat() -> Vector3:
	var best := global_position
	var score := -INF
	for id in routes.graph.get_point_ids():
		var point: Vector3=routes.graph.get_point_position(id)
		var distance := point.distance_to(global_position)
		if distance<1.0 or distance>4.5: continue
		var separation := point.distance_to(last_seen)
		if separation<3.5: continue
		var ray := PhysicsRayQueryParameters3D.create(point+Vector3.UP*1.4,last_seen+Vector3.UP,1|4,[get_rid()])
		var cover := not get_world_3d().direct_space_state.intersect_ray(ray).is_empty()
		var rating := minf(separation,5.5)-distance*0.6+(1.5 if cover else 0.0)
		if rating>score:
			var candidate: PackedVector3Array=routes.path(global_position,point,navigation_excluded)
			if candidate.size()>1:
				score=rating
				best=point
	return best

func sight_range() -> float:
	# Foot elevation, not an actor's height or distance from the camera.
	var advantage := maxf(0,global_position.y-player.global_position.y)
	return (11.0 if ranged else 10.0)+minf(6.0,advantage*(2.5 if ranged else 1.0))

func update_senses(delta: float) -> void:
	target_visible=can_see_target()
	if target_visible:
		lost_time=0
		sight_grace=1.8 if global_position.distance_to(player.global_position)<3.5 else 0.75
		last_seen=player.global_position
		search_time=5.0
		if state in ["guard","return","investigate","search"]:
			if state in ["guard","return"]: effects.sound("alert",global_position)
			state="chase"
	else:
		lost_time+=delta
		if state=="chase" and lost_time>sight_grace:
			state="investigate"
			repath=0

func choose_movement(delta: float) -> Vector3:
	var move := Vector3.ZERO
	if state=="windup":
		attack_time-=delta
		if attack_time<=0:
			if ranged: perform_attack()
			else: strike_pending=true
			if ranged and volley_left>0:
				volley_left-=1
				state="nock"
				attack_time=0.65
			else:
				state="recover"
				attack_time=1.35 if ranged else 0.8 if thrust else 0.65
				recovery_duration=attack_time
	elif state=="nock":
		attack_time-=delta
		if attack_time<=0:
			if target_visible and global_position.distance_to(last_seen)>3.0:
				locked_target=player.global_position+Vector3.UP*(0.55 if player.crouched else 1.0)
				facing=Vector3(last_seen.x-global_position.x,0,last_seen.z-global_position.z).normalized()
				state="windup"
				attack_time=0.45
				action_duration=0.45
				draw_from=0.35
			else:
				volley_left=0
				state="recover"
				attack_time=1.0
	elif state=="recover":
		attack_time-=delta
		if strike_pending and recovery_duration-attack_time>=0.09:
			strike_pending=false
			perform_attack()
		if attack_time<=0:
			state="chase" if target_visible or lost_time<sight_grace else "investigate"
			hurt_recovery=false
	elif state=="chase" and target_visible and global_position.distance_to(last_seen)<(sight_range()-1.0 if ranged else 2.25 if attack_cycle%2==1 else 1.65) and (ranged or absf(global_position.y-last_seen.y)<0.65) and (not ranged or global_position.distance_to(last_seen)>3.0):
		facing=Vector3(last_seen.x-global_position.x,0,last_seen.z-global_position.z).normalized()
		if cooldown<=0:
			state="windup"
			thrust=not ranged and attack_cycle%2==1
			attack_cycle+=1
			volley_left=1 if ranged else 0
			attack_time=0.9 if ranged else 0.5 if thrust else 0.32
			action_duration=attack_time
			hurt_recovery=false
			draw_from=0.0
			locked_target=player.global_position+Vector3.UP*(0.55 if player.crouched else 1.0)
			locked_direction=(last_seen+Vector3.UP-(global_position+Vector3.UP*1.1)).normalized()
			cooldown=2.0 if ranged else 1.15
	elif state in ["chase","investigate","return"]:
		var goal := home if state=="return" else last_seen
		retreat_timer-=delta
		if ranged and state=="chase" and target_visible and global_position.distance_to(last_seen)<=3.0:
			if retreat_timer<=0:
				retreat_goal=find_retreat()
				retreat_timer=1.0
				repath=0
			goal=retreat_goal
		repath-=delta
		if repath<=0:
			route=routes.path(global_position,goal,navigation_excluded)
			route_index=0
			if route.size()>1 and routes.traversable(global_position,route[1],navigation_excluded): route_index=1
			repath=0.45
		if route_index<route.size():
			var offset := route[route_index]-global_position
			if Vector2(offset.x,offset.z).length()<0.10: route_index+=1
			else: move=Vector3(offset.x,0,offset.z).normalized()
		if state=="investigate":
			search_time-=delta
			if global_position.distance_to(last_seen)<0.7 or route.is_empty(): state="search"
			if search_time<=0: state="return"
		elif state=="return" and (global_position.distance_to(home)<0.6 or route.is_empty()): state="guard"
	elif state=="search":
		search_time-=delta
		facing=facing.rotated(Vector3.UP,delta*1.5)
		if search_time<=0: state="return"
	elif state=="guard": facing=Vector3(sin(clock*0.5)*0.7,0,1).normalized()
	return move
