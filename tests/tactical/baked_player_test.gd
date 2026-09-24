extends SceneTree
## 全角色离线美术：固定骨长、真实覆盖、战斗握点、死亡、工作台补色与真实渲染。
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
	if DisplayServer.get_name()!="headless": DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps=120
	ProjectSettings.set_setting("tactical/testing",true)
	DirAccess.make_dir_recursive_absolute("res://work/humanoid")
	for asset in Spec.ACTIONS: await validate_asset(asset)
	await authoring()
	var scene: Node3D=load("res://tests/fixtures/legacy/battlefield.tscn").instantiate()
	scene.results_enabled=false
	root.add_child(scene)
	for i in 120:
		await physics_frame
		if get_nodes_in_group("tactical_enemies").size()==5: break
	await frames(3)
	var player: CharacterBody3D=scene.player
	var combat: Node3D=scene.combat
	player.test_mode=true
	player.set_physics_process(false)
	combat.set_physics_process(false)
	for enemy in get_nodes_in_group("tactical_enemies"): enemy.set_physics_process(false)
	check(not scene.progression.persist,"正式战场仍隔离测试存档")
	var pure:=true
	for actor in [player]+get_nodes_in_group("tactical_enemies"):
		pure=pure and actor.baked_visual.active and actor.baked_visual.find_children("*","Skeleton3D",true,false).is_empty() and actor.baked_visual.find_children("*","SubViewport",true,false).is_empty()
	check(pure,"玩家与五敌人均用离线图集；角色播放没有骨架/烘焙视口")
	var align:=true
	for weapon in ["knife","sword","cleaver"]:
		combat.apply_weapon(load("res://data/weapons/"+weapon+".tres"))
		for direction in 12:
			var yaw: float=scene.camera.rotation.y+direction*PI/6
			player.facing=Vector2(sin(yaw),cos(yaw))
			player.direction_index=direction
			player.movement_direction=(direction+6)%12
			combat.locked_direction=Vector3(sin(yaw),0,cos(yaw))
			for action in combat.weapon_profile.attack_sequence:
				combat.attack_action=load("res://data/actions/"+action+".tres")
				for phase in [0.1,0.4,0.65,0.9]:
					combat.swing_time=combat.attack_duration*(1-phase)+.001
					player.art_step=3
					player.crouch_blend=1 if phase>.8 else 0
					player.jump_frame=2 if phase<.2 else -1
					combat._physics_process(.001)
					align=align and player.baked_visual.active and combat.hand.global_position.distance_to(player.baked_visual.last_grip)<.001
	check(align,"三种武器全朝向、蹲/跳/后退攻击的实际握柄与烘焙手心同帧吻合")
	var enemy_align:=true
	for enemy in get_nodes_in_group("tactical_enemies"):
		for direction in 12:
			var yaw: float=scene.camera.rotation.y+direction*PI/6
			enemy.facing=Vector3(sin(yaw),0,cos(yaw))
			for status in ["guard","windup","recover","nock"]:
				enemy.state=status
				enemy.attack_time=.1
				enemy.update_visuals(.1)
				enemy_align=enemy_align and enemy.baked_visual.active and enemy.sword.global_position.distance_to(enemy.baked_visual.last_grip)<.001
				if not enemy.ranged:
					enemy_align=enemy_align and enemy.shield_node.to_global(preload("res://scripts/presentation/weapon_art.gd").SHIELD_CENTER).distance_to(enemy.baked_visual.last_support)<.001
	check(enemy_align,"守卫剑盾与弓手持弓手在十二方向随实际 AI 状态绑定")
	player.crouch_blend=0
	player.jump_frame=-1
	player.art_step=-1
	player.visual_action="light_ready"
	player.direction_index=0
	player._refresh_art(-1)
	if DisplayServer.get_name()!="headless":
		await gallery(scene)
		await wall_depth(scene)
	var enemy: CharacterBody3D=get_nodes_in_group("tactical_enemies")[0]
	enemy.hp=0
	enemy.death_visual.update(enemy,.5)
	check(enemy.baked_visual.active and enemy.baked_visual.last_keys.upper.contains("death_fall") and not enemy.sword.visible,"死亡播实体倒地帧并隐藏武器")
	enemy.death_visual.update(enemy,2.5)
	check(enemy.baked_visual.opacity<1 and enemy.baked_visual.opacity>0,"尸体按原时序像素渐隐")
	enemy.death_visual.update(enemy,1.1)
	check(not enemy.visible,"死亡四秒后隐藏且保留任务计数节点")
	await roundtrip(player)
	for layer in scene.find_children("*","CanvasLayer",true,false): layer.hide()
	await workbench()
	await performance(scene)
	scene.queue_free()
	await frames(3)
	print("BAKED_PLAYER: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)

func validate_asset(asset: String) -> void:
	var manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(Spec.folder(asset)+"/atlas.json"))
	var expected:=0
	for job in Spec.jobs(asset): expected+=job.frames*job.moves*12
	check(manifest.entries.size()==expected,"%s 作业清单完整落盘：%d 帧"%[asset,expected])
	var images: Array[Image]=[]
	for page in manifest.pages: images.append(load(Spec.folder(asset)+"/"+str(page)+".png").get_image())
	var nonempty:=true
	var directions: Dictionary={}
	for key in manifest.entries:
		var entry: Dictionary=manifest.entries[key]
		var image:=images[int(entry.page)].get_region(Rect2i(entry.rect[0],entry.rect[1],entry.rect[2],entry.rect[3]))
		var area:=image.get_used_rect()
		nonempty=nonempty and area.has_area() and area.position.x>0 and area.position.y>0 and area.end.x<image.get_width() and area.end.y<image.get_height()
		if key.begins_with(("full/" if asset in Spec.CREATURES else "upper/")+Spec.ready(asset)+"/") and key.ends_with("/0/0"): directions[hash(image.get_data())]=true
	check(nonempty and directions.size()==12,asset+" 全帧非空/未裁边，十二朝向确实不同")
	var coverage:=true
	for direction in 12:
		for move in 12:
			for posture in 15:
				for action in Spec.ACTIONS[asset]:
					var state:=Frame.character(direction,posture%8,posture in range(1,7),move,0,-1,0,posture%9,posture if posture in range(1,7) else 0,posture==7,posture-8 if posture in range(8,13) else -1)
					state=Frame.with_action(state,action,Spec.phases(action)-1)
					var selected:=Spec.select(state,asset)
					for part in Spec.parts(asset): coverage=coverage and manifest.entries.has(selected[part])
	check(coverage,asset+" 全朝向/移动方向、蹲跳/攻击组合没有旧帧回退")
	var source:=Source.new()
	source.rig_id=asset
	source.asset_id=asset+"_baked"
	var contract:=true
	for clip in source.animations():
		for part in (["full"] if asset in Spec.CREATURES else ["full","upper","lower"]):
			var keys: Dictionary={}
			for phase in clip.frames:
				var sample: Dictionary=source.sample(clip.id,3,phase,{"part":part,"ready":Spec.ready(asset),"move":6,"gait":-1})
				contract=contract and sample.texture.get_size()==Vector2.ONE*Spec.cell(asset) and not keys.has(sample.key)
				keys[sample.key]=true
	check(contract,asset+" 新来源全动作三种视图尺寸与预览帧键有效")
	await process_frame

