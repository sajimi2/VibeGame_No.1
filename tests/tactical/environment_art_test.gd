extends SceneTree
## 环境接入与真实 GPU 像素检查；屋檐外遮人必须触发开孔，圆外屋面和固定阴影保持。
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
func place(point: Vector3,n:=35) -> void:
	scene.player.position=point
	scene.player.velocity=Vector3.ZERO
	scene.update_camera_position()
	await frames(n)
	scene.player._update_occlusion()
func screen() -> Image:
	await process_frame
	RenderingServer.force_draw(false)
	return root.get_texture().get_image()
func run() -> void:
	ProjectSettings.set_setting("tactical/testing",true)
	DirAccess.make_dir_recursive_absolute("res://work/environment")
	scene=load("res://scenes/waystation_blockout.tscn").instantiate()
	scene.combat_enabled=false
	root.add_child(scene)
	current_scene=scene
	scene.player.test_mode=true
	scene.player.set_physics_process(false)
	for label in scene.review_labels: label.hide()
	await frames(3)
	var roof: Node3D=scene.get_node("Roofs/WarehouseRoof")
	check(scene.get_node("Terrain/Ground/Visual").material_override.resource_path.ends_with("grass.tres"),"驿站使用磁盘草地材质")
	check(scene.get_node("Architecture/WarehouseBack/ArtFinish").get_child_count()<=4,"整面建筑按材质合并网格，不逐条木梁增加绘制节点")
	for id in ["SouthAccess","NorthAccess"]:
		var ramp: Node3D=scene.get_node("Terrain/"+id)
		check(not ramp.get_node("Visual").visible and ramp.has_node("TimberBridge/Planks") and ramp.get_node("Collision").shape is ConvexPolygonShape3D,id+" 木架外观复用原连续碰撞")
	await place(Vector3(0,.05,26))
	check(roof.reveal==0 and roof.visible,"没有挡住玩家的屋顶完整显示")
	await place(Vector3(13,1.8,-9),5)
	check(roof.blocked and roof.reveal>0 and roof.reveal<1,"进入屋面投影后经过渐变过程")
	await frames(30)
	check(roof.reveal==1 and roof.visible,"室内只打开局部窗口，不隐藏整栋屋顶")
	check(scene.get_node("Roofs/CommandRoof").reveal==0,"各屋顶只处理自身遮挡")
	var center: Vector2=roof.roof_material.get_shader_parameter("reveal_center")
	await place(Vector3(8.1,1.8,-9))
	check(not roof.inside and roof.blocked and roof.reveal==1,"复现屋檐外：不在地面范围内仍按视线打开透视圆")
	check(scene.player.occluded,"屋顶开孔后前墙仍有真实遮挡；局部灰色由 occlusion_presentation 实测")
	check(roof.roof_material.get_shader_parameter("reveal_center").distance_to(center)<.01,"跟随镜头移动后，圆心仍以人物屏幕位置为准")
	await place(Vector3(13,8,-9))
	check(not roof.blocked and roof.reveal==0,"人物位于屋面上方时不误开孔")
	await place(Vector3(13,1.8,-11))
	scene.player.crouched=true
	await frames(5)
	check(roof.blocked and roof.reveal==1,"下蹲仍检测脚胸头的真实遮挡")
	scene.player.crouched=false
	await place(Vector3(0,.05,26),4)
	check(roof.reveal>0,"离开遮挡保留短暂滞回")
	await frames(35)
	check(roof.reveal==0,"离开后恢复全部屋面")
	if DisplayServer.get_name()!="headless": await rendered(roof)
	scene.queue_free()
	await process_frame
	# 另两个有效场景同样装配新草地和木架坡桥，不把只改驿站当作全部环境完成。
	for path in ["res://scenes/battlefield.tscn","res://scenes/tactical_height.tscn","res://tools/environment_preview.tscn"]:
		var other: Node3D=load(path).instantiate()
		other.encounter_enabled=false
		root.add_child(other)
		current_scene=other
		await frames(5)
		check(other.terrain.material("grass").shader!=null and not other.progress_enabled,path+" 共用材质且测试进度隔离")
		other.toggle_shading()
		other.toggle_shading()
		if DisplayServer.get_name()!="headless":
			var frame:=await screen()
			frame.save_png("res://work/environment/"+path.get_file().get_basename()+".png")
		other.queue_free()
		await process_frame
	print("ENVIRONMENT_ART: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)

## 同一个静止画面切换 shader 强度；直接比较像素，排除只有参数改变却没有正确开孔。
func rendered(roof: Node3D) -> void:
	await place(Vector3(13,1.8,-9))
	roof.set_physics_process(false)
	roof.roof_material.set_shader_parameter("reveal",0.0)
	var closed:=await screen()
	roof.roof_material.set_shader_parameter("reveal",1.0)
	var opened:=await screen()
	opened.save_png("res://work/environment/roof_circle.png")
	var size:=Vector2(opened.get_size())
	var center: Vector2=roof.roof_material.get_shader_parameter("reveal_center")*size
	var radius: float=roof.roof_material.get_shader_parameter("reveal_radius")
	var changed:=0
	var outside:=0
	for y in opened.get_height():
		for x in opened.get_width():
			if closed.get_pixel(x,y)!=opened.get_pixel(x,y):
				if Vector2(x,y).distance_to(center)<radius+3: changed+=1
				else: outside+=1
	check(changed>500,"真实 GPU 圆内屋瓦退去并露出玩家/地板")
	check(outside<40,"真实 GPU 圆外屋面与太阳阴影保持不变")
	roof.set_physics_process(true)
	await place(Vector3(8.1,1.8,-9))
	var eaves:=await screen()
	eaves.save_png("res://work/environment/roof_eaves.png")
