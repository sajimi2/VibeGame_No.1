extends SceneTree
## 覆盖两种武器的动作、物理前冲、接地尘、散布、死亡生命周期与新图集回导；隔离进度和美术覆盖。
const Pose = preload("res://scripts/presentation/character_pose.gd")
const Actions = preload("res://scripts/combat/action_library.gd")
const Accuracy = preload("res://scripts/combat/bow_accuracy.gd")
const Store = preload("res://scripts/art/atlas_store.gd")
const Document = preload("res://scripts/art/atlas_document.gd")
const Spec = preload("res://scripts/art/frame_spec.gd")
var lab: Node3D
var checks := 0
var failures := 0
var evidence: Array[Image] = []

func _initialize() -> void: run.call_deferred()
func frames(count: int) -> void:
	for i in count: await physics_frame
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ")+label)

func place() -> void:
	lab.player.position = Vector3(-4,0.03,17)
	lab.player.velocity = Vector3.ZERO
	lab.player.test_motion = Vector2.ZERO
	lab.player.test_crouch = false
	lab.player.test_sprint = false
	lab.combat.cooldown = 0
	lab.combat.swing_time = 0
	lab.combat.bow_time = 0
	await frames(12)

## 轻重分类只影响装备限制；未来技能的限制不会被换装误清除。
func mobility_and_drag() -> void:
	var player = lab.player
	var combat = lab.combat
	combat.apply_weapon(load("res://data/weapons/cleaver.tres"))
	await place()
	player.test_motion = Vector2(0.5,0)
	player.test_sprint = true
	await frames(20)
	check(not player.sprinting and player.velocity.x <= player.WALK_SPEED*0.5+0.01,"重型武器实际按住 Shift 仍不能疾跑")
	check(combat.dust.emitted > 0 and combat.dust.particles.size()<=6,"重刀移动接地时只产生少量尘粒")
	player.test_motion = Vector2.ZERO
	await frames(2)
	var emitted: int = combat.dust.emitted
	await frames(30)
	check(combat.dust.emitted == emitted and combat.dust.particles.is_empty(),"静止不冒尘，已有尘粒按寿命清理")
	var contact_ok := true
	for direction in 12:
		player.facing = Vector2(sin(direction*PI/6),cos(direction*PI/6))
		await frames(20)
		var tip: Vector3 = combat.weapon.to_global(combat.weapon.get_meta("blade_tip"))
		contact_ok = contact_ok and absf(tip.y-0.02)<0.06
	check(contact_ok,"十二朝向重刀刀尖真实接地")
	player.set_sprint_block(&"test_skill",true)
	combat.apply_weapon(load("res://data/weapons/knife.tres"))
	player.test_motion = Vector2(1,0)
	await frames(3)
	check(not player.sprinting,"换轻刀不解除独立技能限制")
	player.set_sprint_block(&"test_skill",false)
	await frames(3)
	check(player.sprinting and is_equal_approx(player.velocity.x,player.RUN_SPEED*1.1),"移除限制后轻刀恢复加速疾跑")
	await place()

