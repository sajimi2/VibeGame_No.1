extends "res://tests/tactical/wall_occlusion_test.gd"
## 同材质前墙触发透视时，圆内旁墙/近后墙应保持原像素；同时覆盖真实仓库窄走道。
func run() -> void:
	ProjectSettings.set_setting("tactical/testing",true)
	DirAccess.make_dir_recursive_absolute("res://work/occlusion")
	scene=load("res://tests/fixtures/legacy/waystation_blockout.tscn").instantiate()
	scene.combat_enabled=false
	root.add_child(scene)
	current_scene=scene
	scene.player.test_mode=true
	await frames(5)
	freeze(scene)
	scene.hud.hide()
	for label in scene.review_labels: label.hide()
	scene.combat.hide()
	scene.combat.hand.hide()
	controller=scene.wall_occlusion
	await place(Vector3(0,.02,26))
	scene.environment_pixels.set_enabled(false,false)
	var front:=board(Vector3(1.1,3,.15),Vector3(0,0,2))
	var side:=board(Vector3(.7,2,.15),Vector3(1.1,0,.4))
	var back:=board(Vector3(.7,2,.15),Vector3(-1.1,0,-.4))
	# 第二层前景墙完全藏在第一层后，不能只收集射线最近命中的墙。
	var second:=board(Vector3(1.1,3,.15),Vector3(0,0,1))
	await settle()
	check(controller.ratio>=.9 and controller.reveal==1,"前墙触发透视，旁墙与近后墙仍在同一个圆内")
	check(second.get_active_material(0).get_shader_parameter("wall_reveal")==1,"前方重叠的两段墙都参与透视，不遗漏被前墙盖住的一层")
	if DisplayServer.get_name()!="headless":
		bodies(false)
		hints(false)
		controller.reveal=0
		controller._publish()
		var solid:=await screen()
		controller.reveal=1
		controller._publish()
		var opened:=await screen("selective_"+("before" if "--baseline" in OS.get_cmdline_user_args() else "after"))
		for item in [side,back]:
			var center: Vector2=scene.camera.unproject_position(item.global_position)
			var changed:=0
			for y in range(int(center.y)-20,int(center.y)+20):
				for x in range(int(center.x)-8,int(center.x)+8):
					if solid.get_pixel(x,y)!=opened.get_pixel(x,y): changed+=1
			print("UNRELATED_WALL changed=",changed," position=",item.position)
			check(changed==0,"圆内未遮挡的墙保持像素不变 "+str(item.position))
		check(solid.get_data()!=opened.get_data(),"前墙确实淡化，非全部禁用透视")
		bodies(true)
		hints(true)
	# 身体仍被另一段墙全挡时，移开的旧遮挡也必须自行恢复，不能依赖全局圆关闭。
	front.global_position+=scene.camera.global_basis.x*1.5
	await settle()
	check(controller.reveal==1 and front.get_active_material(0).get_shader_parameter("wall_reveal")==0,"圆仍开启时，已不遮挡的旧墙独立恢复")
	for item in [front,side,back,second]: item.hide()
	for roof in scene.get_node("Roofs").get_children(): roof.set_physics_process(true)
	scene.environment_pixels.set_enabled(true,false)
	var index:=0
	for point in [Vector3(8.3,1.8,-6),Vector3(8.3,1.8,-12.5),Vector3(14,1.8,-14.7)]:
		await place(point)
		await settle()
		if index<2:
			var rail: Node=scene.get_node("Architecture/RampRailSouth" if index==0 else "Architecture/RampRailNorth")
			var base: MeshInstance3D=rail.get_node("Visual")
			var cap: MeshInstance3D=rail.get_node("ArtFinish/Masonry")
			check(controller._group_owner(base)==controller._group_owner(cap),"真实仓库矮墙的墙身和薄压顶属于同一构件")
			check(base.get_active_material(0).get_shader_parameter("wall_reveal")==0 and cap.get_active_material(0).get_shader_parameter("wall_reveal")==0,"仓库走道旁未挡住玩家的矮墙和压顶完整保留")
		if DisplayServer.get_name()!="headless": await screen("selective_warehouse_"+("before" if "--baseline" in OS.get_cmdline_user_args() else "after")+"_"+str(index))
		index+=1
	print("SELECTIVE_WALL: %d checks, %d failures"%[checks,failures])
	scene.queue_free()
	await process_frame
	quit(1 if failures else 0)