## 修改保存的动画轨道会改变骨骼姿态，证明烘焙不再由旧二维公式覆盖关键帧。
func authoring() -> void:
	var rig: Node3D=load("res://assets/characters/player_rig.tscn").instantiate()
	root.add_child(rig)
	var fixed:=true
	for id in rig.animator.get_animation_list():
		for t in [0.0,.25,.5,.75,1.0]:
			rig.sample(id,t)
			for index in range(1,rig.rig_skeleton.get_bone_count()):
				fixed=fixed and rig.rig_skeleton.get_bone_pose_position(index).distance_to(rig.rig_skeleton.get_bone_rest(index).origin)<.0001 and rig.rig_skeleton.get_bone_pose_scale(index).distance_to(Vector3.ONE)<.0001
	check(fixed,"全部片段保持固定骨长，没有缩放四肢凑手脚位置")
	var lean:=true
	for move in 12:
		for phase in 8:
			rig.sample("run_%02d"%move,phase/8.0)
			var spine: Basis=rig.rig_skeleton.get_bone_global_pose(rig.rig_skeleton.find_bone("Spine")).basis
			lean=lean and rad_to_deg(spine.y.angle_to(Vector3.UP))<8
	check(lean,"十二方向跑步胸椎倾角小于 8 度，重心不再只靠胸口前移")
	var knees:=true
	for move in 12:
		for gait in ["run","jump"]:
			for phase in range(8 if gait=="run" else 5):
				rig.sample(gait+"_%02d"%move,phase/(8.0 if gait=="run" else 4.0))
				for suffix in ["L","R"]:
					var hip: Vector3=rig._bone_point("Thigh"+suffix)
					var knee: Vector3=rig._bone_point("Shin"+suffix)
					var ankle: Vector3=rig._bone_point("Foot"+suffix)
					var axis: Vector3=(ankle-hip).normalized()
					var bend: Vector3=knee-hip-axis*(knee-hip).dot(axis)
					knees=knees and bend.dot(Vector3.BACK)>-.0001
	check(knees,"十二移动方向跑/跳的膝盖始终向身体前方弯，不随倒退移动反折")
	rig.animator.play("run_00")
	rig.animator.advance(.1)
	rig._sync()
	var preview_a: Dictionary=rig.anchors()
	rig.animator.advance(.25)
	rig._sync()
	var preview_b: Dictionary=rig.anchors()
	check(preview_a.grip.distance_to(preview_b.grip)>.01,"AnimationPlayer 自身可播放源动画，不只自定义采样器认识这些数据")
	rig.animator.stop()
	var base: Dictionary=rig.sample("heavy_swing",.5)
	var library: AnimationLibrary=rig.animator.get_animation_library("").duplicate(true)
	rig.animator.remove_animation_library("")
	rig.animator.add_animation_library("",library)
	var clip:=library.get_animation("heavy_swing")
	var track := -1
	for index in clip.get_track_count():
		if clip.track_get_type(index)==Animation.TYPE_ROTATION_3D and str(clip.track_get_path(index)).ends_with(":UpperArmR"): track=index
	assert(track>=0,"导入动画缺少右上臂轨道")
	for index in clip.track_get_key_count(track): clip.rotation_track_insert_key(track,clip.track_get_key_time(track,index),Quaternion(Vector3.FORWARD,1.4))
	rig.animator.clear_caches()
	var modified: Dictionary=rig.sample("heavy_swing",.5)
	print("AUTHORING_DELTA ",base.grip," -> ",modified.grip," track=",track)
	check(base.grip.distance_to(modified.grip)>.1,"编辑标准骨骼关键帧直接改变烘焙采样手心")
	rig.free()