## 真正运行攻击，确认交替顺序、手柄对齐与重刀位移；再用墙测试前冲没有绕过碰撞。
func attacks() -> void:
	var player = lab.player
	var combat = lab.combat
	var sequence: Array[String] = []
	var worst := 0.0
	for i in 3:
		combat.cooldown = 0
		combat.attack(player.position+Vector3.FORWARD*3+Vector3.UP)
		sequence.append(combat.attack_action.id)
		for frame in 29:
			await frames(1)
			worst = maxf(worst,combat.hand.global_position.distance_to(Pose.world_grip(player.sprite,lab.camera,player.grip_pixel,player.grip_depth)))
	check(sequence == ["light_rise","light_stab","light_rise"],"小刀每次有效攻击交替上挥、下刺")
	check(worst<0.0001,"连续攻击中手柄始终与本帧手心一致")
	combat.apply_weapon(load("res://data/weapons/cleaver.tres"))
	await place()
	var before: Vector3 = player.position
	combat.attack(player.position+Vector3.FORWARD*3+Vector3.UP)
	await frames(55)
	var distance: float = before.z-player.position.z
	check(distance>0.25 and distance<0.8,"重刀实际挥出产生有界的前冲惯性")
	await place()
	var wall = lab.box("LungeWall",player.position+Vector3(0,0.9,-0.60),Vector3(4,1.8,0.35),"wall")
	await frames(3)
	before = player.position
	combat.cooldown = 0
	combat.attack(player.position+Vector3.FORWARD*3+Vector3.UP)
	await frames(55)
	check(before.z-player.position.z<0.2,"重刀前冲被墙挡住，不穿过碰撞体")
	wall.queue_free()
	await frames(3)
	await place()
	var tip: Vector3 = combat.weapon.get_meta("blade_tip")
	for id in ["light_rise","light_stab","heavy_swing"]:
		var action := Actions.get_action(id)
		var idle := Actions.get_action("heavy_drag" if id == "heavy_swing" else "light_ready")
		check(action.sample(0).hand == idle.sample(0).hand and action.sample(1).hand == idle.sample(0).hand,"%s 首尾握点与待机连续" % id)
	check(tip.z < -1.5,"大砍刀保留足够刀身用于拖地与前劈")

## 同一批随机样本比较瞄准误差，同时验证生产射击确实使用发射时姿态。
func accuracy() -> void:
	var normal := RandomNumberGenerator.new()
	var crouch := RandomNumberGenerator.new()
	normal.seed = 883
	crouch.seed = 883
	var standing_error := 0.0
	var crouch_error := 0.0
	for i in 256:
		standing_error += Accuracy.deviate(Vector3.FORWARD*18,Accuracy.spread_degrees(false,false,false),normal).angle_to(Vector3.FORWARD)
		crouch_error += Accuracy.deviate(Vector3.FORWARD*18,Accuracy.spread_degrees(true,false,false),crouch).angle_to(Vector3.FORWARD)
	check(crouch_error < standing_error*0.3,"相同 256 次样本中，静止蹲射角误差小于站射三成")
	check(Accuracy.spread_degrees(false,true,false)>Accuracy.spread_degrees(false,false,false) and Accuracy.spread_degrees(true,false,true)>1,"移动与腾空仍有明确精度代价")
	for crouched in [false,true]:
		await place()
		lab.player.test_crouch = crouched
		await frames(15)
		lab.combat.shoot(lab.player.position+Vector3.FORWARD*10+Vector3.UP)
		await frames(12)
		check(is_equal_approx(lab.combat.last_spread,0.18 if crouched else 0.75),"实际%s使用对应散布" % ("蹲射" if crouched else "站射"))

