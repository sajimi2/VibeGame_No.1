extends SceneTree
## 实验专项：真实动作烘焙、原版切换、深度遮挡及像素导出；不进入真实进度。
const Baker = preload("res://scripts/art/weapon_sprite_baker.gd")
const Actions = preload("res://scripts/combat/action_library.gd")
const Art = preload("res://scripts/presentation/weapon_art.gd")
const Adapter = preload("res://scripts/presentation/pixel_weapon.gd")
var checks := 0
var failures := 0
var lab: Node3D

func _initialize() -> void: run.call_deferred()
func frames(count: int) -> void:
	for i in count: await process_frame
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ")+label)

func coverage(image: Image) -> int:
	var count := 0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x,y).a>0.5: count += 1
	return count

## 由真实战斗控制器给出最终握点/刀刃姿态，十二方向分别烘焙，禁止用另一套动画代替。
func poses() -> void:
	var player: Node3D = lab.battlefield.player
	var combat: Node3D = lab.battlefield.combat
	player.test_mode = true
	player.set_physics_process(false)
	combat.set_physics_process(false)
	lab.battlefield.hud.hide()
	lab.caption.hide()
	for id in ["sword","cleaver","knife"]:
		lab.equip(id)
		var adapter: Node3D = lab.adapter
		adapter.set_process(false)
		combat.attack_action = Actions.get_action({"sword":"sword_slash","cleaver":"heavy_swing","knife":"light_rise"}[id])
		var sheet := Image.create(12*Baker.SIZE,9*Baker.SIZE,false,Image.FORMAT_RGBA8)
		var depths := Image.create(sheet.get_width(),sheet.get_height(),false,Image.FORMAT_RGBA8)
		var all_visible := true
		var all_inside := true
		var largest_bake := 0
		for direction in 12:
			var yaw: float = lab.battlefield.camera.rotation.y+direction*PI/6
			player.facing = Vector2(sin(yaw),cos(yaw))
			combat.locked_direction = Vector3(sin(yaw),0,cos(yaw))
			for phase in 9:
				combat.swing_time = combat.attack_duration*(1-phase/8.0)+1.0/60
				combat._physics_process(1.0/60)
				adapter.sync(1.0)
				var frame: Image = adapter.capture_frame().image
				all_visible = all_visible and coverage(frame)>10
				for edge in Baker.SIZE:
					all_inside = all_inside and frame.get_pixel(edge,0).a==0 and frame.get_pixel(edge,Baker.SIZE-1).a==0 and frame.get_pixel(0,edge).a==0 and frame.get_pixel(Baker.SIZE-1,edge).a==0
				largest_bake = maxi(largest_bake,adapter.bake_usec)
				var at := Vector2i(direction*Baker.SIZE,phase*Baker.SIZE)
				sheet.blit_rect(frame,Rect2i(0,0,Baker.SIZE,Baker.SIZE),at)
				depths.blit_rect(adapter.capture_frame().depth,Rect2i(0,0,Baker.SIZE,Baker.SIZE),at)
		print(id," 最大单帧烘焙微秒: ",largest_bake)
		check(all_visible,id+" 十二方向九相位都有可见刀身")
		check(all_inside,id+" 所有姿态都未裁切到图框外")
		check(adapter.cache.size()<=Adapter.CACHE_LIMIT,id+" 姿态缓存受上限约束")
		# 超过缓存容量后仍能回到旧姿态重新生成，不能只在未满时检查 size。
		for step in 150:
			combat.weapon.rotation = Vector3(0.3,step*0.03,0.2)
			adapter.sync(1.0)
			adapter.capture_frame()
		check(adapter.cache.size()==Adapter.CACHE_LIMIT and not adapter.capture_frame().is_empty(),id+" 超过容量后淘汰旧帧并继续显示")
		sheet.save_png("res://work/weapon_pixels/"+id+"_12x9.png")
		depths.save_png("res://work/weapon_pixels/"+id+"_12x9_depth.png")
		# 同姿态对照原版与像素版，保留握点和真实宽刀身投影。
		var yaw: float = lab.battlefield.camera.rotation.y+PI/3
		player.facing = Vector2(sin(yaw),cos(yaw))
		combat.locked_direction = Vector3(sin(yaw),0,cos(yaw))
		combat.swing_time = combat.attack_duration*0.65+1.0/60
		combat._physics_process(1.0/60)
		adapter.sync(1.0)
		var location: Vector3 = combat.weapon.global_position
		check(adapter.card.global_position.distance_to(location)<0.00001,id+" 纸片中心与真实握柄重合")
		check(combat.weapon.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY,id+" 实体只保留投影，不重复显示")
		if DisplayServer.get_name()!="headless":
			for pixel in [false,true]:
				adapter.set_enabled(pixel)
				adapter.sync(1.0)
				await frames(3)
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://work/weapon_pixels/%s_%s.png" % [id,"pixel" if pixel else "original"])
		adapter.set_enabled(false)
		check(combat.weapon.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_ON and not adapter.card.visible,id+" 切回原版完整恢复模型")
		adapter.set_enabled(true)
		combat.weapon.hide()
		adapter.sync(1.0)
		check(not adapter.card.visible,id+" 隐藏源武器时纸片同步隐藏")
		combat.weapon.show()
		adapter.sync(1.0)
		lab.export_frame()
		check(lab.caption.text.contains("已导出"),id+" 试验场导出当前颜色与深度 PNG 成功")
	if DisplayServer.get_name()!="headless":
		var comparison := Image.create(800,1050,false,Image.FORMAT_RGBA8)
		for row in 3:
			for column in 2:
				var path := "res://work/weapon_pixels/%s_%s.png" % [["sword","cleaver","knife"][row],["original","pixel"][column]]
				comparison.blit_rect(Image.load_from_file(path),Rect2i(440,80,400,350),Vector2i(column*400,row*350))
		comparison.save_png("res://work/weapon_pixels/comparison.png")
	# PNG 与深度元数据配对，便于人工按相同格子核对。
	var file := FileAccess.open("res://work/weapon_pixels/atlas.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"version":1,"cell_size":Baker.SIZE,"columns":12,"rows":9,"pixel_size":Baker.PIXEL_SIZE,"pivot":[64,64],"depth_span":Baker.DEPTH_SPAN,"depth_encoding":"RG16 = R*256+G; meters = (RG16/65535 - 0.5)*6","actions":{"sword":"sword_slash","cleaver":"heavy_swing","knife":"light_rise"}},"\t"))

func difference(a: Image,b: Image) -> int:
	var result := 0
	for y in a.get_height():
		for x in a.get_width():
			var p := a.get_pixel(x,y)
			var q := b.get_pixel(x,y)
			if absf(p.r-q.r)+absf(p.g-q.g)+absf(p.b-q.b)>0.12: result += 1
	return result

## 让正式物理时序自然推进，验证移动攻击、蹲姿和腾空下仍跟手；不只摆拍关键帧。
func live_motion() -> void:
	var player: CharacterBody3D = lab.battlefield.player
	var combat: Node3D = lab.battlefield.combat
	player.set_physics_process(true)
	combat.set_physics_process(true)
	for id in ["sword","cleaver","knife"]:
		lab.equip(id)
		player.position = Vector3(-4,0.05,17)
		player.velocity = Vector3.ZERO
		player.test_motion = Vector2(0.4,0)
		combat.cooldown = 0
		combat.attack(combat.muzzle()+Vector3.RIGHT*2)
		var follow_ok := true
		var samples := {}
		for tick in 60:
			await physics_frame
			await process_frame
			if DisplayServer.get_name()!="headless": await RenderingServer.frame_post_draw
			else: await create_timer(0.0).timeout # 无头也等普通帧回调结束，再观察显示适配器。
			follow_ok = follow_ok and lab.adapter.card.global_position.distance_to(combat.weapon.global_position)<0.001
			samples[lab.adapter.last_key] = true
		check(follow_ok and samples.size()>8,id+" 实际移动攻击连续切帧并保持握柄对齐")
		player.test_motion = Vector2.ZERO
		player.test_crouch = true
		for tick in 12: await physics_frame
		await process_frame
		lab.adapter.sync(1.0)
		check(player.crouched and lab.adapter.card.global_position.distance_to(combat.weapon.global_position)<0.001,id+" 下蹲持握沿用真实低握点")
		player.test_crouch = false
		for tick in 12: await physics_frame
		player.velocity.y = player.JUMP_SPEED
		player.jumped = true
		for tick in 10: await physics_frame
		await process_frame
		lab.adapter.sync(1.0)
		check(not player.is_on_floor() and lab.adapter.card.global_position.distance_to(combat.weapon.global_position)<0.001,id+" 腾空时纸片仍随真实武器变换")

## 将墙放在斜向刀身中间；若误用整张纸片的统一深度，刀尖会穿墙，本对照会失败。
func depth_render() -> void:
	if DisplayServer.get_name()=="headless": return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(400,400)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.2
	camera.position = Vector3(0,0,6)
	world.add_child(camera)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40,-25,0)
	world.add_child(light)
	var sword := Art.sword()
	world.add_child(sword)
	sword.rotation_degrees = Vector3(25,55,0)
	var wall := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(8,8,0.05)
	wall.mesh = box
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color("443322")
	wall.material_override = mat
	world.add_child(wall)
	var adapter := Adapter.new()
	world.add_child(adapter)
	adapter.setup(sword,camera,light)
	var counts: Array = []
	# 按当前刀尖深度取中点；缩剑后旧固定墙位已接近刀尖，不能继续假定会挡住一半。
	var midpoint: float=sword.to_global(sword.get_meta("blade_tip")).z*.5
	for z in [0.5,midpoint,-2.0]:
		wall.position.z = z
		var images: Array[Image] = []
		for mode in 3:
			sword.visible = mode!=0
			adapter.set_enabled(mode==2)
			adapter.sync(1.0)
			await frames(3)
			await RenderingServer.frame_post_draw
			images.append(viewport.get_texture().get_image())
		var reference := difference(images[0],images[1])
		var pixels := difference(images[0],images[2])
		counts.append(pixels)
		print("墙深度 ",z," 原版/像素覆盖 ",reference,"/",pixels)
		check(pixels==0 if reference==0 else pixels>reference*0.65 and pixels<reference*1.4,"实际遮挡覆盖与三维原版一致 z="+str(z))
		images[2].save_png("res://work/weapon_pixels/depth_"+str(z)+".png")
	check(counts[0]==0 and counts[1]>0 and counts[1]<counts[2]*0.8,"纸片刀身能被墙局部切挡，既非置顶也非整张隐藏")
	# 刀光也走像素颜色/深度，不得绕开墙遮挡或重新变成平滑透明带。
	sword.hide()
	adapter.sync(1.0)
	var trail := preload("res://scripts/presentation/swing_trail.gd").new()
	world.add_child(trail)
	trail.sample_blade(true,Vector3(-0.8,-0.4,0),Vector3(-0.3,0.7,-0.8))
	trail.sample_blade(true,Vector3(-0.6,-0.4,0),Vector3(0.2,0.7,-0.8))
	trail.sample_blade(true,Vector3(-0.4,-0.4,0),Vector3(0.8,0.5,-0.8))
	var trail_counts: Array = []
	for z in [0.5,-2.0]:
		wall.position.z = z
		trail.hide()
		await frames(3)
		await RenderingServer.frame_post_draw
		var before := viewport.get_texture().get_image()
		trail.show()
		await frames(3)
		await RenderingServer.frame_post_draw
		var after := viewport.get_texture().get_image()
		trail_counts.append(difference(before,after))
		after.save_png("res://work/weapon_pixels/trail_"+str(z)+".png")
	check(trail_counts[0]==0 and trail_counts[1]>100,"实际像素刀光可见、被墙完全遮挡")
	check(coverage(trail.capture_frame().image)>50 and trail.pixel_material.get_shader_parameter("dither_fade"),"刀光存在真实低分辨率帧与像素消退")
	for i in 4: trail.sample_blade(false,Vector3.ZERO,Vector3.ZERO)
	await frames(2)
	check(not trail.card.visible and trail.mesh.get_surface_count()==0,"像素刀光沿用四帧结束清理")
	viewport.queue_free()
	await frames(2)

