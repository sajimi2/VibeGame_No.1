extends SceneTree
const Creature = preload("res://scripts/actors/creature.gd")
## 驿站强化遭遇：验证真实伤害、攻速、实体路线和隔离装备，不用配置存在代替行为通过。
var scene: Node3D
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+message)
func frames(count: int) -> void:
	for i in count: await physics_frame
func arrange(enemy: Node3D, at: Vector3, target: Vector3) -> void:
	enemy.position=at+Vector3.UP*.05
	enemy.home=at
	enemy.velocity=Vector3.ZERO
	enemy.state="guard"
	enemy.returning_to_post=false
	enemy.facing=(target-at).normalized()
	enemy.route=PackedVector3Array()
	enemy.repath=0
	enemy.cooldown=0
	enemy.hurt_recovery=false
	# 移走敌人后先同步物理世界，避免玩家落在其旧碰撞上被错误推走。
	await frames(2)
	scene.player.position=target+Vector3.UP*.05
	scene.player.velocity=Vector3.ZERO
	scene.player.invulnerable=999
	await frames(3)

func run() -> void:
	ProjectSettings.set_setting("tactical/testing",true)
	scene=load("res://scenes/waystation_blockout.tscn").instantiate()
	root.add_child(scene)
	current_scene=scene
	scene.player.test_mode=true
	for i in 300:
		await physics_frame
		if scene.battle_ready: break
	check(scene.battle_ready,"导航、十名敌人与临时装备完成装配")
	if not scene.battle_ready: quit(1); return
	await frames(5)
	var enemies := get_nodes_in_group("tactical_enemies")
	check(enemies.size()==10,"十名敌人分组驻守，保留总规模")
	check(enemies.filter(func(e):return e.ranged).size()==3 and enemies.filter(func(e):return e.art_id in ["goblin","golem","slime"]).size()==5,"三弓手、两守卫与五名新物种混合驻守")
	check(not scene.progression.persist and scene.objective==null,"只接入战斗，不接任务奖励或真实存档")
	check(scene.progression.inventory.has_instance("camp_sword") and scene.progression.inventory.has_instance("waystation_trial_cleaver"),"三把现有近战武器均可试用")
	check(scene.player.safe_zone and not enemies.any(func(e):return e.target_visible),"出生营地安全，远处敌人不会全图发现玩家")
	var health_ok := true
	var placement_ok := true
	var shape := CapsuleShape3D.new()
	shape.radius=.27
	shape.height=1.5
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape=shape
	query.collision_mask=33
	var excluded: Array[RID]=[]
	for enemy in enemies: excluded.append(enemy.get_rid())
	query.exclude=excluded
	for enemy in enemies:
		health_ok=health_ok and enemy.max_hp==(enemy.profile.health if enemy is Creature else 52 if enemy.ranged else 80)
		shape.height=enemy.body_height-.04
		shape.radius=enemy.body_radius-.02
		query.transform=Transform3D(Basis.IDENTITY,enemy.position+Vector3.UP*(enemy.body_height/2+.03))
		var hits := scene.get_world_3d().direct_space_state.intersect_shape(query)
		if not hits.is_empty(): print("SPAWN_BLOCKED ",enemy.home," ",hits.map(func(hit):return hit.collider.name))
		placement_ok=placement_ok and hits.is_empty()
		enemy.ai_enabled=false
		enemy.collision_layer=0
	check(health_ok,"生命数值实际应用到每名演员")
	check(placement_ok,"十个出生位置均未嵌入地形或建筑")
	var guard: Node3D=enemies[5]
	guard.collision_layer=17
	await arrange(guard,Vector3(5,1.8,-9),Vector3(13,1.8,-9))
	guard.ai_enabled=true
	await frames(240)
	check(guard.position.x>11 and absf(guard.position.y-1.8)<.12,"守卫实际穿过仓库门洞追击")
	guard.ai_enabled=false
	await arrange(guard,Vector3(5,0,2),Vector3(5,1.8,-7))
	guard.ai_enabled=true
	await frames(250)
	check(guard.position.z < -4.5 and guard.position.y>1.6,"守卫实际追上高台")
	guard.ai_enabled=false
	guard.collision_layer=0
	# 新体型复用同一张导航图，实际验证较宽石头人也能穿门和上坡。
	for id in ["goblin","golem","slime"]:
		var creature: Node3D=enemies.filter(func(e):return e.art_id==id)[0]
		creature.collision_layer=17
		await arrange(creature,Vector3(5,1.8,-9),Vector3(15,1.8,-9))
		creature.ai_enabled=true
		await frames(480)
		check(creature.position.x>11 and absf(creature.position.y-1.8)<.12,id+" 实际穿门追击")
		creature.ai_enabled=false
		await arrange(creature,Vector3(5,0,2),Vector3(5,1.8,-7))
		creature.ai_enabled=true
		await frames(540)
		check(creature.position.z < -4.5 and creature.position.y>1.6,id+" 实际沿坡追上高台")
		creature.ai_enabled=false
		creature.collision_layer=0
		creature.warning.hide()
	guard.collision_layer=17
	await arrange(guard,Vector3(0,0,10),Vector3(0,0,11.2))
	guard.state="chase"
	guard.target_visible=true
	guard.last_seen=scene.player.position
	guard.attack_cycle=0
	guard.choose_movement(0)
	check(is_equal_approx(guard.action_duration,.272) and is_equal_approx(guard.cooldown,.92),"横斩前摇 0.272 秒、起手间隔 0.92 秒")
	guard.choose_movement(.28)
	check(guard.strike_pending and is_equal_approx(guard.recovery_duration,.507),"缩短收招仍保留挥出与待结算命中")
	guard.strike_pending=false
	scene.player.hp=100
	scene.player.invulnerable=0
	guard.locked_direction=Vector3.BACK
	guard.thrust=false
	guard.perform_attack()
	check(scene.player.hp==74,"横斩真实扣血 26")
	scene.player.invulnerable=0
	guard.thrust=true
	guard.perform_attack()
	check(scene.player.hp==41,"突刺真实扣血 33")
	var archer: Node3D=enemies.filter(func(e):return e.ranged)[0]
	await arrange(archer,Vector3(-5,0,12),Vector3(-5,0,16))
	scene.player.hp=100
	scene.player.invulnerable=0
	archer.locked_target=scene.player.position+Vector3.UP
	archer.perform_attack()
	await frames(35)
	check(scene.player.hp==80,"弓箭沿真实弹道命中扣血 20")
	guard.home=Vector3(0,0,10)
	guard.position=Vector3(0,0,30)
	guard.state="windup"
	guard.strike_pending=true
	guard.update_senses(.016)
	check(guard.returning_to_post and guard.state=="return" and not guard.strike_pending,"超出岗位范围取消出手并归队")
	scene.player.position=scene.spawn_point()
	scene.player.hp=50
	await frames(3)
	check(scene.player.hp==100 and scene.player.safe_zone,"回到营地可恢复生命重新交战")
	guard.ai_enabled=true
	for i in 900:
		await physics_frame
		if guard.position.distance_to(guard.home)<.8: break
	await frames(3)
	check(guard.position.distance_to(guard.home)<.8 and not guard.returning_to_post,"归队真实走回外院，通过营门后解除离岗锁定")
	guard.ai_enabled=false
	await arrange(guard,Vector3(0,0,12),scene.spawn_point())
	guard.home=Vector3(0,0,10)
	guard.state="windup"
	guard.strike_pending=true
	guard.update_senses(.016)
	check(guard.returning_to_post and not guard.strike_pending,"玩家回营地时敌人取消待结算攻击")
	var before: Vector3=scene.player.position
	for key in [KEY_M,KEY_3]:
		var event := InputEventKey.new()
		event.physical_keycode=key
		event.pressed=true
		scene._unhandled_input(event)
	check(not scene.overview and scene.player.position==before,"战斗模式禁用全图冻结和区域瞬移")
	scene.last_feedback="弓箭命中：格挡"
	await frames(2)
	check(scene.hud.feedback.text.contains("格挡"),"剩余人数与实际命中反馈同时保留")
	# 从相同出生数据重开渲染一张外院实景，避免测试挪位后的演员污染截图。
	scene.queue_free()
	await process_frame
	if DisplayServer.get_name()!="headless":
		scene=load("res://scenes/waystation_blockout.tscn").instantiate()
		root.add_child(scene)
		current_scene=scene
		while not scene.battle_ready: await physics_frame
		scene.player.test_mode=true
		scene.player.position=Vector3(0,.05,17)
		await frames(35)
		RenderingServer.force_draw(false)
		root.get_texture().get_image().save_png("res://work/waystation/combat.png")
		scene.queue_free()
		await process_frame
	print("WAYSTATION_COMBAT: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)

