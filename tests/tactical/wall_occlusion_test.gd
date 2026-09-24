extends "res://tests/tactical/occlusion_presentation_test.gd"
## 同时检查触发比例、原始几何反馈、真实屏幕残留与屋顶叠层；使用隔离场景不读写存档。
var controller: Node

func settle() -> void:
	for i in 45:
		controller._physics_process(1.0/60)
		await physics_frame

func board(size: Vector3,offset: Vector3) -> MeshInstance3D:
	var item:=MeshInstance3D.new()
	var box:=BoxMesh.new()
	box.size=size
	item.mesh=box
	item.material_override=preload("res://scripts/presentation/environment_library.gd").material("plaster")
	scene.add_child(item)
	item.global_transform=Transform3D(scene.camera.global_basis,scene.player.position+Vector3.UP*.8+scene.camera.global_basis*offset)
	controller.register_branch(item)
	return item

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
	for roof in scene.get_node("Roofs").get_children(): roof.set_physics_process(true)
	await place(Vector3(0,.02,26))
	await settle()
	check(controller.ratio==0 and controller.reveal==0,"无遮挡不开第二层透视圆")
	check(controller.sample_count>40,"按当前非透明身体轮廓采样，包含上下身")
	var left:=board(Vector3(3.6,7,.15),Vector3(-1.8,0,2))
	await settle()
	print("HALF ratio=",controller.ratio," samples=",controller.sample_count)
	check(controller.ratio>.2 and controller.ratio<.8 and controller.reveal==0,"半身被挡保持原灰色提示，不打开墙体圆")
	var right:=board(Vector3(3.6,7,.15),Vector3(1.8,0,2))
	await settle()
	print("FULL ratio=",controller.ratio," usec=",controller.sample_usec)
	check(controller.ratio>=.9 and controller.reveal==1,"多个小遮挡合计超过 90% 时打开圆")
	check(left.get_parent()==scene and left.find_children("*","CollisionShape3D",true,false).is_empty(),"纯视觉无碰撞墙也参与真实几何采样")
	for i in 4: await settle()
	check(controller.ratio>=.9 and controller.reveal==1,"淡化后仍按原始墙体判断，不反复开关")
	var poses_ok:=true
	var warm_cost:=0
	for direction in 12:
		for posture in [{"step":-1},{"step":3,"run":true},{"crouch":4},{"jump":2}]:
			var state: Dictionary=posture.duplicate()
			state.direction=direction
			state.move=direction
			scene.player.baked_visual.apply_frame(state)
			controller.measure()
			poses_ok=poses_ok and controller.sample_count>20 and controller.ratio>=.9
			controller.measure() # 二次采样排除首次静态图页载入，记录持续运行成本。
			warm_cost=maxi(warm_cost,controller.sample_usec)
	print("POSE_PROBE max_warm_usec=",warm_cost)
	check(poses_ok,"十二朝向站立/疾跑/蹲姿/跳跃均使用当前身体轮廓")
	scene.player._refresh_art(-1)
	if DisplayServer.get_name()!="headless": await pixels([left,right])
	left.hide()
	right.hide()
	controller.measure()
	controller._physics_process(.11)
	check(controller.reveal>0,"离开时短暂缓冲而非瞬间恢复")
	await settle()
	check(controller.reveal==0,"离开墙体后正常恢复不透明")
	var back:=board(Vector3(4,3,.15),Vector3(0,0,-2))
	await settle()
	check(controller.ratio==0 and controller.reveal==0,"人物身后的墙不算前景遮挡")
	back.hide()
	# 覆盖率滞回独立于渐变：避免动作边缘在 90% 附近抖动。
	controller.sample_clock=10
	controller.ratio=.85
	controller.engaged=true
	controller._physics_process(.01)
	check(controller.engaged,"已开启后 85% 区间保持，不在 90% 阈值反复切换")
	controller.sample_clock=0
	await warehouse()
	print("WALL_OCCLUSION: %d checks, %d failures"%[checks,failures])
	scene.queue_free()
	await process_frame
	quit(1 if failures else 0)