## 加载正式入口检查全部敌方武器，特别是弓弦版本、搭弓箭排除、死亡和共享缓存。
func production() -> void:
	Adapter.cache.clear()
	var previous_testing: bool = ProjectSettings.get_setting("tactical/testing",false)
	ProjectSettings.set_setting("tactical/testing",true)
	var field := preload("res://tests/fixtures/legacy/battlefield.tscn").instantiate()
	field.results_enabled = false
	root.add_child(field)
	while not is_instance_valid(field.guard): await physics_frame
	await frames(3)
	field.player.test_mode = true
	field.player.position = Vector3(-4,0.02,17)
	field.camera.size = 11
	field.hud.hide()
	var guards: Array = []
	var archers: Array = []
	for enemy in get_nodes_in_group("tactical_enemies"):
		enemy.ai_enabled = false
		if enemy.ranged: archers.append(enemy)
		else: guards.append(enemy)
	field.update_camera_position()
	for index in (guards+archers).size():
		var enemy: Node3D = (guards+archers)[index]
		enemy.position = field.player.position+Vector3((index-2)*1.2,0,-2)
		enemy.update_visuals(0)
	check(field.combat.weapon.has_node("PixelPresentation") and field.combat.bow.has_node("PixelPresentation"),"正式玩家匕首和弓自动绑定像素表现")
	var enemy_ok := guards.size()==3 and archers.size()==2
	for guard in guards:
		enemy_ok = enemy_ok and guard.sword.get_child(0).has_node("PixelPresentation") and guard.shield_node.get_child(0).has_node("PixelPresentation")
	for archer in archers: enemy_ok = enemy_ok and archer.sword.get_child(0).has_node("PixelPresentation")
	check(enemy_ok,"三名守卫剑盾、两名弓手全部接入")
	check(Adapter.cache.is_empty(),"正式启动和转向不再触发 CPU 烘焙/图像缓存")
	var studio := Image.create(5*256,448,false,Image.FORMAT_RGBA8)
	var sources := [Art.melee_model("knife"),Art.sword(),Art.melee_model("cleaver"),Art.shield(),Art.bow()]
	for index in sources.size():
		var model: MeshInstance3D = sources[index]
		var rotation := Vector3(1.25,0.2,-0.35) if index<3 else Vector3(0.15,0.35,-0.08) if index==3 else Vector3(0,1.1,0)
		var frame := Baker.bake(Baker.geometry(model),Basis.from_euler(rotation),Vector3(-0.3,0.7,0.6).normalized())
		var colors := {}
		var outline: Image = frame.image
		for y in 128:
			for x in 128:
				var color := outline.get_pixel(x,y)
				if color.a>0.5: colors[color.to_rgba32()] = true
		check(colors.size()>=5,"源模型装饰缩为像素仍保留明暗与材质分区 "+str(index))
		var crop := outline.get_region(Rect2i(32,0,64,112))
		crop.resize(256,448,Image.INTERPOLATE_NEAREST)
		studio.blit_rect(crop,Rect2i(0,0,256,448),Vector2i(index*256,0))
		model.free()
	studio.save_png("res://work/weapon_pixels/detailed_sources.png")
	var bow: MeshInstance3D = archers[0].sword.get_child(0)
	var visual: Node3D = bow.get_node("PixelPresentation")
	var phases := {}
	for phase in 9:
		Art.set_bow_draw(bow,phase/8.0,true)
		visual.sync(1.0)
		phases[hash(visual.capture_frame().image.get_data())] = true
	check(phases.size()>=6 and visual.geometry_revision==8,"弓弦随拉弓刷新几何与像素帧，没有冻结")
	var nocked: MeshInstance3D = bow.get_node("NockedArrow")
	check(nocked.cast_shadow!=GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY and not Baker.meshes(bow).has(nocked),"搭弓箭保留原像素贴图且不重复烘焙")
	Art.set_bow_draw(bow,0,false)
	check(not nocked.visible,"放箭后展示箭仍按原动作隐藏")
	var first: Node3D = guards[0].sword.get_child(0)
	var second: Node3D = guards[1].sword.get_child(0)
	second.global_basis = first.global_basis
	first.get_node("PixelPresentation").sync(1.0)
	second.get_node("PixelPresentation").sync(1.0)
	check(first.get_node("PixelPresentation").capture_frame().image==second.get_node("PixelPresentation").capture_frame().image,"相同守卫姿态共用离线导出图")
	var cached_key: String = first.get_node("PixelPresentation").last_key
	var saved_position: Vector3 = guards[0].position
	guards[0].position = Vector3(1000,0,1000)
	first.rotation.y += 0.5
	first.get_node("PixelPresentation").sync(1.0)
	check(first.get_node("PixelPresentation").last_key==cached_key,"屏外敌人不消耗新姿态烘焙")
	guards[0].position = saved_position
	first.get_node("PixelPresentation").sync(1.0)
	check(first.get_node("PixelPresentation").last_key!=cached_key,"重回画面立即恢复当前姿态")
	var timings: Array[float] = []
	Adapter.cache.clear()
	for step in 36:
		var start := Time.get_ticks_usec()
		for enemy in guards+archers:
			enemy.facing = Vector3.BACK.rotated(Vector3.UP,step*0.11+enemy.get_index()*0.1)
			enemy.state = "windup"
			enemy.attack_time = enemy.action_duration*(1-step/36.0)
			enemy.update_visuals(0)
			enemy.sword.get_child(0).get_node("PixelPresentation").sync(1.0)
			if not enemy.ranged: enemy.shield_node.get_child(0).get_node("PixelPresentation").sync(1.0)
		timings.append((Time.get_ticks_usec()-start)/1000.0)
	timings.sort()
	print("五敌人同时转向/蓄力含姿态与显示提交毫秒 median/max: ",timings[18],"/",timings.max())
	check(Adapter.cache.is_empty(),"五敌人连续变姿态没有重走 CPU 图像生成")
	# 留一名守卫和一名弓手在同一近景，供人工检查像素细节及双手/盾前后关系。
	for enemy in guards+archers: enemy.hide()
	for index in 2:
		var enemy: Node3D = guards[0] if index==0 else archers[0]
		enemy.show()
		enemy.position = field.player.position+Vector3(1.8+index*2,0,-0.4)
		enemy.facing = Vector3.BACK.rotated(Vector3.UP,field.camera.rotation.y+PI/3)
		enemy.state="guard" if index==0 else "windup"
		enemy.attack_time=0.1
		enemy.update_visuals(0)
	if DisplayServer.get_name()!="headless":
		await frames(4)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://work/weapon_pixels/enemy_equipment.png")
	guards[0].receive_strike(guards[0].position+Vector3.UP,Vector3.RIGHT,Vector3.RIGHT,1000)
	await physics_frame
	await physics_frame
	await frames(2)
	check(not first.is_visible_in_tree() and not guards[0].shield_node.is_visible_in_tree(),"敌人死亡同步隐藏剑盾和像素纸片")
	field.queue_free()
	await frames(2)
	ProjectSettings.set_setting("tactical/testing",previous_testing)