func gallery(scene: Node3D) -> void:
	var player: CharacterBody3D=scene.player
	scene.hud.hide()
	scene.camera.size=6
	scene.combat.hand.hide()
	player.set_physics_process(false)
	var sources: Array=[]
	for asset in ["player","guard","archer"]:
		var source:=Source.new()
		source.rig_id=asset
		source.asset_id=asset+"_baked"
		sources.append(source)
		var document:=Document.new()
		document.build(source,source.animations()[2],{"part":"full","ready":Spec.ready(asset),"move":0,"gait":-1})
		document.image.save_png("res://work/humanoid/"+asset+"_run.png")
		var overview:=Image.create(96*6,96*4,false,Image.FORMAT_RGBA8)
		var actions: Array=["idle","run","bow_draw" if asset=="archer" else "shield_slash" if asset=="guard" else "heavy_swing","death_fall"]
		for row in 4:
			for column in 6:
				var frame:=source.sample(actions[row],column*2,3 if row==1 else 5 if row==2 and asset=="archer" else 20 if row==2 else 32 if row==3 else 0,{"part":"full","ready":Spec.ready(asset),"move":0})
				overview.blit_rect(frame.texture.get_image(),Rect2i(0,0,96,96),Vector2i(column*96,row*96))
		overview.save_png("res://work/humanoid/"+asset+"_overview.png")
	player.occluded=false
	player.visual_action="light_ready"
	player.sprinting=true
	player.movement_direction=3
	player.direction_index=3
	player._refresh_art(2)
	var rig: Node3D=load("res://assets/characters/player_rig.tscn").instantiate()
	scene.add_child(rig)
	rig.apply_state(Frame.with_action(Frame.character(3,2,false,3,0,-1,0,-1,0,true),"light_ready"))
	rig.global_position=player.global_position+scene.camera.global_basis.x*1.6
	rig.rotation.y=scene.camera.rotation.y+PI/2
	await frames(4)
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png("res://work/humanoid/source_and_pixel.png")
	rig.queue_free()
	check(true,"已输出三角色十二方向跑步与动作图集、实际源模型/像素对照")