## 真正对比实体墙、淡化墙、移除墙：中心全透，向外递增到 22%，圆外与阴影完全一致。
func pixels(boards: Array) -> void:
	scene.environment_pixels.set_enabled(false,false)
	hints(false)
	bodies(false)
	controller.reveal=0
	controller._publish()
	var solid:=await screen()
	controller.reveal=1
	controller._publish()
	var faded:=await screen("wall_faded")
	var meshes: Array=[]
	for item in boards:
		meshes.append(item.mesh)
		item.mesh=null # 保持子节点阴影代理，参考图只移除可见墙面。
	var removed:=await screen()
	for i in boards.size(): boards[i].mesh=meshes[i]
	var mat: ShaderMaterial=boards[0].get_active_material(0)
	var center: Vector2=mat.get_shader_parameter("wall_center")*Vector2(1280,720)
	var radius: float=mat.get_shader_parameter("wall_radius")
	var ring: float=radius-mat.get_shader_parameter("wall_feather")
	var core: float=radius*mat.get_shader_parameter("wall_clear_core")
	var middle: float=(core+ring)*.5
	var changed:=0
	var outside:=0
	var remains:=0
	var total:=0
	var core_remaining:=0
	var middle_remaining:=0
	var middle_total:=0
	for y in range(720):
		for x in range(1280):
			var distance:=Vector2(x,y).distance_to(center)
			if solid.get_pixel(x,y)!=faded.get_pixel(x,y):
				changed+=1
				if distance>radius+2: outside+=1
			if distance<core-2 and faded.get_pixel(x,y)!=removed.get_pixel(x,y): core_remaining+=1
			if absf(distance-middle)<3 and solid.get_pixel(x,y)!=removed.get_pixel(x,y):
				middle_total+=1
				if solid.get_pixel(x,y)==faded.get_pixel(x,y): middle_remaining+=1
			if absf(distance-ring)<3 and solid.get_pixel(x,y)!=removed.get_pixel(x,y):
				total+=1
				if solid.get_pixel(x,y)==faded.get_pixel(x,y): remains+=1
	var coverage:=float(remains)/maxi(1,total)
	print("WALL_PIXELS coverage=",coverage," outside=",outside)
	check(changed>1000 and outside==0,"只改变圆内前景墙，圆外及太阳阴影保持一致")
	check(core_remaining==0,"圆心小范围完全透出，不在人物周围残留墙面网点")
	var middle_coverage:=float(middle_remaining)/maxi(1,middle_total)
	check(middle_coverage>.07 and middle_coverage<.15 and coverage>.19 and coverage<.25,"中心向外逐渐增加，过渡中段约 11%、残影环约 22%")
	check(is_equal_approx(radius,3.375*720/scene.camera.size),"两个透视圆半径从 2.25m 统一放大 50% 到 3.375m")
	check(is_equal_approx(mat.get_shader_parameter("wall_radius"),scene.get_node("Roofs/WarehouseRoof").roof_material.get_shader_parameter("reveal_radius")),"第二层与屋顶透视圆尺寸相同")
	bodies(true)
	hints(true)
	await screen("wall_with_player")
	scene.environment_pixels.set_enabled(true,false)
	await screen("wall_with_player_coarse")
	await moving_wall()
	root.mode=Window.MODE_EXCLUSIVE_FULLSCREEN
	await frames(8)
	controller._publish()
	check(mat.get_shader_parameter("wall_center")==scene.get_node("Roofs/WarehouseRoof").roof_material.get_shader_parameter("reveal_center"),"全屏两层圆心保持对齐")
	await screen("wall_fullscreen")
	root.mode=Window.MODE_WINDOWED
	await frames(8)

## 对齐真实镜头平移后比较圆内墙面，防止淡化网点引入上一轮已修复的移动闪烁。
func moving_wall() -> void:
	var start: Vector3=scene.camera.position
	var unit: float=scene.camera.size/720.0
	var base: Image
	var worst:=0.0
	for step in 9:
		scene.camera.position=start+(scene.camera.global_basis.x+scene.camera.global_basis.y)*unit*step
		scene.environment_pixels._process(0)
		controller._publish()
		var frame:=await screen()
		if step==0: base=frame
		else:
			var changed:=0
			var count:=0
			for y in range(255,400):
				for x in range(565,705):
					var a:=base.get_pixel(x,y)
					var b:=frame.get_pixel(x-step,y+step)
					count+=1
					if maxf(maxf(absf(a.r-b.r),absf(a.g-b.g)),absf(a.b-b.b))>8.0/255: changed+=1
			worst=maxf(worst,float(changed)/count)
	print("FADED_WALL_MOVEMENT worst=",worst)
	check(worst<.01,"第二层圆内墙面平移对齐后明显跳变小于 1%")
	scene.camera.position=start
	scene.environment_pixels._process(0)
	controller._publish()

func warehouse() -> void:
	# 仓库北侧外墙，脚下不在 interior 内，屋顶圆与低覆盖率墙圆应独立同时工作。
	await place(Vector3(14,1.8,-15.0))
	await settle()
	var roof: Node=scene.get_node("Roofs/WarehouseRoof")
	print("WAREHOUSE ratio=",controller.ratio," roof=",roof.reveal," inside=",roof.inside)
	check(not roof.inside and roof.interior_fade==0,"仓库外侧不会触发整片屋顶室内淡化")
	check(controller.ratio>=.9 and controller.reveal==1 and roof.reveal==1,"仓库背面被墙全挡时，两层圆同时生效")
	if DisplayServer.get_name()!="headless": await screen("warehouse_two_circles")
	await place(Vector3(13,1.8,-9))
	await settle()
	check(roof.interior_fade==1 and roof.reveal==1,"进入仓库保留上一轮的整顶淡化和顶层圆")
	if DisplayServer.get_name()!="headless": await screen("warehouse_inside_wall_layer")
