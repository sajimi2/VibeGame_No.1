extends SceneTree
## 新物种走真实角色物理与攻击时序；隔离进度，覆盖锁向、躲避、墙体、打断及死亡。
const Spec=preload("res://scripts/art/baked_human_spec.gd")
const Source=preload("res://scripts/art/baked_character_source.gd")
var lab: Node3D
var creatures: Array[CharacterBody3D]=[]
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func frames(n: int) -> void:
	for i in n: await physics_frame
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+label)

## 渲染专项保留起手/命中实景；不改变相机比例或战斗计时来美化截图。
func capture(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	DirAccess.make_dir_recursive_absolute("res://work/creatures")
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png("res://work/creatures/"+label+".png")

func arrange(enemy: CharacterBody3D, target:=Vector3(0,0,1.5)) -> void:
	for other in creatures:
		other.ai_enabled=false
		other.position=Vector3(7+creatures.find(other)*2,0,7)
		other.warning.hide()
	enemy.position=Vector3(0,.04,0)
	enemy.home=Vector3.ZERO
	enemy.velocity=Vector3.ZERO
	enemy.knockback=Vector3.ZERO
	enemy.hp=enemy.max_hp
	enemy.state="guard"
	enemy.facing=Vector3.BACK
	enemy.hurt_recovery=false
	enemy.returning_to_post=false
	enemy.cooldown=0
	enemy.repath=0
	await frames(3)
	lab.player.position=target+Vector3.UP*.04
	lab.player.velocity=Vector3.ZERO
	lab.player.test_motion=Vector2.ZERO
	lab.player.hp=100
	lab.player.invulnerable=0
	lab.player.safe_zone=false
	# 暂停 AI 时手动推进重力，保证起手检测使用真实地面接触状态。
	for i in 8:
		enemy.velocity=Vector3.DOWN
		enemy.move_and_slide()
		await physics_frame
	enemy.update_visuals(0)

func start(enemy: CharacterBody3D) -> void:
	enemy.begin_attack()
	enemy.ai_enabled=true

func run() -> void:
	ProjectSettings.set_setting("tactical/testing",true)
	lab=load("res://scripts/world/level.gd").new()
	lab.encounter_enabled=false
	root.add_child(lab)
	current_scene=lab
	lab.box("Floor",Vector3(0,-.2,0),Vector3(30,.4,30),"grass")
	lab.player.test_mode=true
	await frames(3)
	lab.routes=preload("res://scripts/world/terrain_routes.gd").new()
	lab.add_child(lab.routes)
	lab.routes.build(lab.get_world_3d(),Rect2(-6,-6,12,12))
	for id in Spec.CREATURES:
		var enemy:=preload("res://scripts/actors/creature.gd").new()
		enemy.profile=load("res://data/enemies/"+id+".tres")
		enemy.tuning=load("res://data/encounters/waystation_hard.tres")
		enemy.player=lab.player
		enemy.camera=lab.camera
		enemy.effects=lab.effects
		enemy.routes=lab.routes
		enemy.ai_enabled=false
		enemy.position=Vector3(7+creatures.size()*2,0,7)
		lab.add_child(enemy)
		creatures.append(enemy)
	for enemy in creatures:
		for other in creatures: enemy.navigation_excluded.append(other.get_rid())
		check(enemy.baked_visual.active and enemy.sword.get_child_count()==0 and enemy.shield_node==null,enemy.art_id+" 使用整身图集，无多余剑盾/实时武器视口")
		var manifest: Dictionary=enemy.baked_visual.manifest
		check(manifest.entries.size()==1188 and manifest.cell==96,enemy.art_id+" 五组动作十二朝向共 1188 帧")
		var source:=Source.new()
		source.rig_id=enemy.art_id
		source.asset_id=enemy.art_id+"_baked"
		var covered:=true
		for action in source.animations():
			for direction in 12:
				for frame in action.frames:
					var selected:=Spec.select(source.preview_state(action.id,direction,frame,{}),enemy.art_id)
					covered=covered and manifest.entries.has(selected.full)
		check(covered,enemy.art_id+" 工作台选帧与游戏清单一致")
	var goblin:=creatures[0]
	var golem:=creatures[1]
	var slime:=creatures[2]
	await arrange(goblin)
	start(goblin)
	await frames(35)
	check(lab.player.hp==100 and goblin.warning.visible,"哥布林前摇可见且尚未扣血")
	capture("goblin_windup")
	await frames(20)
	check(lab.player.hp==77,"哥布林矛刺沿真实线段命中 23 点伤害")
	capture("goblin_hit")
	for i in 70:
		await physics_frame
		if goblin.state=="retreat": break
	var before: Vector3=goblin.position
	await frames(15)
	check(goblin.position.z<before.z-.25,"突刺收招后实际后撤拉开距离")
	await arrange(goblin)
	start(goblin)
	var direction: Vector3=goblin.locked_direction
	lab.player.position.x=2
	await frames(60)
	check(lab.player.hp==100 and goblin.locked_direction==direction,"哥布林起手锁向，横移可以躲开")
	await arrange(golem,Vector3(0,0,2.2))
	start(golem)
	await frames(60)
	check(lab.player.hp==100 and golem.warning.visible,"石头人慢蓄力，地面落点预告先于伤害")
	capture("golem_windup")
	await frames(20)
	check(lab.player.hp==61 and golem.impact_dust.bursts>0,"砸地在落拳阶段造成 39 点伤害并扬尘")
	capture("golem_hit")
	await frames(20)
	check(lab.player.hp==61,"同一次砸地不重复扣血")
	await arrange(golem,Vector3(0,0,2.2))
	start(golem)
	golem.receive_strike(golem.position+Vector3.UP,Vector3.BACK,Vector3.FORWARD,16,2)
	check(golem.state=="windup" and golem.hp==124,"石头人承受轻击扣血但继续蓄力")
	golem.receive_strike(golem.position+Vector3.UP,Vector3.BACK,Vector3.FORWARD,26,5)
	check(golem.state=="recover" and golem.hurt_recovery and not golem.warning.visible,"重刀打断砸地并撤销预告")
	await frames(40)
	check(lab.player.hp==100,"被打断的砸地不残留延迟伤害")
	await arrange(golem,Vector3(0,0,2.2))
	start(golem)
	lab.player.position.x=3
	await frames(82)
	check(lab.player.hp==100,"离开已锁定的砸地区域可避伤")
	await arrange(golem,Vector3(0,0,2.2))
	start(golem)
	await frames(52)
	lab.player.request_jump()
	await frames(28)
	check(lab.player.hp==100,"跳跃离地可躲开地面冲击")
	await arrange(golem,Vector3(0,0,2.2))
	var wall: StaticBody3D=lab.box("SlamWall",Vector3(0,.9,1.6),Vector3(4,1.8,.15),"wall")
	await frames(3)
	start(golem)
	await frames(82)
	check(lab.player.hp==100,"砸地冲击不能穿墙")
	wall.queue_free()
	await frames(3)
	await arrange(slime,Vector3(0,0,2.5))
	start(slime)
	await frames(35)
	check(lab.player.hp==100 and slime.warning.visible,"史莱姆压缩蓄势时显示冲撞方向")
	capture("slime_windup")
	await frames(35)
	check(lab.player.hp==84 and slime.damage_done,"史莱姆实际碰撞命中只扣一次 16")
	capture("slime_hit")
	await frames(20)
	check(lab.player.hp==84,"碰撞接触不持续磨血")
	await arrange(slime,Vector3(0,0,2.5))
	start(slime)
	lab.player.position.x=2
	await frames(80)
	check(lab.player.hp==100 and absf(slime.position.x)<.1,"史莱姆冲撞不追踪横移玩家")
	await arrange(slime,Vector3(0,0,2.5))
	wall=lab.box("ChargeWall",Vector3(0,.8,1.2),Vector3(4,1.6,.2),"wall")
	await frames(3)
	start(slime)
	await frames(80)
	check(lab.player.hp==100 and slime.position.z<.85,"冲撞遇墙停止，不穿墙接触玩家")
	wall.queue_free()
	await frames(3)
	# 玩家也必须能通过生产战斗入口反击，不用直接调用受击函数代替命中验证。
	for enemy in creatures:
		await arrange(enemy,Vector3(0,0,1.2))
		lab.combat.apply_weapon(load("res://data/weapons/sword.tres"))
		lab.combat.cooldown=0
		lab.combat.attack(enemy.position+Vector3.UP*(enemy.body_height*.5))
		await frames(45)
		check(enemy.hp<enemy.max_hp,enemy.art_id+" 玩家实际挥剑命中身体")
		await arrange(enemy,Vector3(0,0,3))
		var center: Vector3=enemy.position+Vector3.UP*(enemy.body_height*.6)
		var aimed: Vector3=lab.combat.assisted_point(center+Vector3.RIGHT,lab.camera.unproject_position(center)+Vector2(25,0))
		check(lab.combat.assist_target==enemy and aimed.y<enemy.position.y+enemy.body_height,enemy.art_id+" 辅助瞄准按体型选取高度")
		lab.combat.cooldown=0
		lab.combat.apply_weapon(load("res://data/weapons/bow.tres"))
		lab.combat.shoot(center)
		await frames(40)
		check(enemy.hp<enemy.max_hp,enemy.art_id+" 玩家实际箭矢弹道命中身体")
	for enemy in creatures:
		await arrange(enemy,Vector3(0,0,4))
		enemy.hp=0
		enemy.ai_enabled=true
		await frames(35)
		check(enemy.baked_visual.active and enemy.baked_visual.last_keys.full.contains("death_fall"),enemy.art_id+" 实际播放独立死亡帧")
		await frames(215)
		check(not enemy.visible,enemy.art_id+" 尸体停留后渐隐")
	print("CREATURE_ENCOUNTER: %d checks, %d failures"%[checks,failures])
	lab.queue_free()
	await process_frame
	quit(1 if failures else 0)
