extends "res://tests/tactical/waystation_blockout_test.gd"
## 使用真实物理验证绘画院子的入口、绕行与对比隔离；同时保存 GPU 画面供美术检查。
func shot(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	for i in 3: await process_frame
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png("res://work/painted_courtyard/"+label+".png")

func run() -> void:
	ProjectSettings.set_setting("tactical/testing",true)
	DirAccess.make_dir_recursive_absolute("res://work/painted_courtyard")
	scene=load("res://tools/painted_courtyard_lab.tscn").instantiate()
	root.add_child(scene)
	current_scene=scene
	scene.player.test_mode=true
	for i in 35: await physics_frame
	check(scene.ready_to_test and scene.courtyard.props.size()==16,"16 个实物完成装配")
	check(scene.player.is_on_floor() and not scene.progress_enabled,"安全落地且隔离存档")
	check(is_equal_approx(scene.camera.size,17.0/1.2),"保持角色显示基准")
	await shot("entry")
	scene.set_physics_process(false)
	scene.camera.position=scene.snapped_camera_position(Vector3(0,2,5)+scene.camera.global_basis.z*26)
	scene.environment_pixels._process(0)
	scene.hud.hide()
	await shot("overview")
	if "--quick" in OS.get_cmdline_user_args(): quit(); return
	scene.set_physics_process(true)
	await walk([Vector3(0,0,5),Vector3(0,0,0)],"真实步行通过院门与房门")
	for i in 35: await physics_frame
	check(scene.cottage.roof.inside and scene.cottage.roof.interior_fade==1,"室内屋顶透视保留")
	await shot("inside")
	await walk([Vector3(0,0,5),Vector3(-2.5,0,5),Vector3(-2.5,0,8),Vector3(-6.4,0,8),Vector3(-6.4,0,4.2),Vector3(-3.2,0,4.2),Vector3(0,0,5)],"水井两侧可真实绕行")
	key(KEY_3)
	for i in 20: await physics_frame
	await shot("well")
	key(KEY_4)
	for i in 20: await physics_frame
	await walk([Vector3(3,0,7.5),Vector3(7,0,7.5),Vector3(7,0,4),Vector3(3,0,4),Vector3(3,0,7.5)],"推车前后可真实绕行")
	await shot("cart")
	var shapes: Array=scene.courtyard.find_children("*","CollisionShape3D",true,false)
	check(shapes.size()==16,"每件实物一个简单碰撞，花草和动态装饰无碰撞")
	var before: Array=[]
	for shape in shapes: before.append([shape.shape.get_rid(),shape.global_transform,shape.disabled])
	key(KEY_F3)
	await shot("collisions")
	key(KEY_V)
	await shot("volumes")
	var after: Array=[]
	for shape in shapes: after.append([shape.shape.get_rid(),shape.global_transform,shape.disabled])
	check(before==after,"外观/碰撞显示切换不更改物理")
	key(KEY_V)
	key(KEY_F3)
	key(KEY_F4)
	check(not scene.courtyard.ambience.visible and not scene.courtyard.ambience.animated,"F4 关闭动态装饰")
	key(KEY_F4)
	check(scene.courtyard.ambience.visible and scene.courtyard.ambience.animated,"F4 恢复动态装饰")
	scene.player.position=Vector3(-5.2,.1,13)
	for i in 20: await physics_frame
	scene.player.test_motion=Vector2(0,-1)
	for i in 65: await physics_frame
	scene.player.test_motion=Vector2.ZERO
	check(scene.player.position.z>11.7,"不规则矮墙背后的盒碰撞确实阻挡行走")
	print("PAINTED_COURTYARD: %d checks, %d failures"%[checks,failures])
	scene.queue_free()
	await process_frame
	quit(1 if failures else 0)
