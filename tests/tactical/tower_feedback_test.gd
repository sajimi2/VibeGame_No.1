extends SceneTree
var failures := 0
func _initialize() -> void: run.call_deferred()
func frames(n: int) -> void:
	for i in n: await physics_frame
func check(ok: bool,label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures+=1
## 检查守卫登塔路径、遮挡轮廓和原始分辨率调色。
func run() -> void:
	var lab = load("res://scenes/tactical_height.tscn").instantiate()
	lab.mission_enabled=false
	ProjectSettings.set_setting("tactical/testing",true)
	root.add_child(lab)
	current_scene=lab
	lab.player.test_mode=true
	while not is_instance_valid(lab.guard): await frames(1)
	var guard=lab.guard
	for start in [Vector3(-5,0.02,13),Vector3(-10,0.02,13)]:
		guard.ai_enabled=false
		guard.position=start
		guard.velocity=Vector3.ZERO
		lab.player.position=Vector3(-8,1.21,9)
		lab.player.velocity=Vector3.ZERO
		lab.player.hp=100
		await frames(5)
		guard.state="chase"
		guard.facing=(lab.player.position-guard.position).normalized()
		guard.last_seen=lab.player.position
		guard.repath=0
		guard.lost_time=0
		guard.ai_enabled=true
		for i in 700:
			await frames(1)
			if guard.position.y>1.18 and guard.position.z<10.7: break
		print("Tower chase ",guard.position," ",guard.state)
		check(guard.position.y>1.18 and guard.position.z<10.7,"guard reaches tower from "+str(start))
	guard.ai_enabled=false
	guard.position=Vector3(-8,0.01,7.7)
	await frames(5)
	guard.update_occlusion()
	check(guard.occluded and guard.baked_visual.layers.upper.occlusion.visible,"occluded enemy gets occlusion")
	guard.position=Vector3(-3,0.01,7)
	await frames(4)
	guard.update_occlusion()
	check(not guard.occluded and guard.baked_visual.layers.upper.occlusion.visible,"无遮挡时仍启用 GPU 逐像素裁切，实际无灰色由 occlusion_presentation 验证")
	check(not lab.lighting.pixel_material.shader.code.contains("SCREEN_PIXEL_SIZE*2.0"),"native resolution color pass")
	if DisplayServer.get_name()!="headless":
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://work/tower_feedback.png")
	print("TOWER_FEEDBACK: 5 checks, ",failures," failures")
	quit(1 if failures else 0)
