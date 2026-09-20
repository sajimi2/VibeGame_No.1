extends SceneTree
## 真正切换原生窗口，覆盖暂停、重开与投影坐标；无头只检查装配，不冒充全屏实测。
var scene: Node3D
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ")+label)
func frames(n: int) -> void:
	for i in n: await process_frame
func key(code: Key,alt := false,echo := false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	event.alt_pressed = alt
	event.echo = echo
	Input.parse_input_event(event)
	await frames(12)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
func create_scene() -> void:
	scene = load("res://scenes/waystation_blockout.tscn").instantiate()
	scene.combat_enabled = false
	root.add_child(scene)
	current_scene = scene
	scene.player.test_mode = false
	scene.player.position = Vector3(13,1.8,-9)
	scene.update_camera_position()
	await frames(25)
func run() -> void:
	ProjectSettings.set_setting("tactical/testing",true)
	await create_scene()
	var control := root.get_node("GameWindowMode")
	check(control.process_mode==Node.PROCESS_MODE_ALWAYS,"窗口组件在暂停时仍接收输入")
	check(root.content_scale_size==Vector2i(1280,720) and root.content_scale_aspect==Window.CONTENT_SCALE_ASPECT_KEEP,"画布仍为 1280×720，宽高比固定")
	if control.is_editor_embedded():
		await key(KEY_F11)
		check(root.mode==Window.MODE_WINDOWED and is_instance_valid(control.embedded_hint) and control.embedded_hint.visible,"实际 --wid 内嵌收到 F11 后明确提示，不再请求无效全屏")
		paused = true
		await key(KEY_ENTER,true)
		check(root.mode==Window.MODE_WINDOWED and control.embedded_hint.visible and paused,"内嵌暂停时 Alt+Enter 同样提示，保持原暂停状态")
		paused = false
		scene.queue_free()
		await frames(2)
		print("DISPLAY_MODE_EMBEDDED: %d checks, %d failures"%[checks,failures])
		quit(1 if failures else 0)
		return
	if DisplayServer.get_name()!="headless":
		root.mode = Window.MODE_WINDOWED
		root.size = Vector2i(1280,720)
		root.position = Vector2i(50,50)
		await frames(15)
		var old_size := root.size
		var old_position := root.position
		var old_camera: float = scene.camera.size
		var old_screen: Vector2 = scene.camera.unproject_position(scene.player.position+Vector3.UP*.768)
		await key(KEY_F11)
		check(root.mode==Window.MODE_EXCLUSIVE_FULLSCREEN and root.size==DisplayServer.screen_get_size(root.current_screen),"F11 实际进入完整屏幕大小的游戏全屏")
		print("DISPLAY_STATE screen=",root.size," canvas=",root.get_visible_rect().size," scale=",root.get_final_transform().get_scale())
		# 验证内容实际显示面积，而不只是原生窗口占满屏幕；旧整数模式在 1080p 会卡在 1×。
		var displayed: Rect2 = root.get_final_transform()*root.get_visible_rect()
		var fit := minf(float(root.size.x)/1280,float(root.size.y)/720)
		check(displayed.size.distance_to(Vector2(1280,720)*fit)<1,"画面按最大等比例倍率铺满，1080p 实际为 1.5× 而非 1×")
		check(root.get_visible_rect().size==Vector2(1280,720) and is_equal_approx(scene.camera.size,old_camera),"切全屏保持画布、相机视野和人物世界大小")
		check(scene.player.cursor.distance_to(root.get_mouse_position())<1,"鼠标没有移动时，切换也刷新画布鼠标坐标")
		scene.player.update_aim(scene.player.cursor)
		check(scene.camera.unproject_position(scene.player.aim_point).distance_to(scene.player.cursor)<1,"全屏鼠标射线与世界命中点投影一致")
		var roof: Node3D = scene.get_node("Roofs/WarehouseRoof")
		check(roof.reveal>.99 and (roof.roof_material.get_shader_parameter("reveal_center")*Vector2(1280,720)).distance_to(old_screen)<1,"全屏透视圆仍对齐人物，屋面遮挡检测正常")
		await key(KEY_F11,false,true)
		check(root.mode==Window.MODE_EXCLUSIVE_FULLSCREEN,"长按重复事件不会连续切换")
		paused = true
		await key(KEY_ENTER,true)
		check(root.mode==Window.MODE_WINDOWED and paused,"暂停期间 Alt+Enter 可恢复窗口而不解除暂停")
		check(root.size==old_size and root.position==old_position,"恢复原窗口大小和位置")
		paused = false
		await key(KEY_ENTER)
		check(root.mode==Window.MODE_WINDOWED,"普通 Enter 不切换显示")
		await key(KEY_F11)
		var id := control.get_instance_id()
		scene.queue_free()
		await frames(2)
		await create_scene()
		check(root.get_node("GameWindowMode").get_instance_id()==id,"重开场景不重复创建组件或丢失窗口恢复记录")
		await key(KEY_F11)
		check(root.mode==Window.MODE_WINDOWED and root.size==old_size and root.position==old_position,"全屏中重开后仍能正确返回原窗口")
		root.mode = Window.MODE_MAXIMIZED
		await frames(15)
		await key(KEY_F11)
		await key(KEY_F11)
		check(root.mode==Window.MODE_MAXIMIZED,"从最大化进入全屏后恢复最大化状态")
		root.mode = Window.MODE_WINDOWED
	else: print("SKIP 原生全屏、鼠标坐标与显示器尺寸必须使用实际渲染进程验证")
	scene.queue_free()
	await frames(2)
	print("DISPLAY_MODE: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
