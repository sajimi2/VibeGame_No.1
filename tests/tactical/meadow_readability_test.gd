extends SceneTree
## 同机位 GPU 对照：坡面明暗调整只影响扩展区，不依赖网格、不改变几何或院内材质。
var lab: Node3D
var failures:=0
var checks:=0
func _initialize() -> void: run.call_deferred()
func frames(count: int) -> void:
	for i in count: await physics_frame
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+message)
func capture(label: String) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	var result:=root.get_texture().get_image()
	result.save_png("res://work/meadow_readability/"+label+".png")
	return result
func difference(a: Image,b: Image,rect: Rect2i) -> float:
	var result:=0.0
	for y in range(rect.position.y,rect.end.y):
		for x in range(rect.position.x,rect.end.x):
			var delta: Color=a.get_pixel(x,y)-b.get_pixel(x,y)
			result+=absf(delta.r)+absf(delta.g)+absf(delta.b)
	return result/(rect.size.x*rect.size.y*3)

func run() -> void:
	if DisplayServer.get_name()=="headless":
		print("SKIP MEADOW_READABILITY requires actual GPU")
		quit()
		return
	ProjectSettings.set_setting("tactical/testing",true)
	DirAccess.make_dir_recursive_absolute("res://work/meadow_readability")
	lab=load("res://scenes/courtyard_combat.tscn").instantiate()
	lab.story_mode=false # 显式运行保留的地形实验，F5 故事默认平地。
	lab.outskirts_mode=1
	root.add_child(lab)
	current_scene=lab
	while not lab.ready_to_test or not is_instance_valid(lab.objective): await frames(1)
	for enemy in get_nodes_in_group("tactical_enemies"):
		enemy.ai_enabled=false
		enemy.update_visuals(0)
	lab.objective.set_physics_process(false)
	lab.player.test_mode=true
	lab.courtyard.ambience.animated=false
	for control in lab.find_children("*","Control",true,false): control.tooltip_text=""
	var ground=lab.rolling_meadow
	var material: ShaderMaterial=ground.surface.material_override
	var height_before: PackedFloat32Array=ground.heights.duplicate()
	var collision_before: RID=ground.get_node("GroundCollision").shape.get_rid()
	for spec in [["hill",Vector2(23,3)],["valley",Vector2(23,14)],["ascent",Vector2(19,8)]]:
		var p: Vector2=spec[1]
		lab.player.position=Vector3(p.x,ground.height_at(p)+.05,p.y)
		lab.player.velocity=Vector3.ZERO
		await frames(8)
		# 同一帧姿势/镜头下只切换材质，排除人物、树叶、相机移动导致的假差分。
		lab.player.set_physics_process(false)
		lab.combat.set_physics_process(false)
		lab.set_physics_process(false)
		material.set_shader_parameter("relief_strength",0.0)
		var before:=await capture(spec[0]+"_before")
		material.set_shader_parameter("relief_strength",1.0)
		var after:=await capture(spec[0]+"_after")
		var delta:=difference(before,after,Rect2i(100,130,1080,410))
		print("RELIEF_DIFFERENCE %s %.4f"%[spec[0],delta])
		check(delta>.02,"%s 实际画面发生可测的宽幅改变"%spec[0])
		var gray:=StandardMaterial3D.new()
		gray.albedo_color=Color(.55,.55,.55)
		gray.roughness=1.0
		ground.surface.material_override=gray
		await frames(8)
		await capture(spec[0]+"_clay")
		ground.surface.material_override=material
		lab.player.set_physics_process(true)
		lab.combat.set_physics_process(true)
		lab.set_physics_process(true)
	# 从原院门观察，中心画面完全在扩展区以西，应保持逐像素一致。
	lab.player.position=Vector3(.8,.1,13.6)
	lab.player.velocity=Vector3.ZERO
	await frames(8)
	lab.player.set_physics_process(false)
	lab.combat.set_physics_process(false)
	lab.set_physics_process(false)
	material.set_shader_parameter("relief_strength",0.0)
	var court_before:=await capture("courtyard_before")
	material.set_shader_parameter("relief_strength",1.0)
	var court_after:=await capture("courtyard_after")
	var court_delta:=difference(court_before,court_after,Rect2i(200,160,550,280))
	print("COURTYARD_DIFFERENCE %.6f"%court_delta)
	check(court_delta<.001,"院内原画面保持不变")
	check(ground.heights==height_before and ground.get_node("GroundCollision").shape.get_rid()==collision_before,"对照过程不改变地形与碰撞")
	check(not material.get_shader_parameter("terrain_guides"),"对照图始终关闭地形网格")
	print("MEADOW_READABILITY: %d checks, %d failures"%[checks,failures])
	lab.queue_free()
	await process_frame
	quit(1 if failures else 0)