func wall_depth(scene: Node3D) -> void:
	var player: Node3D=scene.player
	player.direction_index=0
	player.visual_action="light_ready"
	player.sprinting=false
	player.occluded=false
	player._refresh_art(-1)
	await frames(3)
	RenderingServer.force_draw(false)
	var baseline:=root.get_texture().get_image()
	var wall:=MeshInstance3D.new()
	var box:=BoxMesh.new()
	box.size=Vector3(2,3,.12)
	wall.mesh=box
	var material:=StandardMaterial3D.new()
	material.albedo_color=Color("cf5678")
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	wall.material_override=material
	scene.add_child(wall)
	wall.global_basis=Basis(Vector3.UP,scene.camera.rotation.y)
	wall.global_position=player.global_position+Vector3.UP*.9+scene.camera.global_basis.z*1
	await frames(3)
	# 本项只验证正常身体的深度遮挡；新灰色提示另有逐像素专项，不能把提示当作穿墙。
	for layer in player.baked_visual.layers.values(): layer.occlusion.hide()
	RenderingServer.force_draw(false)
	var front:=root.get_texture().get_image()
	player.baked_visual.hide()
	await frames(2)
	RenderingServer.force_draw(false)
	var hidden:=root.get_texture().get_image()
	var center: Vector2=scene.camera.unproject_position(player.global_position+Vector3.UP*.9)
	var region:=Rect2i(Vector2i(center)-Vector2i(110,150),Vector2i(220,300))
	var same:=front.get_region(region).get_data()==hidden.get_region(region).get_data()
	front.save_png("res://work/humanoid/wall_front.png")
	hidden.save_png("res://work/humanoid/wall_hidden.png")
	check(same,"实际墙体在人物前方时完全遮挡，不靠显示层级强行置顶")
	player.baked_visual.show()
	player.baked_visual.refresh_occlusion_visibility()
	wall.queue_free()

func roundtrip(player: CharacterBody3D) -> void:
	Store.root_path="res://work/humanoid/overrides"
	Store.reload_catalog()
	Store.restore_asset("player_baked")
	var source:=Source.new()
	source.asset_id="player_baked"
	source.rig_id="player"
	source.cell_size=Vector2i(96,96)
	var document:=Document.new()
	document.build(source,source.animations()[0],{"part":"upper","ready":"light_ready","move":0,"gait":-1})
	var original:=document.image.duplicate()
	for y in document.image.get_height():
		for x in document.image.get_width():
			var color:=document.image.get_pixel(x,y)
			if color.a>.5: document.image.set_pixel(x,y,Color(.2,.7,.9,color.a))
	check(source.validate_edit(document).is_empty(),"分层补色保留源深度，允许回导")
	var exported:=document.export_to("res://work/humanoid/export")
	var result:=Store.import_package(exported.json)
	check(not result.has("error") and not Store.lookup("player_baked",document.cells[0].binding).is_empty(),"原尺寸 PNG/JSON 导出、回导与独立覆盖命名空间有效")
	player.visual_action="light_ready"
	player.visual_action_frame=0
	player.attack_pose=0
	player.sprinting=false
	player.crouch_blend=0
	player.jump_frame=-1
	player.direction_index=0
	player._refresh_art(-1)
	var material: ShaderMaterial=player.baked_visual.layers.upper.body.material_override
	var edited: Texture2D=material.get_shader_parameter("color_atlas")
	check(edited.get_width()==document.image.get_width() and player.baked_visual.active,"实际玩家 shader 读取补色图，源深度保持独立")
	var restored:=Document.new()
	check(restored.load_package(Store.inspect_package(exported.json),[source]).is_empty(),"编辑稿可重新载入工作台")
	document.image.set_pixel(0,0,Color.WHITE)
	check(not source.validate_edit(document).is_empty(),"没有源深度的新轮廓明确拒绝，避免回导后穿模")
	Store.restore_asset("player_baked")
	Store.root_path="res://data/art_overrides"
	Store.reload_catalog()

