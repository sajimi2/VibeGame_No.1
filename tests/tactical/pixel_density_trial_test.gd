extends SceneTree
## GPU对照验证：同机位前后、真实投影密度、切回无损、开合和移动；隔离玩家进度。
var lab:Node
var checks:=0
var failures:=0
const OUT="res://work/pixel_density_trial/"
func _initialize() -> void: run.call_deferred()
func frames(n:int) -> void:
	for i in n: await physics_frame
	await process_frame
func check(ok:bool, message:String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+message)
func shot(id:String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT+id+".png")
func run() -> void:
	if DisplayServer.get_name()=="headless":
		print("SKIP DENSITY_TRIAL requires GPU")
		quit()
		return
	DirAccess.make_dir_recursive_absolute(OUT)
	lab=load("res://tools/pixel_density_lab.tscn").instantiate()
	root.add_child(lab)
	current_scene=lab
	while not lab.ready_for_test: await process_frame
	var scene:Node3D=lab.scene
	scene.player.test_mode=true
	check(not scene.progression.persist,"实验入口隔离真实存档")
	check(lab.walls.size()==2,"只选择驿站角落两面墙")
	check(not scene.has_node("WorldPixelGrid"),"未装配整屏降采样")
	var shape_sizes:Array=[]
	for item in lab.walls: shape_sizes.append(item.prop.body.get_child(0).shape.size)
	for mode in 3:
		lab.choose_zoom(mode)
		await frames(65)
		for enabled in [false,true]:
			lab.set_calibrated(enabled)
			await frames(3)
			await shot(("after" if enabled else "before")+"_"+str(mode))
		var origin:Vector3=scene.player.position
		var ppm:float=scene.camera.unproject_position(origin+scene.camera.global_basis.x).distance_to(scene.camera.unproject_position(origin))
		if mode>0: check(absf(ppm/37.5-(2 if mode==1 else 3))<.005,"实际投影达到%d点/逻辑像素"%(2 if mode==1 else 3))
		for item in lab.walls:
			var prop:Node3D=item.prop
			var texture:Texture2D=prop.art_material.get_shader_parameter("illustration")
			check((texture.get_size()/prop.art.mesh.size-Vector2.ONE*37.5).length()<.001,"%s 两轴密度与人物一致，档位%d"%[prop.asset_id,mode])
	check(is_equal_approx(lab.chest.sprite.pixel_size,scene.player.baked_visual.pixel_size),"宝箱逻辑像素世界尺寸等于人物")
	check(lab.trial_frames.all(func(t):return t.get_size()==Vector2(53,75)),"四帧均为53×75且脚点共用")
	var foot:Vector3=lab.chest.sprite.position
	lab.chest.set_open(true)
	await frames(25)
	check(lab.chest.frame==3 and lab.chest.sprite.position==foot,"真实开箱动画完成且脚点不跳")
	await shot("open")
	lab.chest.set_open(false)
	await frames(25)
	check(lab.chest.frame==0,"合箱动画完成")
	lab.choose_zoom(1)
	await frames(65)
	var before:Vector3=scene.player.position
	scene.player.test_motion=Vector2.LEFT
	await frames(20)
	scene.player.test_motion=Vector2.ZERO
	await frames(5)
	check(scene.player.position.distance_to(before)>.3,"实际移动和镜头跟随正常")
	await shot("moved")
	lab.set_calibrated(false)
	var restored:=true
	for i in lab.walls.size():
		var item:Dictionary=lab.walls[i]
		restored=restored and item.prop.art.mesh.size==item.size and item.prop.body.get_child(0).shape.size==shape_sizes[i]
	check(restored and lab.chest.sprite.pixel_size==lab.old_chest_pixel,"切回恢复原尺寸，碰撞无变化")
	lab.set_calibrated(true)
	print("DENSITY_TRIAL: %d checks, %d failures"%[checks,failures])
	lab.queue_free()
	await frames(4)
	quit(1 if failures else 0)
