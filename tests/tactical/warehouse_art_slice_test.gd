extends "res://tests/tactical/waystation_blockout_test.gd"
## 样板验证真实行走/碰撞/交战，并保存新旧实景；图片存在不等于玩法与深度链路通过。
var enemies: Array=[]
func frames(count: int) -> void:
	for i in count: await physics_frame
func snapshot(id: String) -> void:
	if DisplayServer.get_name()=="headless": return
	for i in 3: await process_frame
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png("res://work/warehouse/"+id+".png")

func run() -> void:
	ProjectSettings.set_setting("tactical/testing",true)
	DirAccess.make_dir_recursive_absolute("res://work/warehouse")
	scene=load("res://scenes/warehouse_art_slice.tscn").instantiate()
	root.add_child(scene)
	current_scene=scene
	scene.player.test_mode=true
	for i in 300:
		await physics_frame
		if scene.battle_ready: break
	check(scene.battle_ready,"样板导航、敌人与临时装备装配完成")
	if not scene.battle_ready: quit(1); return
	await frames(15)
	enemies=get_nodes_in_group("tactical_enemies")
	check(enemies.size()==3 and enemies.filter(func(e):return e.ranged).size()==1,"两名守卫与一名弓手使用已有演员")
	check(not scene.progression.persist and scene.objective==null and not scene.progress_enabled,"试玩不访问真实进度或任务奖励")
	check(scene.player.is_on_floor() and scene.player.safe_zone,"桥前出生可站立且处于安全营地")
	check(scene.player.baked_visual!=null and is_equal_approx(scene.camera.size,17.0/1.2),"沿用原角色和镜头大小")
	scene.set_combat_active(false)
	for enemy in enemies: enemy.collision_layer=0
	check(enemies.all(func(e):return not e.ai_enabled and e.state=="guard"),"勘察停止已有敌人的攻击和追击")
	var geometry_ok:=true
	for entry in scene.sample_art.bindings:
		var a: Mesh=entry.source
		var b: Mesh=entry.mesh.mesh
		for index in a.get_surface_count():
			if a.surface_get_arrays(index)[Mesh.ARRAY_VERTEX]!=b.surface_get_arrays(index)[Mesh.ARRAY_VERTEX]: geometry_ok=false
	check(geometry_ok,"贴图投影未改变原显示几何顶点")
	var base: Node3D=load("res://scenes/waystation_blockout.tscn").instantiate()
	var collisions_ok:=true
	for original in base.find_children("*","CollisionShape3D",true,false):
		var current: CollisionShape3D=scene.get_node(base.get_path_to(original))
		if current.shape!=original.shape or current.transform!=original.transform or current.get_parent().transform!=original.get_parent().transform: collisions_ok=false
	check(collisions_ok,"驿站原碰撞形状及位置全部保持")
	base.free()
	check(scene.sample_art.bindings.size()>20 and scene.sample_art.materials.all(func(m):return m.get_shader_parameter("art_texture")!=null),"墙面、石材、木桥、货箱与地表加载生成贴图")
	var side: MeshInstance3D=scene.get_node("Architecture/WarehouseEast/Visual")
	check(side.get_active_material(0).get_shader_parameter("art_projection_enabled")==true,"墙体透视副本保留图片开关")
	scene.hud.hide()
	scene.set_physics_process(false)
	scene.camera.position=scene.snapped_camera_position(Vector3(12,1.8,-6)+scene.camera.global_basis.z*26)
	scene.environment_pixels._process(0)
	await snapshot("new_exterior")
	key(KEY_V)
	await frames(4)
	check(not scene.sample_art.enabled and side.get_active_material(0).get_shader_parameter("art_projection_enabled")==false and scene.get_node("Architecture/WarehouseEast/ArtFinish").visible,"V 恢复旧材质和旧装饰，墙圆副本同步")
	await snapshot("old_exterior")
	key(KEY_V)
	await frames(4)
	check(scene.sample_art.enabled and not scene.get_node("Architecture/WarehouseEast/ArtFinish").visible,"V 再次恢复生成美术")
	scene.set_physics_process(true)
	await walk([Vector3(5,0,4),Vector3(5,1.8,-5),Vector3(5,1.8,-9),Vector3(13,1.8,-9)],"真实走过木桥、高台和侧门进入仓库")
	await frames(30)
	var roof: Node3D=scene.get_node("Roofs/WarehouseRoof")
	check(roof.inside and roof.interior_fade==1 and roof.reveal==1,"生成屋顶室内淡化并叠加透视圆")
	await snapshot("inside")
	var floor: Node=scene.get_node("Architecture/WarehouseFloor")
	check(not scene.wall_occlusion.registered.has(floor.get_instance_id()),"仓库承托地板仍排除墙圆")
	await walk([Vector3(15,1.8,-7),Vector3(15,1.8,-3.8)],"仓库正面装卸口保持通行")
	var wall_hit:=scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(24,2.7,-9),Vector3(19,2.7,-9),8))
	check(not wall_hit.is_empty() and wall_hit.collider.name=="WarehouseEast","生成外墙仍使用原墙体阻弹")
	# 真实飞行箭撞墙，不只确认静态射线。
	var arrow:=preload("res://scripts/combat/arrow.gd").new()
	arrow.position=Vector3(24,2.7,-9)
	arrow.velocity=Vector3(-18,0,0)
	scene.add_child(arrow)
	await frames(20)
	check(arrow.stopped and arrow.position.x>20.5,"飞行箭在仓库外墙停止而非穿过美术")
	arrow.queue_free()
	scene.player.position=Vector3(15,1.85,-15)
	scene.player.velocity=Vector3.ZERO
	await frames(40)
	check(scene.wall_occlusion.ratio>.9 and scene.wall_occlusion.reveal==1,"屋外背墙遮挡仍触发墙圆")
	await snapshot("behind")
	# 重新进入实战；近距离真扣血验证状态机，避免把配置存在当成战斗接通。
	var guard: Node3D=enemies.filter(func(e):return not e.ranged)[0]
	guard.position=Vector3(13,1.85,-8)
	guard.home=guard.position
	guard.velocity=Vector3.ZERO
	guard.facing=Vector3.RIGHT
	guard.cooldown=0
	guard.collision_layer=17
	scene.player.position=Vector3(14.4,1.85,-8)
	scene.player.velocity=Vector3.ZERO
	scene.player.invulnerable=0
	scene.player.hp=scene.player.max_hp
	scene.set_combat_active(true)
	for enemy in enemies:
		if enemy!=guard: enemy.ai_enabled=false
	await frames(150)
	check(scene.player.hp<scene.player.max_hp,"样板守卫实际攻击并扣除玩家生命")
	await snapshot("combat")
	print("WAREHOUSE_ART_SLICE: %d checks, %d failures"%[checks,failures])
	scene.queue_free()
	await process_frame
	quit(1 if failures else 0)