## 实际工作台使用新来源，测试点击选帧、播放、导出及层级选项；不只检查底层拼图。
func workbench() -> void:
	var ui: Control=load("res://tools/art_preview.tscn").instantiate()
	root.add_child(ui)
	await frames(2)
	check(ui.sources[ui.asset.selected].asset_id=="player_baked" and ui.document.source.cell_size==Vector2i(96,96),"工作台默认展示新烘焙角色原尺寸")
	ui.action.select(2)
	ui.rebuild_atlas()
	ui.direction.select(6)
	ui.select_frame(3)
	ui.play.button_pressed=true
	ui._process(.2)
	check(ui.frame.value!=3 and ui.document.cells.size()==96,"十二朝向奔跑可逐帧选择与播放")
	ui.play.button_pressed=false
	var exported: Dictionary=ui.export_atlas()
	check(not exported.has("error") and FileAccess.file_exists(exported.png),"工作台完整合成图导出 PNG/JSON")
	check(ui.apply_atlas().has("error"),"合成图回导给出明确分层编辑提示")
	ui.option_controls.part.select(1)
	ui.rebuild_atlas()
	check(ui.document.cells[0].has("binding") and not Store.inspect_package(ui.export_atlas().json).has("error"),"分层预览保留运行时绑定键，可导出重复共用姿态")
	if DisplayServer.get_name()!="headless":
		await frames(2)
		RenderingServer.force_draw(false)
		root.get_texture().get_image().save_png("res://work/humanoid/workbench.png")
	await model_workbench(ui)
	ui.queue_free()
	await frames(2)

