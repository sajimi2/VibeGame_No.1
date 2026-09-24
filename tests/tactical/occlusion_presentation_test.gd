extends SceneTree
## 用实际像素验证局部灰色、室内整顶淡化与室外圆孔；不以节点 visible 代替最终画面。
var scene: Node3D
var checks:=0
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func frames(n: int) -> void:
	for i in n: await physics_frame
func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): freeze(child)
func screen(label: String="") -> Image:
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	var result:=root.get_texture().get_image()
	if not label.is_empty(): result.save_png("res://work/occlusion/"+label+".png")
	return result
func hints(value: bool) -> void:
	for layer in scene.player.baked_visual.layers.values(): layer.occlusion.visible=value
func bodies(value: bool) -> void:
	for layer in scene.player.baked_visual.layers.values(): layer.body.visible=value
func place(point: Vector3) -> void:
	scene.player.position=point
	scene.player.velocity=Vector3.ZERO
	scene.update_camera_position()
	scene.player._refresh_art(-1)
	scene.environment_pixels._process(0)
	await frames(40)

func run() -> void:
	ProjectSettings.set_setting("tactical/testing",true)
	DirAccess.make_dir_recursive_absolute("res://work/occlusion")
	scene=load("res://tests/fixtures/legacy/waystation_blockout.tscn").instantiate()
	scene.combat_enabled=false
	root.add_child(scene)
	current_scene=scene
	scene.player.test_mode=true
	await frames(3)
	freeze(scene)
	scene.hud.hide()
	for label in scene.review_labels: label.hide()
	scene.combat.hide()
	scene.combat.hand.hide() # 手持模型挂在角色下；本专项只比较身体覆盖，避免刀柄遮住身体掩码。
	for roof in scene.get_node("Roofs").get_children(): roof.set_physics_process(true)
	if DisplayServer.get_name()!="headless":
		await partial_body()
		root.mode=Window.MODE_EXCLUSIVE_FULLSCREEN
		await frames(8)
		await partial_body()
	await roofs()
	scene.queue_free()
	await process_frame
	print("OCCLUSION_PRESENTATION: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)

## 遮挡物刻意不带物理碰撞：身体中心射线漏检时，灰色仍必须由实际可见深度正确裁切。
func partial_body() -> void:
	await place(Vector3(0,.02,26))
	var wall:=MeshInstance3D.new()
	var box:=BoxMesh.new()
	box.size=Vector3(2,.9,.1)
	wall.mesh=box
	var material:=StandardMaterial3D.new()
	material.albedo_color=Color("715649")
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	wall.material_override=material
	scene.add_child(wall)
	wall.global_position=scene.player.position+Vector3.UP*.45+scene.camera.global_basis.z*.6
	wall.rotation.y=scene.camera.rotation.y
	wall.hide()
	hints(false)
	var clear:=await screen()
	hints(true)
	var normal:=await screen("unblocked")
	check(clear.get_data()==normal.get_data(),"无遮挡时灰色层不改变任何可见像素")
	hints(false)
	bodies(false)
	var background:=await screen()
	bodies(true)
	wall.show()
	var blocked:=await screen("partial_without_hint")
	hints(true)
	var hinted:=await screen("partial_gray")
	var gray:=0
	var visible_body:=0
	var leaks:=0
	for y in range(210,430):
		for x in range(570,710):
			var is_body:=clear.get_pixel(x,y)!=background.get_pixel(x,y)
			var visible_pixel:=is_body and clear.get_pixel(x,y)==blocked.get_pixel(x,y)
			var changed:=hinted.get_pixel(x,y)!=blocked.get_pixel(x,y)
			if visible_pixel: visible_body+=1
			if changed:
				gray+=1
				if not is_body or visible_pixel: leaks+=1
	print("PARTIAL gray/visible/leaks=",gray,"/",visible_body,"/",leaks)
	check(gray>100 and visible_body>100,"半身遮挡同时保留正常身体与灰色被挡部分")
	check(leaks==0,"灰色不侵入露出的头手，也不画出身体轮廓之外的光圈")
	scene.player._update_occlusion()
	check(not scene.player.occluded,"无碰撞遮挡物确实未被旧中心射线检出")
	var refreshed:=await screen()
	check(refreshed.get_data()==hinted.get_data(),"中心射线未遮挡也不关闭真实的局部灰色提示")
	scene.environment_pixels.set_enabled(false,false)
	var original_environment:=await screen()
	var changed_hint:=0
	for y in range(210,430):
		for x in range(570,710):
			if hinted.get_pixel(x,y)!=blocked.get_pixel(x,y) and hinted.get_pixel(x,y)!=original_environment.get_pixel(x,y): changed_hint+=1
	check(changed_hint==0,"切换环境精度不改变灰色身体的颜色和精度")
	scene.environment_pixels.set_enabled(true,false)
	wall.queue_free()
	await process_frame

func roofs() -> void:
	var roof: Node3D=scene.get_node("Roofs/WarehouseRoof")
	await place(Vector3(0,.02,26))
	check(roof.interior_fade==0 and roof.reveal==0,"室外无遮挡时整顶不透明且不开圆孔")
	await place(Vector3(8.1,1.8,-9))
	check(not roof.inside and roof.reveal==1 and roof.interior_fade==0,"屋檐外仅开透视圆，不触发整体淡化")
	if DisplayServer.get_name()!="headless": await screen("outside_circle")
	await place(Vector3(13,1.8,-9))
	check(roof.inside and roof.interior_fade==1 and roof.reveal==1,"进入仓库：整顶淡化和局部圆同时生效")
	check(is_equal_approx(roof.roof_material.get_shader_parameter("roof_opacity"),roof.indoor_opacity),"室内屋顶保留约 22% 覆盖率，不全部剔除")
	check(scene.get_node("Roofs/CommandRoof").interior_fade==0,"进入仓库不淡化另一栋建筑")
	if DisplayServer.get_name()!="headless": await layered_roof(roof)
	await place(Vector3(13,8,-9))
	check(roof.interior_fade==0 and roof.reveal==0,"站在屋面上方不会触发室内或透视")
	await place(Vector3(13,1.8,-9))
	scene.player.position=Vector3(0,.02,26)
	scene.update_camera_position()
	await frames(2)
	check(roof.interior_fade>0,"离开室内短暂保留缓冲，不在门槛处瞬间开关")
	await frames(40)
	check(roof.interior_fade==0 and roof.reveal==0,"离开后整顶与圆孔都恢复")

## 与真正删除屋顶、仅淡化两种画面比较，证明残影和追加圆孔都实际参与了渲染。
func layered_roof(roof: Node3D) -> void:
	roof.set_physics_process(false)
	roof.roof_material.set_shader_parameter("reveal",0.0)
	var faded:=await screen("inside_faded_only")
	roof.roof_material.set_shader_parameter("reveal",1.0)
	var both:=await screen("inside_faded_and_circle")
	hints(false)
	var without_hint:=await screen()
	check(both.get_data()==without_hint.get_data(),"透视圆已露出的身体不再叠灰色或亮轮廓")
	hints(true)
	roof.roof_material.set_shader_parameter("roof_opacity",0.0)
	var removed:=await screen()
	var center: Vector2=roof.roof_material.get_shader_parameter("reveal_center")*Vector2(1280,720)
	var radius: float=roof.roof_material.get_shader_parameter("reveal_radius")
	var remains:=0
	var extra_hole:=0
	for y in range(110,640):
		for x in range(50,1230):
			if Vector2(x,y).distance_to(center)>radius+3:
				if both.get_pixel(x,y)!=removed.get_pixel(x,y): remains+=1
			elif faded.get_pixel(x,y)!=both.get_pixel(x,y): extra_hole+=1
	check(remains>500,"圆外仍保留半透明屋瓦的实际像素")
	check(extra_hole>100,"整体淡化之后，圆内继续额外透出角色周围")
	roof.roof_material.set_shader_parameter("roof_opacity",roof.indoor_opacity)
	await moving_roof(roof)
	roof.set_physics_process(true)

## 半透明网点应随世界表面平移；抵消镜头位移后比较，不能只验静止的透明度截图。
func moving_roof(roof: Node3D) -> void:
	var start: Vector3=scene.camera.position
	var unit: float=scene.camera.size/720.0
	var base: Image
	var worst:=0.0
	for step in 9:
		scene.camera.position=start+(scene.camera.global_basis.x+scene.camera.global_basis.y)*unit*step
		scene.environment_pixels._process(0)
		roof._physics_process(0)
		var frame:=await screen()
		if step==0: base=frame
		else:
			var changed:=0
			var count:=0
			for y in range(140,540,2):
				for x in range(390,1140,2):
					var a:=base.get_pixel(x,y)
					var b:=frame.get_pixel(x-step,y+step)
					count+=1
					if maxf(maxf(absf(a.r-b.r),absf(a.g-b.g)),absf(a.b-b.b))>8.0/255: changed+=1
			worst=maxf(worst,float(changed)/count)
	print("FADED_ROOF_MOVEMENT worst=",worst)
	check(worst<.01,"低透明屋面及圆孔移动对齐后明显跳变小于 1%")
	scene.camera.position=start
	scene.environment_pixels._process(0)
	roof._physics_process(0)
