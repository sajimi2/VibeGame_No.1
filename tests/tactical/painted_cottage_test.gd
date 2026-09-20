extends "res://tests/tactical/waystation_blockout_test.gd"
## 验证真实穿门、绕屋、分层透视与对比隔离；图片美术质量另外检查运行截图。
func shot(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	for i in 3: await process_frame
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png("res://work/painted_cottage/"+label+".png")

func collision_state() -> Dictionary:
	var result: Dictionary={}
	for node in scene.cottage.find_children("*","CollisionShape3D",true,false):
		result[str(node.get_path())]=[node.shape.get_rid(),node.global_transform,node.disabled]
	return result

## 实际绘制一个前后移动的标记，验证插画写入空间深度，而不是始终盖住人物的 UI 图片。
func depth_probe(point: Vector3,label: String) -> void:
	if DisplayServer.get_name()=="headless":
		print("SKIP "+label+" requires GPU")
		return
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
		probe.global_position=point+scene.camera.global_basis.z*(.22 if front else -.22)
		for i in 3: await process_frame
		RenderingServer.force_draw(false)
		var image: Image=root.get_texture().get_image()
		var pixel: Vector2i=Vector2i(scene.camera.unproject_position(point))
		var color: Color=image.get_pixelv(pixel)
		var visible: bool=color.r>.7 and color.b>.7 and color.g<.25
		check(visible==front,label+(" 前方物体可见" if front else " 后方物体被绘画遮挡"))
	probe.queue_free()
	await process_frame

func run() -> void:
	ProjectSettings.set_setting("tactical/testing",true)
	DirAccess.make_dir_recursive_absolute("res://work/painted_cottage")
	scene=load("res://tools/painted_cottage_lab.tscn").instantiate()
	root.add_child(scene)
	current_scene=scene
	scene.player.test_mode=true
	for i in 35: await physics_frame
	check(scene.painting.ready_for_comparison and scene.painting.cards.size()==7,"七片插画完成墙/顶/内景绑定")
	check(scene.player.is_on_floor() and not scene.progress_enabled,"门前落地且不写玩家存档")
	check(is_equal_approx(scene.camera.size,17.0/1.2) and scene.camera.rotation_degrees.is_equal_approx(Vector3(-35,25,0)),"保持原正交视角、角色尺寸基准")
	var collisions:=collision_state()
	await shot("play_entry")
	scene.set_physics_process(false)
	scene.camera.position=scene.snapped_camera_position(Vector3(0,1,0)+scene.camera.global_basis.z*26)
	scene.environment_pixels._process(0)
	scene.hud.hide()
	await shot("painted_exterior")
	await depth_probe(Vector3(-1.6,1.4,3.025),"墙面插画深度")
	await depth_probe(Vector3(1.5,4.13-1.5*.52,0),"屋顶插画深度")
	key(KEY_V)
	for i in 5: await physics_frame
	check(not scene.painting.enabled and not scene.second_painting.enabled,"V 切换两栋为原贴面")
	check(collision_state()==collisions,"美术对比不改变任何碰撞资源或变换")
	await shot("old_exterior")
	key(KEY_V)
	for i in 5: await physics_frame
	scene.set_physics_process(true)
	await walk([Vector3(0,0,0)],"真实步行穿过原门洞")
	for i in 35: await physics_frame
	check(scene.cottage.roof.inside and scene.cottage.roof.interior_fade==1,"进入室内整组屋顶低透明度")
	check(scene.painting.bindings[2].material.get_shader_parameter("roof_opacity")==scene.cottage.roof.roof_material.get_shader_parameter("roof_opacity"),"插画屋顶接收原控制器的实际淡化参数")
	check(scene.second_cottage.roof.interior_fade==0,"第一栋的透视不会联动第二栋")
	var floor_visual: Node=scene.cottage.get_node("SupportFloor/Visual")
	check(not scene.wall_occlusion.registered.has(floor_visual.get_instance_id()),"承托地板不进入墙体透视")
	await shot("painted_inside")
	scene.player.test_motion=Vector2.RIGHT
	for i in 70: await physics_frame
	scene.player.test_motion=Vector2.ZERO
	check(scene.player.position.x<2.16,"绘画旁的实体墙仍阻挡移动")
	var ray:=PhysicsRayQueryParameters3D.create(Vector3(4,1.2,0),Vector3(0,1.2,0),8)
	check(not scene.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(),"原墙继续阻挡弹道检测")
	await walk([Vector3(0,0,0),Vector3(0,0,5.2)],"原门洞出屋")
	await walk([Vector3(4,0,5.2),Vector3(4,0,-4.5),Vector3(-4,0,-4.5),Vector3(-4,0,5.2),Vector3(0,0,5.2)],"真实四面绕屋通行")
	key(KEY_3)
	for i in 45: await physics_frame
	check(scene.wall_occlusion.ratio>=.9 and scene.wall_occlusion.reveal==1,"屋后遮挡仍由原三角面采样触发")
	await shot("painted_behind")
	key(KEY_4)
	for i in 40: await physics_frame
	await shot("second_cottage")
	check(scene.cottage.roof.interior_fade==0 and scene.second_cottage.roof.interior_fade==0,"离开后两栋屋顶独立恢复")
	print("PAINTED_COTTAGE: %d checks, %d failures"%[checks,failures])
	scene.queue_free()
	await process_frame
	quit(1 if failures else 0)
