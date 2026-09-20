extends SceneTree
## 移动专项：抵消真实相机位移后比较同一处环境，检出静态截图无法发现的抽样闪烁。
var scene: Node3D
var checks := 0
var failures := 0
var report: Array = []

func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func freeze(node: Node) -> void:
	node.set_physics_process(false)
	node.set_process(false)
	for child in node.get_children(): freeze(child)
func screen() -> Image:
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	var frame: Image = root.get_texture().get_image()
	frame.convert(Image.FORMAT_RGB8)
	return frame

## 相机右移使世界左移、上移使世界下移；比较时对齐，不把正常滚屏算成闪烁。
func residual(reference: Image,current: Image,shift: Vector2i) -> float:
	var a := reference.get_data()
	var b := current.get_data()
	var stride := reference.get_width()*3
	var count := 0
	var changed := 0
	for y in range(100,600,2):
		for x in range(70,1210,2):
			var first := y*stride+x*3
			var next := (y+shift.y)*stride+(x-shift.x)*3
			count+=1
			if maxi(maxi(absi(a[first]-b[next]),absi(a[first+1]-b[next+1])),absi(a[first+2]-b[next+2]))>8: changed+=1
	return float(changed)/count

func run() -> void:
	if DisplayServer.get_name()=="headless":
		print("SKIP 环境移动稳定性需要实际 GPU 渲染")
		quit()
		return
	ProjectSettings.set_setting("tactical/testing",true)
	DirAccess.make_dir_recursive_absolute("res://work/environment_motion/regression")
	scene = load("res://scenes/waystation_blockout.tscn").instantiate()
	scene.combat_enabled = false
	root.add_child(scene)
	current_scene = scene
	scene.player.test_mode = true
	for i in 15: await physics_frame
	freeze(scene)
	scene.player.hide()
	scene.combat.hide()
	scene.hud.hide()
	for label in scene.review_labels: label.hide()
	# 屋顶透视和角色动画本就随玩家变化；此专项固定它们，只检测静态环境纹理的时间稳定性。
	for roof in scene.get_node("Roofs").get_children(): roof.roof_material.set_shader_parameter("reveal",0.0)
	await warehouse_post()
	var places := {"wall_tiles":Vector3(5,.02,4),"wilderness":Vector3(-40,.02,25)}
	for mode in ["window","fullscreen"]:
		if mode=="fullscreen":
			root.mode=Window.MODE_EXCLUSIVE_FULLSCREEN
			for i in 15: await process_frame
		for location in places:
			scene.player.position=places[location]
			scene.update_camera_position()
			var start: Vector3=scene.camera.position
			var unit: float=scene.camera.size/720.0
			for axis in [Vector2i(1,0),Vector2i(0,1),Vector2i(-1,-1)]:
				for enabled in [false,true]:
					scene.environment_pixels.set_enabled(enabled,false)
					var base: Image
					var worst := 0.0
					var mean := 0.0
					for step in 9:
						var shift: Vector2i=axis*step
						scene.camera.position=scene.snapped_camera_position(start+(scene.camera.global_basis.x*shift.x+scene.camera.global_basis.y*shift.y)*unit)
						scene.environment_pixels._process(0)
						var frame := await screen()
						if step==0:
							base=frame
							if axis==Vector2i(1,0): frame.save_png("res://work/environment_motion/regression/"+mode+"_"+location+("_coarse" if enabled else "_original")+".png")
						else:
							var error := residual(base,frame,shift)
							mean+=error/8.0
							worst=maxf(worst,error)
					var label: String = mode+"/"+location+"/"+str(axis)+("/coarse" if enabled else "/original")
					report.append({"case":label,"mean_changed":mean,"worst_changed":worst})
					print(label," mean/worst=",mean,"/",worst)
					check(worst<.01,label+" 对齐后明显跳变像素低于 1%")
	FileAccess.open("res://work/environment_motion/regression/metrics.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	scene.queue_free()
	await process_frame
	print("ENVIRONMENT_MOTION: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)

## 仓库端柱曾与墙芯共面；单独检查小区域，避免柱子的跳变被全画面统计稀释。
func warehouse_post() -> void:
	scene.player.position=Vector3(10.3,1.8,-5)
	scene.update_camera_position()
	var start: Vector3=scene.camera.position
	var unit: float=scene.camera.size/720.0
	var center: Vector2i=Vector2i(scene.camera.unproject_position(Vector3(9,3.6,-3.97)))
	var region:=Rect2i(center-Vector2i(8,24),Vector2i(16,48))
	for enabled in [false,true]:
		scene.environment_pixels.set_enabled(enabled,false)
		var reference: Image
		var worst:=0.0
		for step in 13:
			scene.camera.position=start+scene.camera.global_basis.x*unit*step
			scene.environment_pixels._process(0)
			var frame:=await screen()
			var crop:=frame.get_region(Rect2i(region.position-Vector2i(step,0),region.size))
			if step==0:
				reference=crop
				frame.save_png("res://work/environment_motion/regression/warehouse_post_"+("coarse" if enabled else "original")+".png")
			else:
				var changed:=0
				for y in crop.get_height():
					for x in crop.get_width():
						var a:=reference.get_pixel(x,y)
						var b:=crop.get_pixel(x,y)
						if maxf(maxf(absf(a.r-b.r),absf(a.g-b.g)),absf(a.b-b.b))>8.0/255: changed+=1
				worst=maxf(worst,float(changed)/(region.size.x*region.size.y))
		var label: String="warehouse_post/"+("coarse" if enabled else "original")
		report.append({"case":label,"worst_changed":worst})
		print(label," worst=",worst)
		check(worst<.005,label+" 端柱局部移动跳变低于 0.5%")
