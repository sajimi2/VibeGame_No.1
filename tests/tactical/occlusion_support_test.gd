extends "res://tests/tactical/wall_occlusion_test.gd"
## 实际画面区分承托面和遮挡物：高台/地板/坡桥不得漏底，薄墙帽不能遗留在透视圆内。
var saved_visibility: Dictionary={}

func run() -> void:
	ProjectSettings.set_setting("tactical/testing",true)
	DirAccess.make_dir_recursive_absolute("res://work/occlusion")
	scene=load("res://scenes/waystation_blockout.tscn").instantiate()
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
	await place(Vector3(8.3,1.8,-12.5))
	var terrace: MeshInstance3D=scene.get_node("Terrain/WarehouseTerrace/Visual")
	var cap: MeshInstance3D=scene.get_node("Architecture/RampRailNorth/ArtFinish/Masonry")
	check(not controller.registered.has(terrace.get_instance_id()),"石砌高台明确排除透视，不因与墙共用材质被挖空")
	check(controller.registered.has(cap.get_instance_id()),"矮墙压顶虽薄于 0.25m，仍随墙体一起透视")
	var supports: Array[Node]=[terrace,scene.get_node("Architecture/WarehouseFloor"),scene.get_node("Terrain/SouthAccess/TimberBridge"),scene.get_node("Terrain/NorthAccess/TimberBridge")]
	for support in supports:
		var kept:=true
		var visual_nodes: Array[Node]=[support]
		visual_nodes.append_array(support.find_children("*","MeshInstance3D",true,false))
		for visual in visual_nodes:
			if visual is MeshInstance3D and controller.registered.has(visual.get_instance_id()): kept=false
		check(kept,"承托结构全体保留 "+str(support.name))
	if DisplayServer.get_name()!="headless":
		await support_pixels(supports)
		await thin_trim()
		for roof in scene.get_node("Roofs").get_children(): roof.set_physics_process(true)
		var index:=0
		for point in [Vector3(8.3,1.8,-12.5),Vector3(8.3,1.8,-6),Vector3(14,1.8,-14.7),Vector3(20.3,1.8,-13.3)]:
			await place(point)
			await settle()
			await screen("support_"+("before" if "--baseline" in OS.get_cmdline_user_args() else "after")+"_"+str(index))
			index+=1
	print("OCCLUSION_SUPPORT: %d checks, %d failures"%[checks,failures])
	scene.queue_free()
	await process_frame
	quit(1 if failures else 0)

## 暂时只显示真实承托几何，逐像素比较开关前后，避免上方墙体变化污染断言。
func support_pixels(supports: Array[Node]) -> void:
	for item in scene.find_children("*","GeometryInstance3D",true,false):
		saved_visibility[item]=item.visible
		item.hide()
	scene.environment_pixels.show()
	var points: Array[Vector3]=[Vector3(8.3,1.8,-12.5),Vector3(13,1.8,-9),Vector3(5,.9,0),Vector3(5,.9,-20)]
	for i in supports.size():
		await place(points[i])
		var nodes: Array[Node]=[supports[i]]
		nodes.append_array(supports[i].find_children("*","MeshInstance3D",true,false))
		for node in nodes:
			if node is GeometryInstance3D: node.show()
		controller.reveal=0
		controller._publish()
		var solid:=await screen()
		controller.reveal=1
		controller._publish()
		var opened:=await screen()
		check(solid.get_data()==opened.get_data(),"真实 GPU 开透视不改变承托面任何像素 "+str(supports[i].name))
		for node in nodes:
			if node is GeometryInstance3D: node.hide()
		var empty:=await screen()
		check(solid.get_data()!=empty.get_data(),"对比中承托结构确实可见 "+str(supports[i].name))
	for item in saved_visibility: item.visible=saved_visibility[item]

## 独立薄压顶放在圆心，背景保留阴影；若仍按厚度跳过，就会留下整条亮石片。
func thin_trim() -> void:
	await place(Vector3(0,.02,26))
	scene.environment_pixels.set_enabled(false,false)
	bodies(false)
	hints(false)
	var trim:=board(Vector3(2,.16,.6),Vector3(0,0,2))
	# 独立检验薄压顶材质的全透能力，构件触发和分组由 selective_wall 专项覆盖。
	controller.groups[controller._group_owner(trim).get_instance_id()].weight=1.0
	controller.reveal=1
	controller._publish()
	var opened:=await screen()
	trim.mesh=null
	var empty:=await screen()
	var center: Vector2=scene.camera.unproject_position(scene.player.position+Vector3.UP*.8)
	var leaks:=0
	for y in range(int(center.y)-3,int(center.y)+3):
		for x in range(int(center.x)-30,int(center.x)+30):
			if opened.get_pixel(x,y)!=empty.get_pixel(x,y): leaks+=1
	print("THIN_TRIM residual_pixels=",leaks)
	check(leaks==0,"薄墙帽在全透核心没有孤立残留面")
	trim.queue_free()
	await process_frame
	bodies(true)
	hints(true)
	scene.environment_pixels.set_enabled(true,false)
