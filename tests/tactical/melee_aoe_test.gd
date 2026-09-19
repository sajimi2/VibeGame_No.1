extends SceneTree
## 用真实玩家、守卫和物理墙运行整段攻击，验证群攻时序、遮挡、上限及去重。
var lab: Node3D
var enemies: Array[CharacterBody3D]=[]
var checks := 0
var failures := 0
var impact_point := Vector3.ZERO

func _initialize() -> void: run.call_deferred()
func frames(n: int) -> void:
	for i in n: await physics_frame
func check(ok: bool, caption: String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+caption)

## 每个案例先同步移走的敌人，再放置玩家；避免连续瞬移造成旧碰撞位置推挤。
func arrange(kind: String, positions: Array, index: int = 0) -> void:
	lab.combat.swing_time=0
	lab.combat.cooldown=0
	lab.combat.bow_time=0
	lab.combat.queued_action=0
	for i in enemies.size():
		var enemy := enemies[i]
		enemy.ai_enabled=false
		enemy.position=positions[i] if i<positions.size() else Vector3(10+i,0,10)
		enemy.hp=200
		enemy.max_hp=200
		enemy.state="guard"
		enemy.facing=Vector3.FORWARD
		enemy.velocity=Vector3.ZERO
		enemy.knockback=Vector3.ZERO
		enemy.hurt_recovery=false
		enemy.update_visuals(0)
	await frames(2)
	lab.player.position=Vector3(0,.03,0)
	lab.player.velocity=Vector3.ZERO
	lab.player.facing=Vector2(0,-1)
	lab.player.hp=100
	lab.player.test_motion=Vector2.ZERO
	lab.combat.apply_weapon(load("res://data/weapons/"+kind+".tres"))
	lab.combat.attack_index=index
	await frames(12)

## 走生产攻击入口与物理帧，记录首次真实落点；空挥预采样不依赖人工猜测刀尖位置。
func attack(capture_name: String = "") -> void:
	lab.combat.attack(lab.combat.muzzle()+Vector3.FORWARD*4)
	var captured := false
	for i in ceili(lab.combat.attack_interval*60)+3:
		await physics_frame
		if lab.combat.impact_emitted and not captured:
			impact_point=lab.combat.weapon.to_global(lab.combat.weapon.get_meta("blade_tip"))
			captured=true
			if not capture_name.is_empty(): await capture(capture_name)
	if not captured and not capture_name.is_empty(): await capture(capture_name)

func damaged() -> int:
	return enemies.filter(func(e):return e.hp<200).size()
