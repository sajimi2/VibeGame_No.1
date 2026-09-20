extends "res://tests/tactical/warehouse_motion_test.gd"
## 覆盖真实 GPU 下滚屏、窗口/全屏以及原始/粗环境两档；不以静态截图推断稳定性。
func run() -> void:
	if DisplayServer.get_name()=="headless":
		print("SKIP painted motion requires GPU")
		quit()
		return
	ProjectSettings.set_setting("tactical/testing",true)
	DirAccess.make_dir_recursive_absolute("res://work/painted_cottage")
	scene=load("res://tools/painted_cottage_lab.tscn").instantiate()
	root.add_child(scene)
	current_scene=scene
	for i in 35: await physics_frame
	freeze(scene)
	scene.player.hide()
	scene.combat.hide()
	scene.hud.hide()
	var stats: Dictionary={}
	for mode in ["window","fullscreen"]:
		root.mode=Window.MODE_WINDOWED if mode=="window" else Window.MODE_EXCLUSIVE_FULLSCREEN
		for i in 15: await process_frame
		check(root.mode==(Window.MODE_WINDOWED if mode=="window" else Window.MODE_EXCLUSIVE_FULLSCREEN),mode+" 实际切换成功")
		for coarse in [false,true]:
			scene.environment_pixels.set_enabled(coarse,false)
			for art in [false,true]:
				scene.painting.set_enabled(art)
				scene.second_painting.set_enabled(art)
				scene.camera.position=scene.snapped_camera_position(Vector3(0,1,0)+scene.camera.global_basis.z*26)
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
						largest=maxf(largest,residual(reference,await screen(),axis*step))
				var label: String=mode+("_coarse" if coarse else "_fine")+("_painting" if art else "_old")
				check(largest<.01,label+" 平移残差 %.5f"%largest)
				stats[label]={"residual":largest}
				(await screen()).save_png("res://work/painted_cottage/"+label+".png")
	var file:=FileAccess.open("res://work/painted_cottage/motion_metrics.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(stats,"\t"))
	print("PAINTED_MOTION: %d checks, %d failures"%[checks,failures])
	scene.queue_free()
	await process_frame
	quit(1 if failures else 0)
