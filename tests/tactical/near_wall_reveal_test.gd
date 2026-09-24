extends "res://tests/tactical/wall_occlusion_test.gd"
## 用穿过人物深度的斜墙复现硬切线；比较原墙/透视/只留阴影，验证圆心确实完整透出。
func run() -> void:
	ProjectSettings.set_setting("tactical/testing",true)
	DirAccess.make_dir_recursive_absolute("res://work/occlusion")
	if DisplayServer.get_name()=="headless":
		print("NEAR_WALL_REVEAL: 需要实际 GPU，跳过画面验证")
		quit()
		return
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
	hints(false)
	bodies(false)
	var sheet:=board(Vector3(7,7,.15),Vector3(0,0,.1))
	sheet.basis=scene.camera.global_basis*Basis(Vector3.UP,PI/4)
	var mat: ShaderMaterial=sheet.get_active_material(0)
	# 本项隔离 Shader 深度边界；触发比例另由 wall_occlusion/selective_wall 的真实采样覆盖。
	controller.groups[controller._group_owner(sheet).get_instance_id()].weight=1.0
	controller.reveal=0
	controller._publish()
	var solid:=await screen()
	controller.reveal=1
	controller._publish()
	var label:="before" if "--baseline" in OS.get_cmdline_user_args() else "after"
	var opened:=await screen("near_wall_"+label)
	var mesh:=sheet.mesh
	sheet.mesh=null # 子节点阴影代理仍保持，排除移除阴影引起的颜色差异。
	var clear:=await screen()
	sheet.mesh=mesh
	var center: Vector2=mat.get_shader_parameter("wall_center")*Vector2(1280,720)
	var scale: float=720.0/scene.camera.size
	var opaque_core:=0
	var core_pixels:=0
	for y in range(int(center.y-30),int(center.y+30)):
		for x in range(int(center.x-30),int(center.x+30)):
			if Vector2(x,y).distance_to(center)>.70*scale: continue
			if solid.get_pixel(x,y)==clear.get_pixel(x,y): continue
			core_pixels+=1
			if opened.get_pixel(x,y)!=clear.get_pixel(x,y): opaque_core+=1
	print("NEAR_WALL_CORE remaining=",opaque_core,"/",core_pixels)
	check(core_pixels>1000 and opaque_core==0,"斜墙跨过人物深度时，中心小圆两侧都完全透出，不留下直线折角")
	# 屋顶也曾使用同一硬平面；用同一张斜面验证它没有留下第二条切线。
	var roof_material:=ShaderMaterial.new()
	roof_material.shader=preload("res://scripts/presentation/interior_roof.gdshader")
	roof_material.set_shader_parameter("surface_texture",load("res://assets/environment/textures/roof.png"))
	roof_material.set_shader_parameter("reveal_center",mat.get_shader_parameter("wall_center"))
	roof_material.set_shader_parameter("viewport_size",Vector2(1280,720))
	roof_material.set_shader_parameter("reveal_radius",mat.get_shader_parameter("wall_radius"))
	roof_material.set_shader_parameter("feather_width",mat.get_shader_parameter("wall_feather"))
	roof_material.set_shader_parameter("reveal_target",mat.get_shader_parameter("wall_target"))
	roof_material.set_shader_parameter("view_to_camera",scene.camera.global_basis.z)
	roof_material.set_shader_parameter("dither_origin",scene.camera.unproject_position(Vector3.ZERO).round())
	roof_material.set_shader_parameter("reveal",1.0)
	sheet.material_override=roof_material
	var roof_opened:=await screen("near_roof_"+label)
	var roof_remaining:=0
	for y in range(int(center.y-25),int(center.y+25)):
		for x in range(int(center.x-25),int(center.x+25)):
			if roof_opened.get_pixel(x,y)!=clear.get_pixel(x,y): roof_remaining+=1
	check(roof_remaining==0,"顶层斜屋面跨过人物深度时也不留下中心硬切线")
	sheet.material_override=mat
	# 远处墙体仍不透视：消除近墙硬切线不能让人物后方所有背景一起消失。
	sheet.global_position-=scene.camera.global_basis.z*5
	controller.reveal=0
	controller._publish()
	var back_solid:=await screen()
	controller.reveal=1
	controller._publish()
	var back_open:=await screen()
	check(back_solid.get_data()==back_open.get_data(),"远离人物后方的墙体不受透视影响")
	sheet.queue_free()
	await process_frame
	bodies(true)
	hints(true)
	scene.environment_pixels.set_enabled(true,false)
	for roof in scene.get_node("Roofs").get_children(): roof.set_physics_process(true)
	for point in [Vector3(14,1.8,-14.7),Vector3(21.7,1.8,-11),Vector3(9.7,1.8,-12.7),Vector3(8.3,1.8,-12.5),Vector3(20.3,1.8,-13.3)]:
		await place(point)
		await settle()
		await screen("near_warehouse_"+label+"_"+str(point.x))
	print("NEAR_WALL_REVEAL: %d checks, %d failures"%[checks,failures])
	scene.queue_free()
	await process_frame
	quit(1 if failures else 0)
