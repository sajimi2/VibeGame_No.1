extends SceneTree
var lab: Node3D
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func frames(n: int) -> void:
	for i in n: await physics_frame
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func mouse(button: MouseButton, target: Vector3) -> void:
	var event := InputEventMouseButton.new()
	event.button_index=button
	event.pressed=true
	event.position=lab.camera.unproject_position(target)
	Input.parse_input_event(event)
	Input.flush_buffered_events()
func capture(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://work/attack_motion_"+label+".png")
## 模拟攻击输入，检查近战动作、收招缓存、拉弓和敌人挥击时序。
func run() -> void:
	ProjectSettings.set_setting("tactical/testing",true)
	lab=load("res://tests/fixtures/legacy/tactical_height.tscn").instantiate()
	lab.mission_enabled=false
	root.add_child(lab)
	current_scene=lab
	while not is_instance_valid(lab.guard): await frames(1)
	var player=lab.player
	var combat=lab.combat
	var guard=lab.guard
	guard.ai_enabled=false
	player.test_mode=true
	player.position=Vector3(4,0.02,6)
	guard.position=Vector3(4,0.02,4.6)
	guard.state="recover"
	guard.facing=Vector3.BACK
	await frames(10)
	var before: int=guard.hp
	combat.attack(guard.position+Vector3.UP)
	player.test_motion=Vector2(0.2,0)
	var initial: Vector3=player.position
	var poses := {}
	var max_change := 0.0
	var last_angle := 0.0
	for i in 23:
		await frames(1)
		poses[player.baked_visual.last_keys.upper]=true
		var angle: float=combat.hand.rotation.y
		if i>0: max_change=maxf(max_change,absf(angle_difference(last_angle,angle)))
		last_angle=angle
		if i==9: await capture("player_swing")
	player.test_motion=Vector2.ZERO
	check(poses.size()>=8,"player attack includes progressive body and arm poses")
	check(max_change<0.7,"weapon has no hard recovery-to-idle angular snap")
	check(player.position.distance_to(initial)>0.2,"player keeps moving throughout attack")
	check(guard.hp==before-combat.melee_damage,"progressive swing still deals damage only once")
	# 冷却结束前的点击只应缓存并执行一次。
	guard.hp=60
	while combat.cooldown>0: await frames(1)
	combat.attack(guard.position+Vector3.UP)
	while combat.cooldown>0.1: await frames(1)
	mouse(MOUSE_BUTTON_LEFT,guard.position+Vector3.UP)
	check(combat.queued_action==1,"late click is buffered during recovery")
	await frames(8)
	check(combat.swing_time>0 and combat.queued_action==0,"buffer executes one followup attack when available")
	await frames(30)
	check(combat.swing_time==0 and combat.queued_action==0,"buffer does not create automatic repeated attacks")
	guard.position=Vector3(4,0.02,3)
	await frames(8)
	combat.apply_weapon(load("res://data/weapons/bow.tres"))
	var arrow=combat.shoot(guard.position+Vector3.UP)
	await frames(4)
	check(is_instance_valid(arrow) and not arrow.visible and arrow.lifetime==0,"bow draws before projectile becomes active")
	check(player.bow_draw>0,"player has a progressing bow draw pose")
	await capture("draw")
	await frames(7)
	check(arrow.visible and arrow.lifetime>0 and not is_instance_valid(combat.pending_arrow),"arrow releases at the end of draw")
	await frames(30)
	check(guard.hp<60,"released player arrow physically reaches target")
	var cancelled=combat.shoot(Vector3(8,1,1))
	player.hp=0
	await frames(2)
	check(not is_instance_valid(cancelled),"death cancels an unreleased arrow")
	player.hp=100
	player.position=Vector3(4,0.02,6)
	guard.position=Vector3(4,0.02,4.5)
	guard.hp=60
	guard.collision_layer=1|16
	guard.collision_mask=1|2
	guard.velocity=Vector3.ZERO
	guard.knockback=Vector3.ZERO
	guard.hurt=0
	guard.hurt_recovery=false
	guard.sword.show()
	guard.shield_node.show()
	guard.trail.show()
	guard.death_visual.restore(guard)
	guard.state="chase"
	guard.attack_cycle=0
	guard.cooldown=0
	guard.lost_time=0
	guard.facing=Vector3.BACK
	guard.ai_enabled=true
	await frames(3)
	var start: Vector3=guard.position
	poses.clear()
	for i in 43:
		await frames(1)
		poses[guard.baked_visual.last_keys.upper]=true
		if i==24: await capture("guard_swing")
	check(poses.size()>=10,"guard windup and recovery keep progressive body poses")
	print("Guard step ",start," -> ",guard.position," state ",guard.state)
	check(guard.position.distance_to(start)>0.05 and absf(guard.position.y)<0.1,"guard strike includes a short physical committed step")
	check(not guard.shield_node.global_basis.is_equal_approx(guard.sword.get_child(0).global_basis),"shield does not rotate with blade through the swing")
	guard.ai_enabled=false
	print("ATTACK_MOTION: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
