extends SceneTree
## 骷髅专项：检查真实 Blender 动作往返、96 像素协议、混合分辨率、工作台与实际遮挡。
const Spec=preload("res://scripts/art/baked_human_spec.gd")
const Frame=preload("res://scripts/art/frame_spec.gd")
const Source=preload("res://scripts/art/baked_character_source.gd")
const Document=preload("res://scripts/art/atlas_document.gd")
const Store=preload("res://scripts/art/atlas_store.gd")
var checks:=0
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func frames(count: int) -> void:
	for i in count: await process_frame

func run() -> void:
	ProjectSettings.set_setting("tactical/testing",true)
	if DisplayServer.get_name()!="headless": DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps=120
	DirAccess.make_dir_recursive_absolute("res://work/skeleton96")
	await source_checks()
	var source: Resource=load("res://data/art_sources/00_3_skeleton_baked.tres")
	source._load()
	check(source.cell_size==Vector2i(96,96) and is_equal_approx(source.manifest.pixel_size*96,2.56),"96×96 提高像素密度，世界采样范围仍为 2.56m")
	var old_unchanged:=true
	for asset in ["player","guard","archer"]:
		var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(Spec.folder(asset)+"/atlas.json"))
		old_unchanged=old_unchanged and int(data.cell)==96 and is_equal_approx(data.pixel_size,2.56/96)
	check(old_unchanged,"四种角色统一 96×96，世界采样范围不变")
	var overview:=Image.create(96*12,96*5,false,Image.FORMAT_RGBA8)
	var clips:=["idle","walk","shield_slash","shield_thrust","death_fall"]
	for row in clips.size():
		for direction in 12:
			var sample: Dictionary=source.sample(clips[row],direction,[0,3,20,19,32][row],{"part":"full","ready":"shield_ready","move":0,"gait":-1})
			overview.blit_rect(sample.texture.get_image(),Rect2i(0,0,96,96),Vector2i(direction*96,row*96))
	overview.save_png("res://work/skeleton96/actions_12_directions.png")
	var scene: Node3D=load("res://scenes/battlefield.tscn").instantiate()
	scene.results_enabled=false
	root.add_child(scene)
	for i in 120:
		await physics_frame
		if get_nodes_in_group("tactical_enemies").size()==5: break
	await frames(3)
	scene.player.test_mode=true
	scene.player.set_physics_process(false)
	scene.combat.set_physics_process(false)
	scene.set_process(false)
	var skeleton: CharacterBody3D
	var count:=0
	for enemy in get_nodes_in_group("tactical_enemies"):
		enemy.set_physics_process(false)
		if enemy.art_id=="skeleton": skeleton=enemy; count+=1
	check(count==1 and not scene.progression.persist and scene.player.baked_visual.frame_size==96,"F5 仅首名守卫换骷髅，统一分辨率和测试存档隔离有效")
	check(skeleton.baked_visual.active and skeleton.baked_visual.frame_size==96 and skeleton.max_hp==60 and not skeleton.ranged,"骷髅实际播放 96 图集，沿用守卫战斗参数")
	check(skeleton.baked_visual.find_children("*","Skeleton3D",true,false).is_empty() and skeleton.baked_visual.find_children("*","SubViewport",true,false).is_empty(),"游戏中的骷髅身体没有实时骨架或烘焙视口")
	var grip_ok:=true
	for direction in 12:
		var angle: float=scene.camera.rotation.y+direction*PI/6
		skeleton.facing=Vector3(sin(angle),0,cos(angle))
		for status in ["guard","windup","recover"]:
			skeleton.state=status
			skeleton.attack_time=.1
			skeleton.update_visuals(.1)
			grip_ok=grip_ok and skeleton.baked_visual.active and skeleton.sword.global_position.distance_to(skeleton.baked_visual.last_grip)<.001
			grip_ok=grip_ok and skeleton.shield_node.to_global(preload("res://scripts/presentation/weapon_art.gd").SHIELD_CENTER).distance_to(skeleton.baked_visual.last_support)<.001
	check(grip_ok,"96 图集十二方向移动/剑盾攻击握点与世界武器吻合")
	await roundtrip(source,skeleton)
	for layer in scene.find_children("*","CanvasLayer",true,false): layer.hide()
	await workbench()
	if DisplayServer.get_name()!="headless": await render_checks(scene,skeleton)
	skeleton.hp=0
	skeleton.death_visual.update(skeleton,.6)
	check(skeleton.baked_visual.active and skeleton.baked_visual.last_keys.upper.contains("death_fall"),"死亡使用骷髅帧，没有回退为旧人形")
	skeleton.death_visual.update(skeleton,2.4)
	check(skeleton.baked_visual.opacity>0 and skeleton.baked_visual.opacity<1,"骷髅尸体按原时序渐隐")
	skeleton.death_visual.update(skeleton,1.1)
	check(not skeleton.visible,"死亡清理仍保留原任务节点")
	scene.queue_free()
	await frames(2)
	print("SKELETON_PIPELINE: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)

## 比较实际导回的全部作业关节；动画同名但重采样失真也会失败。
func source_checks() -> void:
	var original: Node3D=load(Spec.source_scene("guard")).instantiate()
	var imported: Node3D=load(Spec.source_scene("skeleton")).instantiate()
	root.add_child(original)
	root.add_child(imported)
	check(imported.rig_skeleton.get_bone_count()==15 and imported.animator.get_animation_list().size()==54,"Blender 资产含 15 骨及 54 个所需动作/方向片段")
	var maximum:=0.0
	for job in Spec.jobs("skeleton"):
		for move in job.moves:
			for phase in job.frames:
				original.sample_job(job,move,phase)
				imported.sample_job(job,move,phase)
				for bone in original.rig_skeleton.get_bone_count():
					var id: String=original.rig_skeleton.get_bone_name(bone)
					maximum=maxf(maximum,original._bone_point(id).distance_to(imported._bone_point(id)))
	print("SKELETON_ROUNDTRIP_MAX_METERS=",maximum)
	check(maximum<.001,"全部烘焙姿态与复用原动作的关节偏差小于 1mm")
	var bindings:=true
	for piece in imported.pieces:
		bindings=bindings and piece.skin!=null and piece.get_meta("art_part","") in ["upper","lower"]
	check(bindings and imported.pieces.size()==86,"86 个身体网格带有效蒙皮与分层，不包含重复剑盾")
	imported.sample("shield_slash",0)
	var a: Array=imported.geometry("upper")
	imported.sample("shield_slash",.5)
	var b: Array=imported.geometry("upper")
	check(a.size()>4000 and a!=b,"采集的是动作后的实体表面，不是静态绑定姿态")
	if DisplayServer.get_name()!="headless": await resolution_comparison(imported)
	original.free()
	imported.free()

## 同一模型、姿态、世界视野分别原生出图；等大小最近邻展示只为比较真实采样细节。
func resolution_comparison(rig: Node3D) -> void:
	rig.sample("shield_ready",0)
	var geometry: Array=rig.geometry("all",Spec.CENTER)
	var sheet:=Image.create(800,440,false,Image.FORMAT_RGBA8)
	sheet.fill(Color("283139"))
	var coverage:=[]
	for index in 2:
		var size:=64 if index==0 else 96
		var gpu:=preload("res://scripts/presentation/pixel_frame_gpu.gd").new()
		gpu.frame_size=size
		gpu.pixel_size=2.56/size
		root.add_child(gpu)
		await frames(1)
		gpu.set_triangles(geometry)
		gpu.draw(Basis(Vector3.RIGHT,deg_to_rad(Spec.PITCH)).inverse(),Vector3(-.35,.75,.56).normalized())
		gpu.color_mesh.force_update_transform()
		gpu.depth_mesh.force_update_transform()
		RenderingServer.force_draw(false)
		var frame:=gpu.viewport.get_texture().get_image().get_region(Rect2i(0,0,size,size))
		var filled:=0
		for y in size:
			for x in size:
				if frame.get_pixel(x,y).a>.5: filled+=1
		coverage.append(filled)
		frame.save_png("res://work/skeleton96/native_%d.png"%size)
		frame.resize(384,384,Image.INTERPOLATE_NEAREST)
		sheet.blend_rect(frame,Rect2i(0,0,384,384),Vector2i(8+index*400,28))
		gpu.free()
	sheet.save_png("res://work/skeleton96/resolution_compare.png")
	print("NATIVE_PIXEL_COVERAGE_64_96=",coverage)
	check(coverage[1]>coverage[0]*1.7,"96 原生采样得到更多实体像素，绝非将 64 贴图放大")

func roundtrip(source: Resource, actor: CharacterBody3D) -> void:
	Store.root_path="res://work/skeleton96/overrides"
	Store.reload_catalog()
	Store.restore_asset("skeleton_baked")
	var document:=Document.new()
	document.build(source,source.animations()[0],{"part":"upper","ready":"shield_ready","move":0,"gait":-1})
	check(document.image.get_size()==Vector2i(1152,96),"原尺寸导出为十二列 96×96，而非放大旧图")
	for y in document.image.get_height():
		for x in document.image.get_width():
			var c:=document.image.get_pixel(x,y)
			if c.a>.5: document.image.set_pixel(x,y,Color(.2,.7,.9,c.a))
	check(source.validate_edit(document).is_empty(),"96 分层补色接受有效轮廓")
	var exported:=document.export_to("res://work/skeleton96/roundtrip")
	var result:=Store.import_package(exported.json)
	check(not result.has("error"),"96 PNG/JSON 可重新导入隔离覆盖目录")
	actor.state="guard"
	actor.update_visuals(0)
	var texture: Texture2D=actor.baked_visual.layers.upper.body.material_override.get_shader_parameter("color_atlas")
	check(actor.baked_visual.active and texture.get_width()==1152,"游戏读取 96 编辑稿并保留源深度")
	var restored:=Document.new()
	check(restored.load_package(Store.inspect_package(exported.json),[source]).is_empty(),"96 编辑稿可在工作台重新载入")
	document.image.set_pixel(0,0,Color.WHITE)
	check(not source.validate_edit(document).is_empty(),"96 新增无深度轮廓仍被拒绝")
	Store.restore_asset("skeleton_baked")
	Store.root_path="res://data/art_overrides"
	Store.reload_catalog()
	actor.update_visuals(0)

func workbench() -> void:
	var ui: Control=load("res://tools/art_preview.tscn").instantiate()
	root.add_child(ui)
	await frames(2)
	for index in ui.sources.size():
		if ui.sources[index].asset_id=="skeleton_baked": ui.asset.select(index)
	ui.configure_source()
	ui.view_mode.select(1)
	ui.refresh_view_mode()
	check(ui.document.source.cell_size==Vector2i(96,96) and ui.model_view.rig!=null,"工作台可查看骷髅 96 图集及 Blender 源模型")
	ui.option_controls.part.select(1)
	ui.rebuild_atlas()
	var layers_ok:=true
	for piece in ui.model_view.rig.pieces: layers_ok=layers_ok and piece.visible==(piece.get_meta("art_part","")=="upper")
	check(layers_ok,"源模型分层预览兼容实际蒙皮结构")
	ui.option_controls.part.select(0)
	ui.rebuild_atlas()
	if DisplayServer.get_name()!="headless":
		await frames(3)
		RenderingServer.force_draw(false)
		root.get_texture().get_image().save_png("res://work/skeleton96/workbench.png")
	ui.queue_free()
	await frames(2)

## 实景截图与墙前后像素差验证，防止高分辨率纸片绕过深度。
func render_checks(scene: Node3D, actor: CharacterBody3D) -> void:
	for layer in scene.find_children("*","CanvasLayer",true,false): layer.hide()
	scene.camera.size=4.8
	scene.player.position=actor.position+Vector3(1.2,0,0)
	scene.player.direction_index=0
	scene.player._refresh_art(-1)
	actor.facing=Vector3(sin(scene.camera.rotation.y),0,cos(scene.camera.rotation.y))
	actor.state="guard"
	actor.update_visuals(0)
	scene.camera.position=actor.global_position+Vector3(0,.8,0)+scene.camera.basis.z*12
	await frames(4)
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png("res://work/skeleton96/in_game.png")
	var wall:=MeshInstance3D.new()
	var box:=BoxMesh.new()
	box.size=Vector3(2.8,3,.12)
	wall.mesh=box
	var mat:=StandardMaterial3D.new()
	mat.albedo_color=Color("d05280")
	mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	wall.material_override=mat
	scene.add_child(wall)
	wall.global_basis=scene.camera.global_basis
	wall.global_position=actor.global_position+Vector3.UP*.8+scene.camera.basis.z*2
	actor.sword.hide()
	actor.shield_node.hide()
	actor.trail.hide()
	actor.marker.hide()
	actor.health_bar.hide()
	actor.occluded=false
	actor.baked_visual.layers.upper.outline.hide()
	actor.baked_visual.layers.lower.outline.hide()
	await frames(3)
	RenderingServer.force_draw(false)
	var behind:=root.get_texture().get_image()
	actor.baked_visual.hide()
	await frames(3)
	RenderingServer.force_draw(false)
	check(behind.get_data()==root.get_texture().get_image().get_data(),"骷髅被墙完全遮挡时，身体不会覆盖墙面像素")
	wall.hide()
	await frames(3)
	RenderingServer.force_draw(false)
	var hidden:=root.get_texture().get_image()
	actor.baked_visual.show()
	await frames(3)
	RenderingServer.force_draw(false)
	check(hidden.get_data()!=root.get_texture().get_image().get_data(),"移开墙后骷髅确实绘出，不是假隐藏通过")
	wall.queue_free()
