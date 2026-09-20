extends SceneTree
## 灰盒验收走真实角色物理，覆盖主路双坡、侧路、仓库门洞和返程；不把节点存在视作可通行。
var scene: Node3D
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(value: bool, caption: String) -> void:
	checks += 1
	if not value: failures += 1
	print(("PASS " if value else "FAIL ")+caption)

func walk(points: Array, caption: String) -> void:
	var arrived := true
	for point in points:
		var reached := false
		for tick in 1000:
			var offset: Vector3 = point-scene.player.position
			if Vector2(offset.x,offset.z).length()<0.18:
				reached = absf(offset.y)<0.25
				break
			scene.player.test_motion = Vector2(offset.x,offset.z).normalized()
			await physics_frame
		if not reached:
			print("BLOCKED target=",point," actual=",scene.player.position)
			arrived=false
			break
	scene.player.test_motion=Vector2.ZERO
	check(arrived,caption)

func capture(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	for i in 3: await process_frame
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png("res://work/waystation/"+label+".png")

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode=code
	event.pressed=true
	scene._unhandled_input(event)

## 真实步行继续覆盖仓库门洞；局部透视/屋檐边缘/像素效果由 environment_art 专项验证。
func roofs_and_wilderness() -> void:
	scene.move_to_stop(2)
	for i in 30: await physics_frame
	var roof: Node3D=scene.get_node("Roofs/WarehouseRoof")
	check(roof.visible,"仓库外保留屋顶")
	await capture("roof_outside")
	await walk([Vector3(13,1.8,-9)],"真实步行进入仓库")
	for i in 30: await physics_frame
	check(roof.blocked and roof.reveal==1 and roof.visible,"室内打开局部透视圆，整体屋顶保留")
	await capture("roof_inside")
	await walk([Vector3(5,1.8,-9)],"仓库室内步行穿门返回室外")
	for i in 35: await physics_frame
	check(roof.reveal==0,"走出屋面投影后恢复屋顶")
	key(KEY_5)
	for i in 8: await physics_frame
	check(scene.player.is_on_floor() and scene.player.position.x < -27,"5 跳转至新增西侧野地")
	await capture("wilderness")
	await walk([Vector3(-40,0,-23),Vector3(-21,0,-23),Vector3(-21,0,29),Vector3(-40,0,29),Vector3(-40,0,25)],"林间通路与南北两处出入口完整连通")
	scene.set_overview(true)
	await capture("overview")
	scene.set_overview(false)

func run() -> void:
	ProjectSettings.set_setting("tactical/testing",true)
	DirAccess.make_dir_recursive_absolute("res://work/waystation")
	scene=load("res://scenes/waystation_blockout.tscn").instantiate()
	scene.combat_enabled=false
	root.add_child(scene)
	current_scene=scene
	scene.player.test_mode=true
	for i in 10: await physics_frame
	check(scene.player.is_on_floor(),"出生点安全落地")
	check(not scene.progress_enabled and scene.progression==null and scene.objective==null,"灰盒不装配任务或存档")
	check(get_nodes_in_group("tactical_enemies").is_empty(),"标记不生成战斗敌人")
	check(is_equal_approx(scene.camera.size,17.0/1.2),"步行保持已确认角色显示大小")
	await capture("entry")
	await walk([Vector3(0,0,10),Vector3(5,0,8),Vector3(5,0,4),Vector3(5,1.8,-9)],"主路经正门和南坡登上高台")
	await capture("terrace")
	await walk([Vector3(13,1.8,-9),Vector3(5,1.8,-9)],"仓库西门可双向进出")
	await walk([Vector3(5,0,-25),Vector3(0,0,-27),Vector3(0,0,-28)],"北坡下行进入内院目标区")
	await capture("inner")
	await walk([Vector3(0,0,-25),Vector3(5,0,-25),Vector3(5,1.8,-9),Vector3(5,0,8),Vector3(0,0,10)],"主路北坡上行、南坡下行均可原路返回")
	scene.move_to_stop(3)
	for i in 3: await physics_frame
	await walk([Vector3(-8,0,-27),Vector3(-8,0,12),Vector3(-13,0,12),Vector3(-13,0,17.5),Vector3(-18,0,17.5),Vector3(-18,0,27),Vector3(0,0,27),Vector3(0,0,32)],"侧路与外院缺口可完整返回入口")
	scene.move_to_stop(3)
	for i in 3: await physics_frame
	await walk([Vector3(-8,0,-28),Vector3(-21,0,-28),Vector3(-21,0,26),Vector3(-18,0,26),Vector3(-18,0,27),Vector3(0,0,27)],"预留返程门洞与西侧捷径可通行")
	key(KEY_M)
	check(scene.overview and not scene.player.is_physics_processing(),"M 全图冻结角色移动")
	await capture("overview")
	key(KEY_3)
	check(not scene.overview and scene.player.is_physics_processing() and scene.player.position==scene.STOPS[2],"数字键退出全图并跳转高台")
	for i in 10: await physics_frame
	check(scene.player.is_on_floor() and absf(scene.player.position.y-1.8)<.06,"高台跳转没有落入碰撞体")
	var labels: Array = scene.review_labels
	key(KEY_F1)
	check(not labels[0].visible,"F1 关闭空间标注")
	key(KEY_F1)
	check(labels[0].visible,"F1 恢复空间标注")
	# 凸坡可走还不足以证明外观正确；核对显示包围盒与碰撞的宽度及高度。
	for name in ["SouthAccess","NorthAccess"]:
		var ramp: Node3D=scene.get_node("Terrain/"+name)
		var visual: CSGPolygon3D=ramp.get_node("Visual")
		var bounds: AABB=visual.transform*visual.get_aabb()
		print(name," visual bounds=",bounds)
		check(absf(bounds.position.x+2)<.02 and absf(bounds.end.x-2)<.02 and absf(bounds.end.y-1.8)<.02,"坡道显示与四米宽碰撞重合 "+name)
	await roofs_and_wilderness()
	print("WAYSTATION_BLOCKOUT: %d checks, %d failures"%[checks,failures])
	scene.queue_free()
	await process_frame
	quit(1 if failures else 0)