## 本轮增量：测实际装备、移动、重击接地和共用剑盾曲线，不以资源字段存在代替运行行为。
func weapon_revision() -> void:
	# 遍历可用物品，而非只验刚修过的一把刀；共边必须恰好出现两次且有向体积为正。
	var catalog := ItemCatalog.build()
	for id in catalog.ids():
		var model := preload("res://scripts/presentation/weapon_art.gd").melee_model(catalog.definition(id).weapon_profile.model_id)
		var vertices: PackedVector3Array = model.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var edges := {}
		var volume := 0.0
		for i in range(0,vertices.size(),3):
			volume += vertices[i].dot(vertices[i+1].cross(vertices[i+2]))/6.0
			for j in 3:
				var a := str(vertices[i+j])
				var b := str(vertices[i+(j+1)%3])
				var key := a+":"+b if a<b else b+":"+a
				edges[key] = int(edges.get(key,0))+1
		var closed := true
		for count in edges.values(): closed = closed and count==2
		check(closed and volume>0.0001 and model.mesh.get_aabb().size.y>=0.029,id+" 刀身有厚度、封闭且面朝向正确")
		model.free()
	check(lab.progression.inventory.has_instance("camp_sword"),"初始化库存新增一把中型宝剑")
	# 模拟真实 v1 老库存没有宝剑：先补发再二次读档，验证装备保留且不会重复赠送。
	var old_inventory: Dictionary = lab.progression.inventory.get_snapshot().duplicate(true)
	for i in old_inventory.bag.size():
		if old_inventory.bag[i].get("instance_id","")=="camp_sword": old_inventory.bag[i] = {}
	var save_path := Store.root_path.get_base_dir().path_join("legacy_progress.json")
	DirAccess.make_dir_recursive_absolute(save_path.get_base_dir())
	preload("res://scripts/persistence/tactical_save.gd").write_snapshot(save_path,{"version":1,"inventory":old_inventory,"level":1,"xp":0,"rewarded":false})
	for attempt in 2:
		var restored := preload("res://scripts/progression/camp_progress.gd").new()
		restored.setup(lab.player,lab.combat)
		restored.save_path = save_path
		lab.add_child(restored)
		check(restored.inventory.has_instance("camp_sword") and restored.inventory.bag_used()==1 and restored.inventory.get_equipped(&"weapon").instance_id=="camp_knife","旧存档第 %d 次恢复：原装备保留、宝剑仅一把" % (attempt+1))
		restored.queue_free()
		await process_frame
	var combat = lab.combat
	var player = lab.player
	for kind in ["knife","sword","cleaver"]:
		combat.apply_weapon(load("res://data/weapons/"+kind+".tres"))
		await place()
		player.test_motion = Vector2.RIGHT
		await frames(15)
		check(is_equal_approx(player.velocity.x,4.62 if kind=="knife" else 4.2),kind+" 实际步速符合轻型 +10% / 中重型基准")
		player.test_sprint = true
		await frames(5)
		check(is_equal_approx(player.velocity.x,7.48 if kind=="knife" else 6.8 if kind=="sword" else 4.2),kind+" 实际疾跑遵守类型规则")
	await place()
	var action := Actions.get_action("heavy_swing")
	check(action.windup_end>0.6 and action.active_end-action.windup_end<0.15,"重刀用超过六成时间提起，砸落集中在短窗口")
	var vertices: PackedVector3Array = combat.weapon.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var low := 999.0
	var high := -999.0
	for point in vertices: low = minf(low,point.y); high = maxf(high,point.y)
	check(high-low>=0.1,"大砍刀封闭模型有真实刀背厚度")
	var previous: int = combat.dust.bursts
	combat.attack(player.position+Vector3.FORWARD*3+Vector3.UP)
	var contact_error := INF
	for i in 50:
		await frames(1)
		if combat.dust.bursts>previous and contact_error==INF:
			contact_error = absf(combat.weapon.to_global(combat.weapon.get_meta("blade_tip")).y-0.03)
		if i==42 and DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://work/heavy_impact_dust.png")
	check(combat.dust.bursts==previous+1 and contact_error<0.09,"一次重击在刀尖真实接地时只扬尘一次")
	await frames(45)
	check(combat.dust.particles.is_empty(),"重击尘土结束后自动清理")
	combat.apply_weapon(load("res://data/weapons/sword.tres"))
	await place()
	var kinds: Array[String] = []
	for i in 2:
		combat.cooldown = 0
		combat.attack(player.position+Vector3.FORWARD*3+Vector3.UP)
		kinds.append(combat.attack_action.id)
		await frames(40)
	check(kinds==["sword_slash","sword_thrust"],"玩家宝剑实际交替执行双手横斩与突刺")
	var guard = lab.guard
	guard.state = "windup"
	guard.action_duration = 0.32
	guard.attack_time = 0.2
	guard.hurt_recovery = false
	guard.update_visuals(0)
	var first: Basis = guard.sword.get_child(0).basis
	guard.attack_time = 0.05
	guard.update_visuals(0)
	check(not first.is_equal_approx(guard.sword.get_child(0).basis),"守卫保留决策前摇，同时实际驱动剑盾编排")
	check(guard.sword.get_child(0).mesh.get_aabb().size.is_equal_approx(combat.weapon.mesh.get_aabb().size),"守卫与玩家中型宝剑共用相同模型尺寸")
	var apex: Dictionary = Actions.get_action("heavy_swing").sample(0.62)
	var tip := Basis.from_euler(apex.blade)*Vector3(0,0,-2.21)
	check(apex.hand.x>0 and apex.hand.x<=2 and absf(tip.x)<0.08 and tip.y>2,"重刀头顶握点略偏持刀手，刀尖近乎竖直居中")
	guard.state = "guard"
	guard.update_visuals(0)

