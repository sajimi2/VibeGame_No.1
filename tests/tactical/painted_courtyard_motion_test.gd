extends "res://tests/tactical/warehouse_motion_test.gd"
## 冻结真实动画后检查窗口/全屏滚屏；前后标记额外验证画稿实际写入空间深度。
func depth_probe(point: Vector3,label: String) -> void:
	var probe:=MeshInstance3D.new()
	var quad:=QuadMesh.new()
	quad.size=Vector2(.22,.22)
	probe.mesh=quad
	var material:=StandardMaterial3D.new()
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color=Color(1,0,1)
	probe.material_override=material
	probe.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(probe)
	probe.global_basis=scene.camera.global_basis
	for front in [true,false]:
		probe.global_position=point+scene.camera.global_basis.z*(.3 if front else -.3)
		var frame: Image=await screen()
		var pixel:=Vector2i(scene.camera.unproject_position(point))
		var color:=frame.get_pixelv(pixel)
		var visible: bool=color.r>.7 and color.b>.7 and color.g<.25
		check(visible==front,label+(" 前方标记可见" if front else " 后方标记被遮挡"))
	probe.queue_free()
	await process_frame

func run() -> void:
	if DisplayServer.get_name()=="headless":
		print("SKIP courtyard motion requires GPU")
		quit()
		return
	ProjectSettings.set_setting("tactical/testing",true)
	DirAccess.make_dir_recursive_absolute("res://work/painted_courtyard")
	scene=load("res://tools/painted_courtyard_lab.tscn").instantiate()
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
			scene.camera.position=scene.snapped_camera_position(Vector3(0,2,5)+scene.camera.global_basis.z*26)
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
			var label: String=mode+("_coarse" if coarse else "_fine")
			check(largest<.01,label+" 平移残差 %.5f"%largest)
			stats[label]={"residual":largest}
			(await screen()).save_png("res://work/painted_courtyard/"+label+".png")
	scene.camera.position=scene.snapped_camera_position(Vector3(0,2,7)+scene.camera.global_basis.z*26)
	scene.environment_pixels._process(0)
	await depth_probe(Vector3(-5.2,.7,11.725),"矮墙绘画深度")
	await depth_probe(Vector3(7.1,.65,9.7475),"不规则石头深度")
	var file:=FileAccess.open("res://work/painted_courtyard/motion_metrics.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(stats,"\t"))
	print("COURTYARD_MOTION: %d checks, %d failures"%[checks,failures])
	scene.queue_free()
	await process_frame
	quit(1 if failures else 0)