## 将 GPU 实际纹理与独立 CPU 光栅器逐像素对照，防止优化后镜像、偏色或深度编码变坏。
func gpu_equivalence() -> void:
	if DisplayServer.get_name()=="headless": return
	var backend := preload("res://scripts/presentation/pixel_frame_gpu.gd").new()
	root.add_child(backend)
	var sources := [Art.melee_model("knife"),Art.sword(),Art.melee_model("cleaver"),Art.shield(),Art.bow()]
	for index in sources.size():
		var model: MeshInstance3D = sources[index]
		var silhouettes_ok := true
		var values_ok := true
		var worst_mask := 0.0
		var worst_depth := 0.0
		var phases := {}
		for direction in 12:
			if index==4: Art.set_bow_draw(model,(direction%9)/8.0,true)
			var triangles := Baker.geometry(model)
			var view := Basis.from_euler(Vector3(0.6,direction*PI/6,0.2))
			var light := Vector3(-0.3,0.7,0.6).normalized()
			backend.set_triangles(triangles)
			backend.draw(view,light)
			await frames(2)
			await RenderingServer.frame_post_draw
			var packed: Image = backend.viewport.get_texture().get_image()
			var actual := packed.get_region(Rect2i(0,0,128,128))
			var depth := packed.get_region(Rect2i(128,0,128,128))
			var reference := Baker.bake(triangles,view,light)
			var mismatch := 0
			var total := 0
			var bad_values := 0
			var common := 0
			for y in 128:
				for x in 128:
					var a := actual.get_pixel(x,y)
					var b: Color = reference.image.get_pixel(x,y)
					if a.a>0.5 or b.a>0.5: total+=1
					if (a.a>0.5)!=(b.a>0.5): mismatch+=1
					if a.a>0.5 and b.a>0.5:
						common+=1
						var p := depth.get_pixel(x,y)
						var q: Color = reference.depth.get_pixel(x,y)
						var error := absf((p.r-q.r)*65280+(p.g-q.g)*255)/65535*6
						worst_depth=maxf(worst_depth,error)
						if error>0.002 or absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)>0.06:
							bad_values+=1
			var ratio := mismatch/float(maxi(total,1))
			worst_mask=maxf(worst_mask,ratio)
			silhouettes_ok = silhouettes_ok and total>10 and ratio<0.15
			values_ok = values_ok and bad_values/float(maxi(common,1))<0.05
			if bad_values/float(maxi(common,1))>=0.05: print("GPU value mismatch model/direction/count/common: ",index,"/",direction,"/",bad_values,"/",common)
			phases[hash(actual.get_data())]=true
			if direction==2: packed.save_png("res://work/weapon_pixels/gpu_%d.png" % index)
		print("GPU/CPU model ",index," silhouette error/max depth: ",worst_mask,"/",worst_depth)
		check(silhouettes_ok,"GPU 十二朝向像素轮廓与 CPU 导出一致 "+str(index))
		check(values_ok and phases.size()>6,"GPU 色阶、逐像素深度及动态切帧一致 "+str(index))
		model.free()
	backend.queue_free()
	await frames(2)

func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://work/weapon_pixels")
	if "gpu-only" in OS.get_cmdline_user_args():
		await gpu_equivalence()
		quit(1 if failures else 0)
		return
	lab = preload("res://tools/weapon_pixel_lab.tscn").instantiate()
	root.add_child(lab)
	await frames(3)
	check(not lab.battlefield.progress_enabled,"美术实验不读取或写入真实进度")
	await poses()
	await live_motion()
	await depth_render()
	await gpu_equivalence()
	lab.queue_free()
	await frames(2)
	await production()
	print("PIXEL_WEAPON: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

