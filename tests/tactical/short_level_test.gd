extends SceneTree
var lab: Node3D
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func frames(n: int) -> void:
	for i in n: await physics_frame
func ui_frames(n: int = 3) -> void:
	for i in n: await process_frame
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode=code
	event.keycode=code
	event.pressed=true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	event=event.duplicate()
	event.pressed=false
	Input.parse_input_event(event)
	Input.flush_buffered_events()
func capture(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://work/short_level_"+label+".png")
func place(point: Vector3) -> void:
	lab.player.position=point
	lab.player.velocity=Vector3.ZERO
	lab.player.test_motion=Vector2.ZERO
	await frames(10)
func walk_to(destination: Vector3) -> bool:
	var player=lab.player
	var excluded: Array[RID]=[player.get_rid(),lab.guard.get_rid(),lab.archer.get_rid()]
	var path: PackedVector3Array=lab.routes.path(player.position,destination,excluded)
	if path.is_empty(): return false
	for point in path:
		var reached := false
		for i in 90:
			var offset: Vector3=point-player.position
			if Vector2(offset.x,offset.z).length()<0.12:
				reached=true
				break
			player.test_motion=Vector2(offset.x,offset.z).normalized()
			await frames(1)
		if not reached:
			print("Blocked at ",player.position," toward ",point)
			player.test_motion=Vector2.ZERO
			return false
	player.test_motion=Vector2.ZERO
	return player.position.distance_to(destination)<1.0
## 驱动关卡闭环，覆盖通行、交付结算、死亡重试与界面按键。
func run() -> void:
	ProjectSettings.set_setting("tactical/testing",true)
	lab=load("res://tests/fixtures/legacy/tactical_height.tscn").instantiate()
	root.add_child(lab)
	current_scene=lab
	while not is_instance_valid(lab.run_flow): await frames(1)
	lab.player.test_mode=true
	await frames(20)
	check(lab.has_node("TrailCamp") and lab.has_node("ApproachRemnant"),"camp dressing and approach cover exist")
	var dummies := 0
	for node in lab.get_children():
		if node.get_script()==load("res://scripts/world/training_target.gd"): dummies+=1
	check(dummies==0 and get_nodes_in_group("tactical_enemies").size()==2,"live level removes training props and retains two distinct enemy roles")
	check(lab.player.safe_zone and lab.guard.state=="guard" and lab.archer.state=="guard","camp starts safe without activating enemies")
	await capture("camp")
	lab.guard.ai_enabled=false
	lab.archer.ai_enabled=false
	key(KEY_E)
	await frames(2)
	check(lab.objective.accepted,"actual E accepts quest at the dressed camp")
	await place(Vector3(-5,0.03,3))
	lab.guard.facing=Vector3.BACK
	lab.archer.facing=(lab.player.position-lab.archer.position)*Vector3(1,0,1)
	lab.archer.facing=lab.archer.facing.normalized()
	check(lab.guard.can_see_target(),"road guard sees exposed standing approach")
	check(not lab.archer.can_see_target(),"central ruin shields first encounter from high archer")
	lab.player.test_crouch=true
	await frames(3)
	check(not lab.guard.can_see_target(),"crouching behind low wall breaks guard sight")
	lab.player.test_crouch=false
	await frames(3)
	await capture("approach")
	check(await walk_to(Vector3(-2.5,0,-3.3)),"player physically walks around low cover and northern ruin end")
	check(await walk_to(Vector3(5,0,2.7)),"player physically reaches ramp mouth around central wall")
	check(await walk_to(lab.objective.pickup_point+Vector3(0,0,0.7)),"player physically climbs onto letter plateau")
	await capture("highland")
	key(KEY_E)
	await frames(3)
	check(lab.objective.carried,"actual E retrieves letter after physical traversal")
	check(await walk_to(Vector3(12,0,5)),"return route descends ramp and reaches eastern cloth passage")
	check(await walk_to(lab.objective.exit_point),"eastern path returns to camp without collision traps")
	await frames(8)
	key(KEY_E)
	await ui_frames()
	check(lab.objective.claimed and lab.run_flow.won and paused,"E hand-in displays completion and pauses world")
	check(lab.run_flow.details.text.contains("大砍刀") and lab.progression.inventory.has_instance("camp_reward_cleaver"),"first completion clearly presents real granted reward")
	await capture("reward")
	key(KEY_I)
	await ui_frames()
	check(lab.progression.open and paused and not lab.run_flow.showing,"I transfers result screen to paused inventory")
	key(KEY_I)
	await ui_frames()
	check(not paused and not lab.progression.open,"closing result inventory returns to running game")
	await place(Vector3(-3,0.03,5))
	lab.player.receive_damage(999,Vector3.RIGHT)
	await ui_frames(5)
	check(paused and lab.run_flow.showing and not lab.run_flow.won,"death after free exploration also shows retry screen")
	await capture("death")
	key(KEY_R)
	await frames(30)
	lab=current_scene
	while not is_instance_valid(lab.run_flow): await frames(1)
	check(not paused and lab.player.hp>0 and not lab.objective.carried and lab.guard.hp==60 and lab.archer.hp==40,"R from paused death screen starts fresh attempt")
	lab.player.test_mode=true
	lab.guard.ai_enabled=false
	lab.archer.ai_enabled=false
	lab.progression.rewarded=true
	lab.objective.accepted=true
	lab.objective.carried=true
	await frames(8)
	key(KEY_E)
	await ui_frames()
	check(lab.run_flow.details.text.contains("不重复发放") and not lab.objective.first_reward,"repeat completion explains no duplicate first-clear reward")
	lab.run_flow.continue_button.pressed.emit()
	await ui_frames()
	check(not paused and not lab.run_flow.showing,"continue button resumes after repeat completion")
	print("SHORT_LEVEL: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