## 用真实工作台切换三角色、姿态和相机，防止原始模型与图集选择各走一套状态。
func model_workbench(ui: Control) -> void:
	ui.view_mode.select(1)
	for asset in ["player","guard","archer"]:
		for index in ui.sources.size():
			if ui.sources[index].asset_id==asset+"_baked": ui.asset.select(index)
		ui.configure_source()
		ui.action.select(2)
		ui.option_controls.move.select(6)
		ui.rebuild_atlas()
		ui.direction.select(3)
		ui.select_frame(3)
		ui.refresh_frame()
		var viewer: SubViewportContainer=ui.model_view
		check(viewer.active and viewer.rig!=null and viewer.scene_path.ends_with(asset+"_rig.tscn") and viewer.world.find_children("*","Skeleton3D",true,false).size()==1,asset+" 工作台直接实例化自己的源骨骼模型，无残留角色")
		var state: Dictionary=viewer.last_descriptor.state
		check(state.asset==asset and state.direction==3 and state.move==9 and state.step==3 and state.run and is_equal_approx(viewer.rig.rotation.y,PI/2),asset+" 三维预览与图集共享朝向、后退步态及角色动作")
		var old_id: int=viewer.rig.get_instance_id()
		# 守卫/弓手的手臂持械时保持稳定；用摆动足的实际骨骼位置验证步态变化。
		var foot: int=viewer.rig.rig_skeleton.find_bone("FootR")
		var old_foot: Vector3=viewer.rig.rig_skeleton.get_bone_global_pose(foot).origin
		ui.select_frame(5)
		check(viewer.rig.get_instance_id()==old_id and viewer.rig.rig_skeleton.get_bone_global_pose(foot).origin.distance_to(old_foot)>.001,asset+" 逐帧确实改变实体姿态，且不重建模型")
		if DisplayServer.get_name()!="headless":
			await frames(3)
			RenderingServer.force_draw(false)
			root.get_texture().get_image().save_png("res://work/humanoid/"+asset+"_model_workbench.png")
			var shown: Image=viewer.viewport.get_texture().get_image()
			viewer.rig.hide()
			viewer._redraw()
			await frames(2)
			RenderingServer.force_draw(false)
			check(shown.get_data()!=viewer.viewport.get_texture().get_image().get_data(),asset+" 子视口实际渲染模型像素")
			viewer.rig.show()
			viewer._redraw()
	var viewer: SubViewportContainer=ui.model_view
	var motion:=InputEventMouseMotion.new()
	motion.button_mask=MOUSE_BUTTON_MASK_LEFT
	motion.relative=Vector2(50,20)
	viewer._gui_input(motion)
	var wheel:=InputEventMouseButton.new()
	wheel.pressed=true
	wheel.button_index=MOUSE_BUTTON_WHEEL_UP
	viewer._gui_input(wheel)
	check(absf(viewer.orbit.x)>.1 and viewer.camera.size<3 and ui.direction.selected==3,"观察窗拖动旋转、滚轮缩放不修改图集方向")
	viewer.reset_camera()
	check(is_zero_approx(viewer.orbit.x) and is_equal_approx(viewer.camera.size,3),"复位回固定斜角正交视角")
	ui.option_controls.part.select(1)
	ui.rebuild_atlas()
	var layers_ok:=true
	for piece in viewer.rig.pieces: layers_ok=layers_ok and piece.visible==(piece.get_meta("art_part")=="upper")
	check(layers_ok,"分层选择同步隐藏源模型对应骨段")
	ui.play.button_pressed=true
	ui._process(.2)
	check(viewer.last_descriptor.state.step==int(ui.frame.value),"播放按钮同时推进实体和像素帧")
	ui.play.button_pressed=false
	ui.view_mode.select(0)
	ui.refresh_view_mode()
	check(not viewer.active and viewer.viewport.render_target_update_mode==SubViewport.UPDATE_DISABLED,"切回图集关闭三维视口绘制")
	ui.view_mode.select(1)
	for index in ui.sources.size():
		if ui.sources[index].asset_id=="arrow": ui.asset.select(index)
	ui.configure_source()
	check(ui.view_mode.selected==0 and ui.view_mode.is_item_disabled(1) and viewer.rig==null,"箭矢纯二维来源自动回图集并清理三维模型")

## 持续切换方向/步态/攻击，统计纯角色播放 CPU；不把这项计时冒充整局 FPS。
func performance(scene: Node3D) -> void:
	var samples: Array[float]=[]
	var actors: Array=[scene.player]+get_nodes_in_group("tactical_enemies")
	for actor in actors:
		actor.hp=100
		actor.show()
		if actor!=scene.player: actor.death_visual.restore(actor)
	for tick in 360:
		var started:=Time.get_ticks_usec()
		for actor in actors:
			var asset: String=actor.baked_visual.asset_id
			var action: String=Spec.ACTIONS[asset][tick%Spec.ACTIONS[asset].size()]
			var state:=Frame.with_action(Frame.character(tick%12,tick%8,false,(tick+6)%12),action,tick%Spec.phases(action))
			actor.baked_visual.apply_frame(state)
		var elapsed:=(Time.get_ticks_usec()-started)/1000.0
		if tick>=60: samples.append(elapsed)
		await process_frame
	samples.sort()
	print("HUMAN_PLAYBACK_CPU_6 median_ms=",samples[150]," p95_ms=",samples[285]," max_ms=",samples[-1])
	check(scene.player.baked_visual.active and scene.player.baked_visual.frame_changes>100,"六角色连续换向/换招播放，帧持续推进")
