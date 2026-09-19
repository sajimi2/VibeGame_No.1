extends SceneTree
var lab: Node3D
var guard: CharacterBody3D
var player: CharacterBody3D
var failures := 0
var checks := 0
func _initialize() -> void: run.call_deferred()
func frames(n: int) -> void:
	for i in n: await physics_frame
func check(value: bool, label: String) -> void:
	checks+=1
	if not value: failures+=1
	print(("PASS " if value else "FAIL ")+label)
func capture(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://work/feedback_"+label+".png")
## 验证坡道侧面通行、敌人视野以及光照反馈的边界情况。
func run() -> void:
	lab=load("res://scenes/tactical_height.tscn").instantiate()
	lab.mission_enabled=false
	ProjectSettings.set_setting("tactical/testing",true)
	root.add_child(lab)
	current_scene=lab
	player=lab.player
	player.test_mode=true
	while not is_instance_valid(lab.guard): await frames(1)
	guard=lab.guard
	# 这两处接近方向曾错误选择穿过坡道侧面的短路径。
	for start in [Vector3(2.5,0.05,0.8),Vector3(7.6,0.05,-0.5)]:
		guard.ai_enabled=false
		guard.position=start
		guard.velocity=Vector3.ZERO
		player.position=Vector3(5,1.8,-3.4)
		player.velocity=Vector3.ZERO
		await frames(6)
		guard.facing=(Vector3(player.position.x,guard.position.y,player.position.z)-guard.position).normalized()
		guard.state="chase"
		guard.lost_time=0
		guard.repath=0
		guard.last_seen=player.position
		guard.ai_enabled=true
		for i in 540:
			await frames(1)
			if guard.position.y>0.95 and guard.position.distance_to(player.position)<1.9: break
		print("Side pursuit: ",start," -> ",guard.position," ",guard.state," route ",guard.route," index ",guard.route_index)
		check(guard.position.y>0.95 and guard.position.distance_to(player.position)<1.9,"pursues via ramp entrance from "+str(start))
		await capture("ramp")
		player.hp=100
	guard.ai_enabled=false
	guard.position=Vector3(3.8,2.05,-4.6)
	player.position=Vector3(4.3,2.05,-4.6)
	player.velocity=Vector3.ZERO
	guard.facing=Vector3.RIGHT
	guard.state="chase"
	await frames(5)
	guard.ai_enabled=true
	await frames(3)
	var remembered: Vector3=guard.last_seen
	player.position=Vector3(0.5,0.05,-4.6)
	player.velocity=Vector3.ZERO
	await frames(8)
	check(guard.state in ["chase","windup","recover"],"nearby drop does not instantly switch to question mark")
	check(guard.target_visible or guard.last_seen.distance_to(remembered)<0.03,"grace does not reveal hidden target position")
	# 即使近距离，也不能透过石墙获得视野。
	guard.ai_enabled=false
	guard.position=Vector3(-1.8,0.05,3)
	guard.facing=Vector3.RIGHT
	guard.state="chase"
	guard.lost_time=0
	player.position=Vector3(-0.2,0.05,3)
	await frames(3)
	check(not guard.can_see_target(),"close awareness still respects wall occlusion")
	var angle_before: Vector3=lab.lighting.sun.rotation
	lab.lighting.set_time_of_day(8)
	check(not lab.lighting.sun.rotation.is_equal_approx(angle_before),"time parameter changes sun projection direction")
	player.position=Vector3(4,2.05,-6)
	player.velocity=Vector3.ZERO
	await frames(5)
	await capture("morning")
	lab.lighting.set_time_of_day(16)
	await frames(3)
	await capture("afternoon")
	var roots:=0
	for child in lab.get_children():
		if child.is_in_group("tree_world_shadows"): roots+=1
	check(roots>=4,"all trees have world-space shadow volumes")
	check(player.baked_visual.layers.lower.shadow.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY,"actor shares world shadow system")
	print("FEEDBACK_EDGES: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
