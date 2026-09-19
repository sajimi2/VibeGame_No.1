extends "res://scripts/actors/enemy.gd"
## 新物种共用感知/导航/受击接口；这里只推进有明确前摇、锁向和收招的三种攻击。
const Query = preload("res://scripts/combat/melee_query.gd")
var profile: Resource = preload("res://data/enemies/goblin.tres")
var warning: MeshInstance3D
var impact_dust: Node3D
var damage_done := false
var slam_point := Vector3.ZERO
var attack_ground_valid := false
var retreat_left := 0.0

func _ready() -> void:
	art_id=profile.art_id
	body_height=profile.height
	body_radius=profile.radius
	uses_equipment=false
	can_block=false
	max_hp=profile.health
	hp=max_hp
	super._ready()
	name=profile.art_id.capitalize()
	marker.position.y=body_height+.55
	health_bar.position.y=body_height+.23
	warning=preload("res://scripts/presentation/attack_warning.gd").new()
	add_child(warning)
	warning.top_level=true
	warning.setup(profile.attack_kind,profile.reach)
	impact_dust=preload("res://scripts/presentation/drag_dust.gd").new()
	add_child(impact_dust)
	update_visuals(0)

## 角色先感知再移动；冲撞走真实碰撞，攻击只在自身有效窗口内结算一次。
func _physics_process(delta: float) -> void:
	if hp<=0:
		warning.hide()
		death_visual.update(self,delta)
		return
	if not ai_enabled: return
	clock+=delta
	cooldown=maxf(0,cooldown-delta)
	hurt=maxf(0,hurt-delta)
	update_senses(delta)
	var previous := global_position
	var move := creature_step(delta)
	var speed: float=profile.attack_speed if state=="active" else profile.speed if state=="chase" else 1.8
	if move.length()>.1 and state not in ["active","retreat"]: facing=move
	velocity=move*speed+knockback+Vector3.UP*(velocity.y-20*delta)
	knockback=knockback.move_toward(Vector3.ZERO,delta*14)
	move_and_slide()
	if state=="active" and profile.attack_kind=="charge":
		for i in get_slide_collision_count():
			var hit := get_slide_collision(i)
			if hit.get_collider()==player and not damage_done:
				player.receive_damage(roundi(profile.damage*tuning.damage_scale),locked_direction)
				damage_done=true
				finish_attack()
				break
			if absf(hit.get_normal().y)<.5:
				finish_attack()
				break
	var distance := Vector2(position.x-previous.x,position.z-previous.z).length()
	gait+=distance/(1.3 if art_id=="goblin" else 1.8)*TAU
	update_visuals(distance)

func creature_step(delta: float) -> Vector3:
	warning.visible=state=="windup" and not hurt_recovery and attack_ground_valid
	if state=="windup":
		attack_time-=delta
		warning.progress(1-attack_time/profile.windup)
		if attack_time<=0:
			state="active"
			attack_time=profile.active_time
			warning.hide()
		return Vector3.ZERO
	if state=="active":
		attack_time-=delta
		if profile.attack_kind!="charge" and attack_time<=profile.active_time*.25: perform_attack()
		if attack_time<=0:
			finish_attack()
			return Vector3.ZERO
		if profile.attack_kind=="charge" and not supported_step(locked_direction,profile.attack_speed*delta+.15):
			finish_attack()
			return Vector3.ZERO
		return locked_direction if profile.attack_kind in ["charge","thrust"] else Vector3.ZERO
	if state=="recover":
		attack_time-=delta
		if attack_time<=0:
			if profile.attack_kind=="thrust" and not hurt_recovery:
				state="retreat"
				retreat_left=.45
			else: state="chase" if target_visible else "investigate"
			hurt_recovery=false
		return Vector3.ZERO
	if state=="retreat":
		retreat_left-=delta
		if retreat_left<=0 or not supported_step(-locked_direction,.4):
			state="chase" if target_visible else "investigate"
			return Vector3.ZERO
		return -locked_direction
	if state=="chase" and target_visible and cooldown<=0 and global_position.distance_to(last_seen)<profile.trigger_range and absf(player.position.y-position.y)<.6:
		begin_attack()
		return Vector3.ZERO
	if state in ["chase","investigate","return"]:
		var move := route_step(home if state=="return" else last_seen,delta)
		if state=="investigate":
			search_time-=delta
			if global_position.distance_to(last_seen)<.7 or route.is_empty(): state="search"
			if search_time<=0: state="return"
		elif state=="return" and global_position.distance_to(home)<.6: state="guard"
		return move
	if state=="search":
		search_time-=delta
		facing=facing.rotated(Vector3.UP,delta*1.5)
		if search_time<=0: state="return"
	elif state=="guard": facing=Vector3(sin(clock*.5)*.7,0,1).normalized()
	return Vector3.ZERO

