extends "res://tests/tactical/environment_motion_test.gd"
## 实际 GPU 比较新旧样板滚屏后的同一像素；静态截图不能代替时间稳定性验证。
func screen() -> Image:
	for i in 3: await process_frame
	RenderingServer.force_draw(false)
	var frame: Image=root.get_texture().get_image()
	frame.convert(Image.FORMAT_RGB8)
	return frame

func sample_cost() -> Dictionary:
	for i in 20: await process_frame
	var start:=Time.get_ticks_usec()
	for i in 90: await process_frame
	return {"frame_ms":float(Time.get_ticks_usec()-start)/90000.0,
		"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"video_mb":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)/1048576.0}

func run() -> void:
	if DisplayServer.get_name()=="headless":
		print("SKIP 仓库移动/全屏专项需要实际 GPU")
		quit()
		return
	ProjectSettings.set_setting("tactical/testing",true)
	DirAccess.make_dir_recursive_absolute("res://work/warehouse")
	scene=load("res://scenes/warehouse_art_slice.tscn").instantiate()
	root.add_child(scene)
	current_scene=scene
	scene.player.test_mode=true
	for i in 300:
		await physics_frame
		if scene.battle_ready: break
	freeze(scene)
	scene.player.hide()
	scene.combat.hide()
	scene.hud.hide()
	for label in get_nodes_in_group("sample_annotations"): label.hide()
	for actor in get_nodes_in_group("tactical_enemies"): actor.hide()
	for roof in scene.get_node("Roofs").get_children():
		roof.roof_material.set_shader_parameter("reveal",0.0)
		roof.roof_material.set_shader_parameter("roof_opacity",1.0)
	for material in scene.wall_occlusion.materials.values(): material.set_shader_parameter("wall_reveal",0.0)
	var stats: Dictionary={}
	for mode in ["window","fullscreen"]:
		root.mode=Window.MODE_WINDOWED if mode=="window" else Window.MODE_EXCLUSIVE_FULLSCREEN
		for i in 15: await process_frame
		check(root.mode==(Window.MODE_WINDOWED if mode=="window" else Window.MODE_EXCLUSIVE_FULLSCREEN),mode+" 实际窗口模式生效")
		for art in [false,true]:
			scene.sample_art.set_enabled(art)
			# 静态专项已冻结控制器，显式同步比较参数后再次关闭墙圆。
			scene.wall_occlusion._publish()
			for material in scene.wall_occlusion.materials.values(): material.set_shader_parameter("wall_reveal",0.0)
			scene.camera.position=scene.snapped_camera_position(Vector3(12,1.8,-6)+scene.camera.global_basis.z*26)
			var start: Vector3=scene.camera.position
			var unit: float=scene.camera.size/720.0
			var largest:=0.0
			for axis in [Vector2i(1,0),Vector2i(0,1),Vector2i(-1,-1)]:
				scene.camera.position=start
				scene.environment_pixels._process(0)
				var reference: Image=await screen()
				for step in [1,2,3,5]:
					scene.camera.position=start+(scene.camera.global_basis.x*axis.x+scene.camera.global_basis.y*axis.y)*unit*step
					scene.environment_pixels._process(0)
					var current: Image=await screen()
					var error:=residual(reference,current,axis*step)
					largest=maxf(largest,error)
				check(largest<.01,mode+(" 新美术" if art else " 旧美术")+" 滚屏纹理稳定 residual=%.4f"%largest)
			var id: String=mode+("_new" if art else "_old")
			stats[id]=await sample_cost()
			stats[id].residual=largest
			(await screen()).save_png("res://work/warehouse/"+id+".png")
	var file:=FileAccess.open("res://work/warehouse/render_metrics.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(stats,"\t"))
	print("WAREHOUSE_METRICS ",JSON.stringify(stats))
	print("WAREHOUSE_MOTION: %d checks, %d failures"%[checks,failures])
	scene.queue_free()
	await process_frame
	quit(1 if failures else 0)
