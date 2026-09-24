extends SceneTree
## 实际小院输入与投影回归：缩放、跟随、暂停、鼠标瞄准和屋顶透视共用当前相机。
var scene: Node3D
var checks:=0
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func frames(count: int) -> void:
	for i in count: await physics_frame
	await process_frame
func wheel(button: MouseButton,at:=Vector2(950,340),factor:=1.0) -> void:
	var event:=InputEventMouseButton.new()
	event.button_index=button
	event.pressed=true
	event.factor=factor
	event.position=at
	event.global_position=at
	root.push_input(event,true)
func centered() -> bool:
	var middle: Vector3=scene.player.position+Vector3.UP*.825
	return scene.camera.unproject_position(middle).distance_to(root.get_visible_rect().size*.5)<1.0
func shot(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://work/camera_zoom/"+label+".png")
func run() -> void:
	ProjectSettings.set_setting("tactical/testing",true)
	DirAccess.make_dir_recursive_absolute("res://work/camera_zoom")
	scene=load("res://scenes/courtyard_combat.tscn").instantiate()
	root.add_child(scene)
	current_scene=scene
	while not is_instance_valid(scene.progression): await frames(1)
	for enemy in get_nodes_in_group("tactical_enemies"): enemy.ai_enabled=false
	scene.player.test_mode=true
	await frames(5)
	check(centered(),"角色身体中心位于画面中心")
	check(is_equal_approx(scene.camera.size,17.0/1.2),"默认视野保持原倍率")
	await shot("default")
	var original_size: float=scene.camera.size
	var original_position: Vector3=scene.player.position
	var ui_rect: Rect2=scene.progression.view.quick_buttons[0].get_global_rect()
	wheel(MOUSE_BUTTON_WHEEL_UP)
	check(scene.camera_size_target<original_size and is_equal_approx(scene.camera.size,original_size),"滚轮向上设拉近目标，不瞬间跳变")
	await frames(1)
	check(scene.camera.size<original_size and scene.camera.size>scene.camera_size_target,"实际物理帧平滑接近目标")
	await frames(40)
	check(absf(scene.camera.size-scene.camera_size_target)<.002 and centered(),"缩放收敛后仍对准角色中心")
	check(scene.player.position.distance_to(original_position)<.01 and scene.player.scale==Vector3.ONE,"缩放不改变角色位置和世界尺寸")
	check(scene.progression.view.quick_buttons[0].get_global_rect()==ui_rect,"快捷栏不随世界缩放")
	for i in 35: wheel(MOUSE_BUTTON_WHEEL_UP)
	await frames(50)
	check(is_equal_approx(scene.camera.size,original_size*.5) and centered(),"连续拉近到达限位，角色保持居中")
	await shot("near")
	for i in 45: wheel(MOUSE_BUTTON_WHEEL_DOWN)
	await frames(50)
	check(is_equal_approx(scene.camera.size,original_size*2.0) and centered(),"连续拉远到达限位，角色保持居中")
	await shot("far")
	wheel(MOUSE_BUTTON_WHEEL_UP)
	check(scene.camera_size_target<original_size*2.0,"限位后反向滚动立即响应，无积压")
	await frames(40)
	scene.player.test_motion=Vector2.RIGHT
	await frames(25)
	scene.player.test_motion=Vector2.ZERO
	check(centered() and scene.player.position.distance_to(original_position)>.5,"移动中镜头继续居中跟随")
	var target: float=scene.camera_size_target
	scene.progression.view.toggle()
	wheel(MOUSE_BUTTON_WHEEL_UP,Vector2(600,180))
	await process_frame
	check(is_equal_approx(scene.camera_size_target,target),"背包暂停时滚轮不积累镜头缩放")
	scene.progression.view.toggle()
	# 在屋内拉近观察，核对缩放后的透视圆投影与真实画面。
	scene.player.position=Vector3(0,.03,0)
	scene.player.velocity=Vector3.ZERO
	for i in 12: wheel(MOUSE_BUTTON_WHEEL_UP)
	await frames(55)
	var roof: Node3D=scene.cottage.roof
	var expected: Vector2=scene.camera.unproject_position(scene.player.position+Vector3.UP*.768)
	var actual: Vector2=roof.roof_material.get_shader_parameter("reveal_center")*root.get_visible_rect().size
	check(roof.inside and roof.interior_fade>.99 and actual.distance_to(expected)<1,"缩放后的室内屋顶淡化与透视圆正确对齐")
	await shot("interior")
	# 固定真实指针后继续缩放，验证无 MouseMotion 时仍使用新的相机投影瞄准。
	scene.player.position=original_position
	scene.player.velocity=Vector3.ZERO
	if DisplayServer.get_name()!="headless":
		root.warp_mouse(Vector2(850,420))
		scene.player.test_mode=false
		wheel(MOUSE_BUTTON_WHEEL_DOWN)
		await frames(55)
		var aim_error:float=scene.camera.unproject_position(scene.player.aim_point).distance_to(root.get_mouse_position())
		if aim_error>=1: print("AIM_DIAGNOSTIC cursor=",root.get_mouse_position()," projected=",scene.camera.unproject_position(scene.player.aim_point)," error=",aim_error)
		check(aim_error<1,"真实指针静止时缩放后瞄准投影一致")
	else: print("SKIP 真实指针检查需要渲染窗口")
	print("COURTYARD_CAMERA: %d checks, %d failures"%[checks,failures])
	scene.queue_free()
	await process_frame
	quit(1 if failures else 0)