## 与旧固定前置握点做同画面 A/B：只统计身体不透明像素被武器改写的数量。
func back_occlusion() -> void:
	if DisplayServer.get_name()=="headless": return
	await place()
	lab.camera.size = 6
	lab.combat.apply_weapon(load("res://data/weapons/knife.tres"))
	var yaw: float = lab.camera.rotation.y+PI
	lab.player.facing = Vector2(sin(yaw),cos(yaw))
	await frames(30)
	lab.player.set_physics_process(false)
	lab.combat.set_physics_process(false)
	lab.combat.trail.hide()
	var images: Array[Image] = []
	for mode in 3:
		lab.combat.weapon.visible = mode!=0
		lab.combat.hand.global_position = Pose.world_grip(lab.player.sprite,lab.camera,lab.player.grip_pixel,0.018 if mode==1 else lab.player.grip_depth)
		await frames(2)
		await RenderingServer.frame_post_draw
		images.append(root.get_texture().get_image())
	images[1].save_png("res://work/knife_back_old.png")
	images[2].save_png("res://work/knife_back_fixed.png")
	var counts := [0,0]
	var body: Image = lab.player.sprite.texture.get_image()
	for y in body.get_height():
		for x in body.get_width():
			if body.get_pixel(x,y).a<0.95: continue
			var p := Vector2i(lab.camera.unproject_position(Pose.world_grip(lab.player.sprite,lab.camera,Vector2(x+0.5,y+0.5),0)))
			for mode in 2:
				if images[0].get_pixelv(p)!=images[mode+1].get_pixelv(p): counts[mode]+=1
	print("Back occlusion old/new: ",counts)
	check(counts[0]>0 and counts[1]<counts[0]*0.4,"实际渲染背向时匕首被身体遮挡，固定前置对照可复现")
	lab.combat.trail.show()
	lab.player.set_physics_process(true)
	lab.combat.set_physics_process(true)

## 同一来源接口导出新的三十三帧动作并回导；原图集键仍保持兼容。
func atlas() -> void:
	var source = load("res://data/art_sources/01_player.tres")
	var document := Document.new()
	document.build(source,source.animations().back(),{"action":"heavy_swing"})
	check(document.image.get_size() == Vector2i(384,1584),"重刀全身动作导出十二朝向、三十三帧原尺寸图集")
	var frames_seen := {}
	for row in 33: frames_seen[hash(document.cell_texture(3,row).get_image().get_data())] = true
	check(frames_seen.size()>20,"全身动作有连续变化的躯干和手臂帧")
	# 每格写不同色标，验证真正运行中的动作相位会使用编辑稿及对应握点。
	for row in 33:
		for column in 12: document.image.set_pixel(column*32+16,row*48+20,Color8(100+row*3,20+column*15,211))
	document.cells[16*12+3].anchors.grip = [20,24]
	var directory := Store.root_path.get_base_dir()
	var file: Dictionary = document.export_to(directory)
	check(not Store.import_package(file.json).has("error"),"新动作可通过现有导出回导接口持久化")
	var candidate := Document.new()
	check(candidate.load_package(Store.inspect_package(file.json),[source]).is_empty(),"工作台能够重新载入新动作清单")
	var player = lab.player
	player.direction_index = 3
	player.art_step = -1
	player.crouch_blend = 0
	player.jump_frame = -1
	player.visual_action = "heavy_swing"
	player.visual_action_frame = 16
	player._refresh_art(-1)
	check(player.sprite.texture.get_image().get_pixel(16,20).is_equal_approx(Color8(148,65,211)) and player.grip_pixel == Vector2(20,24),"实际 Player 全身动作读取编辑稿及新握点")
	check(player.world_shadow.texture == player.sprite.texture,"全身动作手绘稿同步进入实际剪影投影")
	Store.restore_asset("player")