## 起手一次锁定方向和落点，预告与真实伤害使用同一组数据，中途不追踪玩家。
func begin_attack() -> void:
	state="windup"
	attack_time=profile.windup
	damage_done=false
	hurt_recovery=false
	locked_direction=((player.global_position-global_position)*Vector3(1,0,1)).normalized()
	if locked_direction.length()<.1: locked_direction=facing
	facing=locked_direction
	locked_target=player.global_position+Vector3.UP*(.55 if player.crouched else 1.0)
	attack_ground_valid=true
	slam_point=global_position+locked_direction*1.05
	if profile.attack_kind=="slam":
		var excluded := Query.actor_exclusions(self)
		excluded.append(player.get_rid())
		var query := PhysicsRayQueryParameters3D.create(slam_point+Vector3.UP*.5,slam_point+Vector3.DOWN*.65,1|32,excluded)
		var ground := get_world_3d().direct_space_state.intersect_ray(query)
		attack_ground_valid=not ground.is_empty() and ground.normal.y>.7 and absf(ground.position.y-position.y)<.4
		if attack_ground_valid: slam_point=ground.position
	warning.global_position=(slam_point if profile.attack_kind=="slam" else global_position)+Vector3.UP*.055
	warning.global_basis=Basis(Vector3.UP,atan2(locked_direction.x,locked_direction.z))
	warning.visible=attack_ground_valid
	warning.progress(0)
	cooldown=profile.windup+profile.active_time+profile.recovery+profile.rest_time

func finish_attack() -> void:
	state="recover"
	attack_time=profile.recovery
	hurt_recovery=false
	warning.hide()

## 石头人按落点半径与脚底高度判定；哥布林按锁定的矛刺线判定，不做扇形群伤。
func perform_attack() -> void:
	if damage_done or player.hp<=0: return
	damage_done=true
	if profile.attack_kind=="slam":
		if not attack_ground_valid or not is_on_floor(): return
		impact_dust.burst(slam_point,locked_direction)
		if absf(player.global_position.y-slam_point.y)>.6: return
		var offset := player.global_position-slam_point
		if Vector2(offset.x,offset.z).length()>profile.reach: return
		var excluded := Query.actor_exclusions(self)
		excluded.append(player.get_rid())
		for origin in [global_position+Vector3.UP*.7,slam_point+Vector3.UP*.25]:
			var ray := PhysicsRayQueryParameters3D.create(origin,player.global_position+Vector3.UP*.4,1|8|32,excluded)
			if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): return
		player.receive_damage(roundi(profile.damage*tuning.damage_scale),locked_direction)
	elif profile.attack_kind=="thrust":
		var start := global_position+Vector3.UP*.82
		var direction := (locked_target-start).normalized()
		var ray := PhysicsRayQueryParameters3D.create(start,start+direction*profile.reach,1|2|8|32,[get_rid()])
		var hit := get_world_3d().direct_space_state.intersect_ray(ray)
		if not hit.is_empty() and hit.collider==player: player.receive_damage(roundi(profile.damage*tuning.damage_scale),direction)

## 后撤/冲撞先检查前方地面，防止主动运动跨出悬崖；实体阻挡仍由 move_and_slide 处理。
func supported_step(direction: Vector3, distance: float) -> bool:
	var p := global_position+direction*distance
	var ray := PhysicsRayQueryParameters3D.create(p+Vector3.UP*.4,p+Vector3.DOWN*.45,1|32,Query.actor_exclusions(self))
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	return not hit.is_empty() and hit.normal.y>.7 and absf(hit.position.y-position.y)<.4

## 一段动画对应完整攻击；前摇/有效/收招映射固定姿态相位，不把模型动画当作伤害计时器。
func update_visuals(travel: float) -> void:
	var view := facing.rotated(Vector3.UP,-camera.rotation.y)
	var direction := posmod(roundi(atan2(view.x,view.z)/(PI/6)),12)
	var clip := "idle"
	var phase := fmod(clock*.65,1.0)
	if hurt_recovery:
		clip="hurt"
		phase=1-attack_time/.35
	elif state in ["windup","active","recover"]:
		clip="attack"
		phase=(1-attack_time/profile.windup)*.58 if state=="windup" else lerpf(.58,.74,1-attack_time/profile.active_time) if state=="active" else lerpf(.74,1.0,1-attack_time/profile.recovery)
	elif travel>.002:
		clip="walk"
		phase=fposmod(gait/TAU,1)
	update_occlusion()
	baked_visual.tint=Color(1.6,.85,.7) if hurt>0 else Color.WHITE
	baked_visual.apply_frame({"direction":direction,"action":clip,"action_frame":roundi(clampf(phase,0,1)*(preload("res://scripts/art/baked_human_spec.gd").phases(clip)-1))})
	health_bar.set_health(hp,max_hp)
	marker.text=profile.title+" · "+("蓄力砸地！" if profile.attack_kind=="slam" else "准备冲撞！" if profile.attack_kind=="charge" else "突刺！") if state=="windup" else "收招 · 破绽" if state=="recover" and not hurt_recovery else profile.title

## 石头人蓄力时能承受轻击；重刀的强击退会打断。死亡、其他状态和软体仍正常受击。
func receive_strike(point: Vector3, normal: Vector3, incoming: Vector3, damage: int = 20, force: float = 2.0) -> String:
	var previous_state := state
	var previous_time := attack_time
	var result := super.receive_strike(point,normal,incoming,damage,force*profile.knockback_scale)
	if hp>0 and profile.attack_kind=="slam" and previous_state=="windup" and force<4:
		state=previous_state
		attack_time=previous_time
		hurt_recovery=false
		return "坚韧"
	if is_instance_valid(warning): warning.hide()
	return result

## 按各自半径/高度约束插箭深度，避免把史莱姆误当成人形胸膛。
func projectile_attachment_point(_region: String, point: Vector3, incoming: Vector3) -> Vector3:
	var local := point-global_position
	var planar := Vector3(local.x,0,local.z).limit_length(body_radius*.85)
	return global_position+planar+Vector3.UP*clampf(local.y,.1,body_height*.9)-incoming.normalized()*.02
