extends "res://tests/tactical/waystation_blockout_test.gd"
## 走真实玩家物理，验证生成贴图、整面前墙分组、灰模对比与两个实例的遮挡隔离。
func snapshot(path: String) -> void:
	if DisplayServer.get_name()=="headless": return
	for i in 3: await process_frame
	# 测试窗口被其他窗口覆盖时也显式出帧，避免等待不可见窗口的自动绘制而挂起。
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(path)

func run() -> void:
	ProjectSettings.set_setting("tactical/testing",true)
	DirAccess.make_dir_recursive_absolute("res://work/cottage")
	scene=load("res://tools/cottage_art_lab.tscn").instantiate()
	root.add_child(scene)
	current_scene=scene
	scene.player.test_mode=true
	for i in 30: await physics_frame
	check(scene.player.is_on_floor(),"美术小屋门前安全落地")
	check(not scene.progress_enabled and scene.progression==null and scene.objective==null,"实验不访问任务与玩家存档")
	check(get_nodes_in_group("tactical_enemies").is_empty(),"实验无敌人")
	check(is_equal_approx(scene.camera.size,17.0/1.2) and scene.camera.projection==Camera3D.PROJECTION_ORTHOGONAL,"保持正式相机和人物屏幕尺寸")
	check(scene.cottage.roof.pieces.size()==2,"Blender 导入两片独立坡屋面")
	check(scene.cottage.roof.interior_fade==0,"屋外整顶保持不透明")
	var valid_triangles:=true
	for entry in scene.wall_occlusion.meshes:
		if entry.triangles==null: valid_triangles=false
	check(valid_triangles,"未填充的特效网格不进入环境遮挡采样")
	var front: Node3D=scene.cottage.get_node("FrontWall")
	var facade: Array[MeshInstance3D]=[]
	for child in front.get_children():
		if child is MeshInstance3D: facade.append(child)
	check(facade.size()==4 and front is StaticBody3D,"门两侧、门楣和山墙归属一个前墙实体")
	var same_group:=true
	var shared_material: Material=facade[0].get_active_material(0)
	for mesh in facade:
		if scene.wall_occlusion._group_owner(mesh)!=front or mesh.get_active_material(0)!=shared_material: same_group=false
	check(same_group,"前墙四个几何部分共享透视分组和显示材质")
	check(shared_material.get_shader_parameter("art_projection_enabled")==true and shared_material.get_shader_parameter("art_texture")!=null,"透视材质副本保留实际墙面图片")
	check(scene.cottage.roof.roof_material.get_shader_parameter("art_projection_enabled")==true and scene.cottage.roof.roof_material.get_shader_parameter("art_texture")!=null,"屋顶材质入口保留实际瓦片图片")
	var second_front: Node3D=scene.second_cottage.get_node("FrontWall")
	check(scene.wall_occlusion.groups.has(second_front.get_instance_id()) and second_front.get_instance_id()!=front.get_instance_id(),"复用的小屋拥有独立遮挡组")
	var copy_mesh: MeshInstance3D=second_front.get_node("WallFrontLeft")
	check(copy_mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]==front.get_node("WallFrontLeft").mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV],"移动预制件不改变表面纹理坐标")
	scene.hud.hide()
	# 只平移取景中心以完整容纳屋顶；投影角度/倍率/人物尺寸与实际游戏相同。
	scene.set_physics_process(false)
	scene.camera.position=scene.snapped_camera_position(Vector3(0,1,0)+scene.camera.global_basis.z*26)
	scene.environment_pixels._process(0)
	await snapshot("res://work/cottage/art_exterior.png")
	# 实际发送对比键，检查已注册的墙材质副本也收到切换，不能只改源材质。
	var toggle:=InputEventKey.new()
	toggle.physical_keycode=KEY_V
	toggle.pressed=true
	scene._unhandled_input(toggle)
	for i in 3: await physics_frame
	check(not scene.cottage.art_enabled and not scene.second_cottage.art_enabled and shared_material.get_shader_parameter("art_gray_preview")==true and scene.cottage.roof.roof_material.get_shader_parameter("art_gray_preview")==true,"V 实际切换双屋墙面与屋顶灰模")
	await snapshot("res://work/cottage/gray_comparison.png")
	scene._unhandled_input(toggle)
	for i in 3: await physics_frame
	check(scene.cottage.art_enabled and shared_material.get_shader_parameter("art_gray_preview")==false,"V 再按恢复生成美术且保留原分组")
	scene.set_physics_process(true)
	await walk([Vector3(0,0,0)],"真实步行穿过 1.5m 门洞进入小屋")
	for i in 30: await physics_frame
	check(scene.cottage.roof.inside and scene.cottage.roof.interior_fade==1,"室内沿用整顶淡化")
	check(scene.cottage.roof.reveal==1,"室内屋顶圆正常打开")
	check(scene.second_cottage.roof.interior_fade==0 and scene.second_cottage.roof.reveal==0,"进入第一栋不会淡化第二栋屋顶")
	await snapshot("res://work/cottage/inside.png")
	# 向完整侧墙持续行走，确保模型外观之外还具备真实碰撞。
	scene.player.test_motion=Vector2.RIGHT
	for i in 70: await physics_frame
	scene.player.test_motion=Vector2.ZERO
	check(scene.player.position.x<2.16,"东墙阻挡角色穿墙")
	await walk([Vector3(0,0,0),Vector3(0,0,5.2)],"由同一门洞返回屋外")
	for i in 35: await physics_frame
	check(scene.cottage.roof.reveal==0 and scene.cottage.roof.interior_fade==0,"出屋恢复整顶和圆孔")
	await walk([Vector3(4,0,5.2),Vector3(4,0,-4.5),Vector3(-4,0,-4.5),Vector3(-4,0,5.2),Vector3(0,0,5.2)],"四周通道完整绕屋返回")
	var floor_visual: Node=scene.cottage.get_node("SupportFloor/Visual")
	check(not scene.wall_occlusion.registered.has(floor_visual.get_instance_id()),"屋内地板不参与墙体透视")
	var hit:=scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(4,1.2,0),Vector3(0,1.2,0),8))
	check(not hit.is_empty(),"墙体阻弹层正常")
	scene.player.position=Vector3(0,0,-3.8)
	scene.player.velocity=Vector3.ZERO
	for i in 50: await physics_frame
	check(scene.wall_occlusion.ratio>=.9 and scene.wall_occlusion.reveal==1,"小屋背墙完全挡住人物时墙圆生效")
	await snapshot("res://work/cottage/behind.png")
	scene.player.position=Vector3(1.2,.05,1.5)
	scene.player.velocity=Vector3.ZERO
	for i in 45: await physics_frame
	check(scene.wall_occlusion.groups[front.get_instance_id()].weight>.9 and shared_material.get_shader_parameter("wall_reveal")>.9,"靠前墙遮挡时整面共同打开透视，不再逐小板开关")
	await snapshot("res://work/cottage/front_group.png")
	scene.player.position=Vector3(9,.05,0)
	scene.player.velocity=Vector3.ZERO
	for i in 45: await physics_frame
	check(scene.second_cottage.roof.inside and scene.second_cottage.roof.interior_fade==1 and scene.cottage.roof.interior_fade==0,"进入第二栋时本屋淡化、离开的第一栋恢复")
	check(scene.wall_occlusion.groups[front.get_instance_id()].weight==0,"离开的前墙透视组独立恢复")
	await snapshot("res://work/cottage/second_inside.png")
	print("COTTAGE_ART_LAB: %d checks, %d failures"%[checks,failures])
	scene.queue_free()
	await process_frame
	quit(1 if failures else 0)