## 截取动作过程而非只看待机，供人工复核三维刀刃和纸片躯体是否同步。
func capture_actions() -> void:
	if DisplayServer.get_name() == "headless": return
	await place()
	lab.camera.size = 9.5
	lab.player.set_physics_process(false)
	lab.combat.set_physics_process(false)
	lab.player.art_step = -1
	lab.player.facing = Vector2(sin(lab.camera.rotation.y+PI/2),cos(lab.camera.rotation.y+PI/2))
	for kind in ["light_rise","light_stab","heavy_swing","sword_slash","sword_thrust"]:
		lab.combat.apply_weapon(load("res://data/weapons/cleaver.tres" if kind == "heavy_swing" else "res://data/weapons/sword.tres" if kind.begins_with("sword") else "res://data/weapons/knife.tres"))
		lab.combat.cooldown = 0
		lab.combat.attack(lab.player.position+Vector3(lab.player.facing.x,0,lab.player.facing.y)*3+Vector3.UP)
		lab.combat.attack_action = Actions.get_action(kind)
		var sheet := Image.create(5*320,400,false,Image.FORMAT_RGBA8)
		for index in 5:
			lab.combat.trail.samples.clear()
			lab.combat.swing_time = lab.combat.attack_duration*(1.0-index*0.249)+1.0/60
			lab.combat._physics_process(1.0/60)
			await frames(2)
			await RenderingServer.frame_post_draw
			var image := root.get_texture().get_image()
			var center := Vector2i(lab.camera.unproject_position(lab.player.global_position+Vector3.UP))
			sheet.blit_rect(image,Rect2i(center-Vector2i(160,200),Vector2i(320,400)),Vector2i(index*320,0))
		sheet.save_png("res://work/"+kind+"_sequence.png")
		var directions := Image.create(4*256,3*280,false,Image.FORMAT_RGBA8)
		for direction in 12:
			lab.combat.trail.samples.clear()
			var yaw: float = lab.camera.rotation.y+direction*PI/6
			lab.player.facing = Vector2(sin(yaw),cos(yaw))
			lab.combat.locked_direction = Vector3(sin(yaw),0,cos(yaw))
			lab.combat.swing_time = lab.combat.attack_duration*0.45+1.0/60
			lab.combat._physics_process(1.0/60)
			await frames(2)
			await RenderingServer.frame_post_draw
			var center := Vector2i(lab.camera.unproject_position(lab.player.global_position+Vector3.UP))
			directions.blit_rect(root.get_texture().get_image(),Rect2i(center-Vector2i(128,140),Vector2i(256,280)),Vector2i(direction%4*256,direction/4*280))
		directions.save_png("res://work/"+kind+"_directions.png")
		lab.player.facing = Vector2(sin(lab.camera.rotation.y+PI/2),cos(lab.camera.rotation.y+PI/2))
	# 同一峰值姿态按正面、左右侧面拍摄，避免只看一个方向的抡刀弧线。
	lab.combat.apply_weapon(load("res://data/weapons/cleaver.tres"))
	lab.combat.attack_action = Actions.get_action("heavy_swing")
	var apex_sheet := Image.create(3*400,600,false,Image.FORMAT_RGBA8)
	for index in 3:
		var yaw: float = lab.camera.rotation.y+[0,PI/2,-PI/2][index]
		lab.player.facing = Vector2(sin(yaw),cos(yaw))
		lab.combat.locked_direction = Vector3(sin(yaw),0,cos(yaw))
		lab.combat.swing_time = lab.combat.attack_duration*0.38+1.0/60
		lab.combat._physics_process(1.0/60)
		await frames(2)
		await RenderingServer.frame_post_draw
		var center := Vector2i(lab.camera.unproject_position(lab.player.global_position+Vector3.UP*1.8))
		apex_sheet.blit_rect(root.get_texture().get_image(),Rect2i(center-Vector2i(200,300),Vector2i(400,600)),Vector2i(index*400,0))
	apex_sheet.save_png("res://work/heavy_apex_front_sides.png")
	# 守卫使用真实状态到曲线的适配入口，核对盾留在左手而非跟随刀刃翻转。
	lab.player.hide()
	lab.guard.position = lab.player.position
	lab.guard.facing = Vector3.BACK.rotated(Vector3.UP,lab.camera.rotation.y+PI/3)
	for thrust in [false,true]:
		lab.guard.thrust = thrust
		lab.guard.hurt_recovery = false
		lab.guard.action_duration = 0.5 if thrust else 0.32
		lab.guard.recovery_duration = 0.8 if thrust else 0.65
		var sheet := Image.create(5*320,400,false,Image.FORMAT_RGBA8)
		for index in 5:
			lab.guard.trail.samples.clear()
			lab.guard.state = "windup" if index<2 else "recover" if index<4 else "guard"
			lab.guard.attack_time = lab.guard.action_duration*(1-index*0.85) if index<2 else lab.guard.recovery_duration-(0.09 if index==2 else 0.35)
			lab.guard.update_visuals(0)
			await frames(2)
			await RenderingServer.frame_post_draw
			var center := Vector2i(lab.camera.unproject_position(lab.guard.global_position+Vector3.UP))
			sheet.blit_rect(root.get_texture().get_image(),Rect2i(center-Vector2i(160,200),Vector2i(320,400)),Vector2i(index*320,0))
		sheet.save_png("res://work/guard_"+("thrust" if thrust else "slash")+"_sequence.png")
	lab.player.show()
	lab.player.set_physics_process(true)
	lab.combat.set_physics_process(true)

