extends SceneTree
## 隔离小院实战验证：输入归属、有效命中蓄能、格挡、翻滚、库存和实际画面。
var lab: Node3D
var player: CharacterBody3D
var combat: Node3D
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func frames(count: int) -> void:
	for i in count: await physics_frame
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+message)
func key(code: int) -> void:
	var event:=InputEventKey.new()
	event.physical_keycode=code
	event.pressed=true
	Input.parse_input_event(event)
func mouse(button: int, pressed: bool) -> void:
	var event:=InputEventMouseButton.new()
	event.button_index=button
	event.pressed=pressed
	event.position=lab.camera.unproject_position(player.global_position+Vector3.FORWARD*4)
	Input.parse_input_event(event)
func settle() -> void:
	combat.cooldown=0
	combat.swing_time=0
	combat.bow_time=0
	combat.guard_held=false
	player.blocking=false
	player.roll_time=0
	player.roll_cooldown=0
	player.invulnerable=0
	player.hp=100
	player.test_motion=Vector2.ZERO
	await frames(2)
func capture(name: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://work/"+name+".png")

## 取实际运行画面八个相位，核对身体/双手/武器与翻滚，不以源模型预览代替。
func action_sheet(action: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await settle()
	combat.apply_weapon(load("res://data/weapons/sword.tres"))
	player.position=Vector3(0,.03,7.5)
	lab.objective.visible=false
	player.facing=Vector2(1,0)
	await frames(3)
	var sheet:=Image.create(256*4,256*2,false,Image.FORMAT_RGBA8)
	for i in 8:
		var phase:=float(i)/7
		if action=="roll":
			player.roll_direction=Vector2(1,0)
			player.roll_time=maxf(.001,player.ROLL_DURATION*(1-phase))
		else:
			combat.attack_action=load("res://data/actions/"+action+".tres")
			combat.locked_direction=Vector3.RIGHT
			combat.swing_time=maxf(.001,combat.attack_duration*(1-phase))
			combat.previous_angle=rad_to_deg(combat.attack_action.sweep_to)
		combat._physics_process(0)
		player.set_physics_process(false)
		combat.set_physics_process(false)
		await process_frame
		await RenderingServer.frame_post_draw
		var center: Vector2=lab.camera.unproject_position(player.global_position+Vector3.UP)
		var frame:=root.get_texture().get_image()
		sheet.blit_rect(frame,Rect2i(Vector2i(center)-Vector2i(128,128),Vector2i(256,256)),Vector2i((i%4)*256,(i/4)*256))
	player.set_physics_process(true)
	combat.set_physics_process(true)
	sheet.save_png("res://work/combat_"+action+"_sheet.png")
	lab.objective.visible=true
	await settle()

## 用真实移动穿过院门和房门，验证新地图的任务可达性。
func walk_to(point: Vector3) -> bool:
	for i in 260:
		var delta:=Vector2(point.x-player.position.x,point.z-player.position.z)
		if delta.length()<.25:
			player.test_motion=Vector2.ZERO
			return true
		player.test_motion=delta.normalized()
		await physics_frame
	player.test_motion=Vector2.ZERO
	return false

func run() -> void:
	ProjectSettings.set_setting("tactical/testing",true)
	lab=load("res://scenes/courtyard_combat.tscn").instantiate()
	# 此专项保留旧取信流程回归，新故事由 woodpath_expedition 专项覆盖。
	lab.story_mode=false
	lab.results_enabled=false
	root.add_child(lab)
	current_scene=lab
	while not is_instance_valid(lab.progression): await frames(1)
	# 本专项会主动置零生命检查清理；移除结算视图，避免其暂停后续独立案例。
	if is_instance_valid(lab.run_flow):
		lab.run_flow.queue_free()
		lab.run_flow=null
	player=lab.player
	combat=lab.combat
	player.test_mode=true
	for enemy in get_nodes_in_group("tactical_enemies"):
		enemy.ai_enabled=false
		enemy.update_visuals(0)
	await frames(10)
	check(get_nodes_in_group("tactical_enemies").size()==3 and lab.ready_to_test,"绘画小院完成三敌遭遇与遮挡装配")
	check(lab.progression.quick_slots().size()==5,"独立弓占第五格")
	key(KEY_5)
	await frames(2)
	check(combat.weapon_profile.ranged,"5 经库存换装独立弓")
	check(combat.bow.visible and not combat.weapon.visible,"持弓待机只显示弓")
	mouse(MOUSE_BUTTON_LEFT,true)
	await frames(2)
	check(combat.bow_time>0 and is_instance_valid(combat.pending_arrow),"弓左键进入拉弓")
	check(not player.request_roll(),"拉弓期间不能翻滚取消发箭")
	await frames(32)
	mouse(MOUSE_BUTTON_RIGHT,true)
	await frames(2)
	check(player.blocking and combat.bow_time<=0,"弓右键格挡，不再发箭")
	mouse(MOUSE_BUTTON_RIGHT,false)
	await settle()
	key(KEY_4)
	await frames(2)
	check(combat.weapon_profile.model_id=="oath_blade","4 仍装备断剑")
	check(combat.shoot(combat.muzzle()+Vector3.FORWARD*4)==null,"近战武器不能调用弓射击")
	for i in 4:
		combat.attack(combat.muzzle()+Vector3.FORWARD*4)
		await frames(43)
	check(combat.charge_hits==0 and not combat.finisher_attack,"连续空挥不积累光刃")
	var enemy=get_nodes_in_group("tactical_enemies")[0]
	enemy.can_block=false
	enemy.hp=500
	enemy.max_hp=500
	var hit={"collider":enemy,"position":enemy.position+Vector3.UP,"normal":Vector3.FORWARD}
	enemy.can_block=true
	enemy.state="guard"
	enemy.facing=Vector3.BACK
	combat.cooldown=0
	combat.attack(combat.muzzle()+Vector3.FORWARD*4)
	combat.apply_melee_hit(hit,Vector3.FORWARD)
	check(combat.charge_hits==0,"被盾牌格挡不增加光刃蓄能")
	enemy.can_block=false
	combat.swing_time=0
	for i in 3:
		player.position=Vector3(.8,.03,13.6)
		player.velocity=Vector3.ZERO
		enemy.position=Vector3(.8,.03,12.7)
		enemy.velocity=Vector3.ZERO
		enemy.knockback=Vector3.ZERO
		enemy.facing=Vector3.FORWARD
		await frames(3)
		combat.cooldown=0
		combat.attack(combat.muzzle()+Vector3.FORWARD*4)
		await frames(43)
		check(combat.charge_hits==i+1,"实际挥击物理命中累积 %d" % [i+1])
		var charged: int=combat.charge_hits
		combat.apply_melee_hit(hit,Vector3.FORWARD)
		check(combat.charge_hits==charged,"同一挥击重复采样不增加计数")
	combat.cooldown=0
	combat.attack(combat.muzzle()+Vector3.FORWARD*4)
	check(combat.finisher_attack and combat.charge_hits==0 and combat.melee_range==2.25,"三次有效命中后的下一击释放光刃")
	await frames(45)
	combat.cooldown=0
	combat.attack(combat.muzzle()+Vector3.FORWARD*4)
	check(not combat.finisher_attack and combat.melee_range==1.15,"光刃空挥后也消耗，恢复断刃")
	combat.charge_hits=2
	player.hp=0
	await frames(2)
	check(combat.charge_hits==0,"死亡清除未释放的光刃蓄能")
	await settle()
	# 格挡正面减伤，背面照常受伤；关闭任务的安全区刷新避免掩盖测试。
	lab.objective.set_physics_process(false)
	player.safe_zone=false
	player.facing=Vector2(0,-1)
	combat.guard_held=true
	await frames(2)
	player.receive_damage(20,Vector3.BACK)
	check(player.hp==95 and player.blocked_hits==1,"正面格挡减伤至 25%")
	player.invulnerable=0
	player.receive_damage(20,Vector3.FORWARD)
	check(player.hp==75,"背面来袭不能格挡")
	check(not combat.attack(combat.muzzle()+Vector3.FORWARD*4),"举武器格挡期间不能攻击")
	combat.guard_held=false
	await settle()
	player.position=Vector3(.8,.1,13.6)
	await frames(4)
	player.facing=Vector2(1,0)
	var start: Vector3=player.position
	key(KEY_ALT)
	await frames(1)
	check(player.roll_time>0,"Alt 实际按键触发落地翻滚")
	check(not player.request_roll(),"翻滚冷却阻止连滚")
	check(not combat.attack(combat.muzzle()+Vector3.RIGHT*4),"翻滚期间禁止攻击")
	await frames(8)
	player.invulnerable=0
	player.receive_damage(20,Vector3.LEFT)
	check(player.hp==100,"翻滚中段免伤")
	check(player.baked_visual.visible,"翻滚整身图集实际可显示")
	await capture("combat_roll")
	await frames(16)
	player.invulnerable=0
	player.receive_damage(20,Vector3.LEFT)
	check(player.hp==80,"翻滚收尾不免伤")
	await frames(15)
	check(player.position.distance_to(start)>2 and player.position.distance_to(start)<4,"翻滚真实位移在有限范围")
	await settle()
	player.position=Vector3(.8,.1,13.6)
	var wall=lab.box("RollTestWall",Vector3(2.0,1,13.6),Vector3(.15,2,4),"wall")
	await frames(5)
	player.facing=Vector2(1,0)
	player.request_roll()
	await frames(38)
	check(player.position.x<1.7,"翻滚 move_and_slide 不能穿墙")
	wall.queue_free()
	await settle()
	player.velocity.y=6
	await frames(2)
	check(not player.request_roll(),"空中禁止翻滚")
	await frames(45)
	await action_sheet("sword_slash")
	await action_sheet("sword_overhead")
	await action_sheet("roll")
	await settle()
	player.position=Vector3(.8,.1,13.6)
	await frames(4)
	await capture("combat_courtyard")
	key(KEY_I)
	await frames(2)
	check(paused and lab.progression.open,"I 开包暂停")
	for button in lab.progression.view.quick_buttons:
		check(absf(button.size.x-button.size.y)<.1,"快捷栏保持圆角正方形")
	await capture("combat_inventory")
	key(KEY_I)
	await frames(2)
	check(not paused,"背包关闭恢复")
	await settle()
	for enemy_actor in get_nodes_in_group("tactical_enemies"):
		enemy_actor.position=Vector3(-9,0,-6)
	lab.objective.set_physics_process(true)
	player.position=lab.spawn_point()
	await frames(4)
	lab.objective.interact()
	check(lab.objective.accepted,"小院入口可接取委托")
	var entered: bool=await walk_to(Vector3(0,0,5))
	entered=await walk_to(Vector3(0,0,0)) and entered
	check(entered,"携带实战碰撞真实走过院门和房门")
	lab.objective.interact()
	check(lab.objective.carried,"室内密函可实际交互，不被地板或墙阻断")
	await walk_to(Vector3(0,0,5))
	await walk_to(lab.objective.exit_point)
	await frames(2)
	lab.objective.interact()
	check(lab.objective.claimed and lab.progression.inventory.has_instance("camp_reward_cleaver"),"实际返回交付并领取重刀")
	lab.queue_free()
	await frames(3)
	print("COURTYARD_COMBAT: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