func capture(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await process_frame
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png("res://work/aoe/"+label+".png")

func run() -> void:
	ProjectSettings.set_setting("tactical/testing",true)
	DirAccess.make_dir_recursive_absolute("res://work/aoe")
	lab=load("res://scripts/world/level.gd").new()
	lab.encounter_enabled=false
	root.add_child(lab)
	current_scene=lab
	lab.box("Ground",Vector3(0,-.2,0),Vector3(40,.4,40),"grass")
	lab.player.test_mode=true
	lab.player.invulnerable=999
	for i in 7:
		var enemy := preload("res://scripts/actors/enemy.gd").new()
		enemy.player=lab.player
		enemy.camera=lab.camera
		enemy.effects=lab.effects
		enemy.sunlight=lab.lighting.sun
		enemy.ai_enabled=false
		enemy.position=Vector3(10+i,0,10)
		lab.add_child(enemy)
		enemies.append(enemy)
	await frames(5)
	# 同射线前后站位是旧检测的缺口：前排身体不应截断宝剑横扫。
	await arrange("sword",[Vector3(0,0,-.8),Vector3(0,0,-1.45)])
	lab.combat.attack(lab.combat.muzzle()+Vector3.FORWARD*4)
	await frames(8)
	check(damaged()==0,"宝剑前摇没有提前扣血")
	await frames(35)
	check(enemies[0].hp==180 and enemies[1].hp==180,"横扫穿过前排身体，前后两人各受一次 20 伤害")
	lab.combat.strike(-50,50)
	check(enemies[0].hp==180 and enemies[1].hp==180,"同一动作再次采样不重复扣血")
	await arrange("sword",[Vector3(.85,0,-1.1),Vector3(-.85,0,-1.1)])
	lab.combat.attack(lab.combat.muzzle()+Vector3.FORWARD*4)
	await frames(14)
	check(enemies[0].hp==180 and enemies[1].hp==200,"挥到一侧时只伤该侧，不提前结算整个扇面")
	await frames(25)
	check(enemies[1].hp==180,"刀刃扫到另一侧后才结算另一目标")
	await arrange("sword",[Vector3(-.85,0,-1.1),Vector3(0,0,-1.0),Vector3(.85,0,-1.1),Vector3(.35,0,-1.65),Vector3(0,0,1.0)])
	await attack("sword_sweep")
	check(damaged()==3,"横斩整段动作最多命中三人")
	check(enemies[4].hp==200,"横扫不打身后敌人")
	await arrange("sword",[Vector3(0,0,-.8),Vector3(0,0,-1.45),Vector3(.85,0,-1.0)],1)
	await attack()
	check(damaged()==1 and enemies[2].hp==200,"同一宝剑的突刺仍限一人、保留窄范围")
	await arrange("knife",[Vector3(-.25,0,-.9),Vector3(.35,0,-1.0)])
	await attack()
	check(damaged()==1,"匕首维持单次单目标")
	await arrange("sword",[Vector3(0,0,-.7),Vector3(0,0,-1.65)])
	var wall: StaticBody3D = lab.box("SweepWall",Vector3(0,1,-1.15),Vector3(4,2,.12),"wall")
	await frames(3)
	await attack()
	check(enemies[0].hp==180 and enemies[1].hp==200,"可扫穿身体但不能穿过身体后方的墙")
	wall.queue_free()
	await frames(3)
	await arrange("sword",[Vector3(-.5,0,-1),Vector3(.5,0,-1)])
	enemies[0].facing=Vector3.BACK
	await attack()
	check(enemies[0].hp==194 and enemies[1].hp==180,"群攻逐个解算盾挡，盾前减伤而侧背正常扣血")
	# 先取得当前模型实际落点，再布置范围内、范围外、背后和不同高度的目标。
	await arrange("cleaver",[])
	await attack()
	check(lab.combat.impact_emitted,"重刀实际接地触发冲击")
	var center := impact_point*Vector3(1,0,1)
	print("IMPACT_CENTER ",center)
	await arrange("cleaver",[Vector3(0,0,-1.2),center+Vector3(.85,0,0),center+Vector3(-.85,0,0),center+Vector3(.55,0,-.7),center+Vector3(-.55,0,-.7),center+Vector3(0,1.8,0),Vector3(0,0,1)])
	var previous_bursts: int=lab.combat.dust.bursts
	await attack("heavy_impact")
	check(damaged()==4,"重刀刀刃与落地冲击合计最多四个目标")
	check(enemies[0].hp==174,"刀刃命中只扣 26，不叠加落地伤害")
	check(enemies.filter(func(e):return e.hp==180).size()==3,"落地冲击独立对周围三人各扣 20")
	check(enemies[5].hp==200 and enemies[6].hp==200,"冲击不跨楼层，也不覆盖玩家身后")
	check(lab.combat.dust.bursts==previous_bursts+1,"一次重击只出现一次落地尘土")
	check(enemies[1].knockback.length()>4.9,"范围命中应用较强击退")
	# 只让一名受击演员推进短暂硬直，检查真实 move_and_slide 位移，而非只看参数。
	var before: Vector3=enemies[1].position
	enemies[1].ai_enabled=true
	await frames(10)
	enemies[1].ai_enabled=false
	check(enemies[1].position.distance_to(before)>.3,"重击后的敌人实际被推开")
	await arrange("cleaver",[center+Vector3(.85,0,0),center+Vector3(1.7,0,0)])
	enemies[0].facing=(lab.player.position-enemies[0].position).normalized()
	await attack()
	check(enemies[0].hp==194 and enemies[0].knockback.length()<1,"正面盾挡冲击时保留减伤与抗击退")
	check(enemies[1].hp==200,"冲击半径外不扣血")
	await arrange("cleaver",[center+Vector3(.9,0,0)])
	wall=lab.box("ImpactWall",center+Vector3(.45,.9,0),Vector3(.12,1.8,2),"wall")
	await frames(3)
	await attack()
	check(lab.combat.impact_emitted and enemies[0].hp==200,"刀尖可落地，但冲击不能绕过旁边墙体")
	wall.queue_free()
	await frames(3)
	await arrange("cleaver",[center+Vector3(.85,0,0)])
	lab.player.request_jump()
	# 测试提高初速，让整个下砸窗口都处于空中，排除正常落地后触发冲击的情况。
	lab.player.velocity.y=10
	await frames(8)
	await attack()
	check(not lab.combat.impact_emitted and enemies[0].hp==200,"空中下砸不生成地面范围伤害")
	print("MELEE_AOE: %d checks, %d failures"%[checks,failures])
	lab.queue_free()
	await process_frame
	quit(1 if failures else 0)