## 隔离视口只画地面阴影，对照旧单面宝剑与当前实体，不把材质开关当作投影证据。
func sword_shadow() -> void:
	if DisplayServer.get_name()=="headless": return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(400,400)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("333333")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.3
	world.add_child(environment)
	var sun := DirectionalLight3D.new()
	world.add_child(sun)
	sun.rotation_degrees = Vector3(-55,-30,0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 20
	sun.light_energy = 0.8
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.5
	camera.far = 20
	world.add_child(camera)
	camera.position = Vector3(2,6,4)
	camera.look_at(Vector3(0,0,-0.7))
	var ground := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(8,0.1,8)
	ground.mesh = box
	ground.material_override = StandardMaterial3D.new()
	ground.material_override.albedo_color = Color("999999")
	world.add_child(ground)
	ground.position.y = -0.05
	var sword := preload("res://scripts/presentation/weapon_art.gd").sword()
	world.add_child(sword)
	sword.position.y = 1
	for node in [sword]+sword.get_children(): node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	var solid := sword.mesh
	var old := SurfaceTool.new()
	old.begin(Mesh.PRIMITIVE_TRIANGLES)
	var polygon := [Vector3(-0.075,0,-0.22),Vector3(0.075,0,-0.22),Vector3(0.095,0,-1.35),Vector3(0,0,-1.7),Vector3(-0.065,0,-1.37)]
	for i in range(1,4):
		for p in [polygon[0],polygon[i],polygon[i+1]]: old.add_vertex(p)
	old.generate_normals()
	var images: Array[Image] = []
	for mode in 3:
		sword.visible = mode!=0
		sword.mesh = old.commit() if mode==1 else solid
		await frames(4)
		await RenderingServer.frame_post_draw
		images.append(viewport.get_texture().get_image())
	images[1].save_png("res://work/sword_shadow_single_face.png")
	images[2].save_png("res://work/sword_shadow_solid.png")
	var counts := [0,0]
	for y in 400:
		for x in 400:
			for mode in 2:
				if images[0].get_pixel(x,y).r-images[mode+1].get_pixel(x,y).r>0.03: counts[mode]+=1
	print("Sword shadow old/solid pixels: ",counts)
	check(counts[1]>counts[0]*1.25,"实际渲染：实体宝剑投出宽刀身阴影，超过旧单面细条")
	viewport.queue_free()
	await process_frame

## 使用真实击杀入口，观察屈膝、倒地、停留、渐隐；尸体隐藏后依旧属于击败统计。
func death() -> void:
	await place()
	var guard = lab.guard
	guard.position = lab.player.position+Vector3(0,0,-1.8)
	guard.facing = Vector3.BACK
	guard.update_visuals(0)
	var population := get_nodes_in_group("tactical_enemies").size()
	guard.receive_strike(guard.position+Vector3.UP,Vector3.RIGHT,Vector3.LEFT,1000)
	await frames(8)
	check(guard.hp==0 and guard.collision_layer==0 and guard.death_visual.started,"真实死亡立即退出战斗并开始倒地")
	var early: Basis = guard.sprite.basis
	await frames(45)
	check(not early.is_equal_approx(guard.sprite.basis) and guard.visible,"先连续倒地，随后保留尸体")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://work/enemy_death_ground.png")
	await frames(130)
	check(guard.sprite.modulate.a>0 and guard.sprite.modulate.a<1,"停留后逐渐降低透明度")
	await frames(70)
	check(not guard.visible and is_instance_valid(guard) and get_nodes_in_group("tactical_enemies").size()==population,"渐隐后隐藏表现，击败统计节点仍保留")
	var archer: Node3D
	for enemy in get_nodes_in_group("tactical_enemies"):
		if enemy.ranged: archer = enemy; break
	archer.position = Vector3(8,1.12,-14)
	archer.receive_strike(archer.position+Vector3.UP,Vector3.RIGHT,Vector3.FORWARD,1000)
	await frames(60)
	check(archer.death_visual.ground_normal.y<0.99 and archer.sprite.global_basis.z.normalized().dot(archer.death_visual.ground_normal)>0.999,"弓手倒在真实坡道上，尸体平面与地面贴合")
	check(archer.sprite.global_basis.y.normalized().dot(archer.death_visual.fall_direction)>0.999,"倒地方向跟随致命攻击来向")

func run() -> void:
	ProjectSettings.set_setting("tactical/testing",true)
	Store.root_path = "res://work/weapon_test_%d_%d/overrides" % [int(Time.get_unix_time_from_system()),Time.get_ticks_usec()]
	Store.reload_catalog()
	lab = load("res://scenes/battlefield.tscn").instantiate()
	lab.results_enabled = false
	root.add_child(lab)
	current_scene = lab
	lab.player.test_mode = true
	while not is_instance_valid(lab.guard): await frames(1)
	lab.effects.streams.clear()
	for enemy in get_nodes_in_group("tactical_enemies"): enemy.ai_enabled = false
	await mobility_and_drag()
	await attacks()
	await weapon_revision()
	await back_occlusion()
	await accuracy()
	atlas()
	await capture_actions()
	await sword_shadow()
	await death()
	print("WEAPON_CHOREOGRAPHY: %d checks, %d failures" % [checks,failures])
	lab.queue_free()
	await process_frame
	quit(1 if failures else 0)
