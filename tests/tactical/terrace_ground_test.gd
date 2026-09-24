extends SceneTree
## 原小院实走分层地形，验证合并边界、坡道、坑出口、追击与射线，不写玩家存档。
const Layout=preload("res://scripts/world/terrace_layout.gd")
var lab: Node3D
var actor: CharacterBody3D
var ground: StaticBody3D
var checks:=0
var failures:=0
var terrain_seed:=0
func _initialize() -> void: run.call_deferred()
func frames(count: int) -> void:
	for i in count: await physics_frame
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+message)
func point(x: float,z: float) -> Vector3: return Vector3(x,ground.height_at(Vector2(x,z))+.04,z)
func walk(x: float,z: float) -> bool:
	for i in 650:
		var d:=Vector2(x-actor.position.x,z-actor.position.z)
		if d.length()<.2:
			actor.test_motion=Vector2.ZERO
			return true
		actor.test_motion=d.normalized()
		await physics_frame
	actor.test_motion=Vector2.ZERO
	return false
func shot(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://work/terraces/"+label+".png")
func run() -> void:
	ProjectSettings.set_setting("tactical/testing",true)
	DirAccess.make_dir_recursive_absolute("res://work/terraces")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("seed="): terrain_seed=int(arg.trim_prefix("seed="))
	var model:=Layout.new()
	model.put(Vector2i(2,2),2)
	check(model.exposed_edges().size()==4,"单块只生成四条外露边")
	model.put(Vector2i(3,2),2)
	check(model.exposed_edges().size()==6,"双块合并后删除内部侧壁")
	model.put(Vector2i(3,3),2)
	check(model.exposed_edges().size()==8,"L 形保留凹角，无对角假连接")
	model.cells.clear()
	model.put(Vector2i(2,2),-2)
	check(model.exposed_edges().size()==4,"坑由四周高地自动生成内壁")
	var boundary_correct:=true
	for f in model.exposed_edges():
		if absf(f.a.y-Layout.BASE)>.001 or absf(f.low_a.y-(Layout.BASE-1))>.001: boundary_correct=false
	check(boundary_correct,"坑的侧壁只覆盖实际高差")
	model.build(42)
	var snapshot:=model.cells.duplicate(true)
	model.build(42)
	check(model.cells==snapshot,"种子布局可以复现")
	model.build(73)
	check(model.cells!=snapshot,"不同种子改变外围平台组合")
	var valid:=true
	for seed in [0,1,2,42,73,100]:
		model.build(seed)
		valid=valid and model.validate().is_empty()
	check(valid,"多种子布局的坡顶坡脚均接同高平台")
	model.cells.clear()
	model.put(Vector2i(2,2),1)
	model.put(Vector2i(3,2),2)
	check(is_equal_approx(model.height_in(Vector2i(2,2),Vector2.ONE),Layout.BASE+.5) and model.exposed_edges().size()==7,"半高平台保持平面，与全高平台只补实际高度差")
	lab=load("res://scenes/courtyard_combat.tscn").instantiate()
	lab.story_mode=false # 显式运行保留的地形实验，F5 故事默认平地。
	lab.terrace_seed=terrain_seed
	root.add_child(lab)
	current_scene=lab
	while not is_instance_valid(lab.objective): await frames(1)
	if is_instance_valid(lab.run_flow): lab.run_flow.queue_free()
	lab.objective.set_physics_process(false)
	actor=lab.player
	actor.test_mode=true
	ground=lab.terrace_ground
	for enemy in get_nodes_in_group("tactical_enemies"):
		enemy.ai_enabled=false
		enemy.update_visuals(0)
	await frames(5)
	check(ground!=null and lab.rolling_meadow==null,"F5 使用分层地形，旧缓坡保留但未装配")
	var accurate:=true
	for p in [Vector2(10,13),Vector2(22,6),Vector2(22,-2),Vector2(26,2),Vector2(26,-2),Vector2(34,10),Vector2(34,14)]:
		var hit:=lab.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(p.x,5,p.y),Vector3(p.x,-2,p.y),1))
		if hit.is_empty() or absf(hit.position.y-ground.height_at(p))>.005: accurate=false
	check(accurate,"平台、两级坡道与坑的真实碰撞高度正确")
	check(await walk(8,13) and await walk(16,13) and await walk(22,13),"从小院实际步行进入粗格区域")
	ground.set_artwork(false)
	await shot("entrance_clay")
	ground.set_artwork(true)
	await shot("entrance_art")
	check(await walk(22,2),"沿入口坡道自然走上一级平台")
	check(actor.is_on_floor() and actor.position.y>.9,"一级平台真实承托角色")
	check(await walk(22,6) and await walk(26,6) and await walk(26,-2),"经第二段坡道走上二级平台")
	check(actor.is_on_floor() and actor.position.y>1.9,"二级平台真实高度为两米")
	await shot("upper_art")
	ground.set_artwork(false)
	await shot("upper_clay")
	ground.set_artwork(true)
	actor.move_intent=Vector2(0,1)
	check(actor.request_roll(),"平台上可以翻滚")
	await frames(40)
	check(actor.is_on_floor() and actor.position.y>.8,"翻滚可经过平台与坡道连接")
	check(await walk(26,6) and await walk(22,6) and await walk(22,13),"沿原路从两级平台下行")
	check(await walk(28,18) and await walk(34,18) and await walk(34,10),"实际沿出口坡道走入凹坑")
	check(actor.is_on_floor() and actor.position.y<-.8,"坑底不会被原平板挡住")
	await shot("pit_art")
	check(await walk(34,18),"坑内可以原路走出")
	# 前方断崖不可当坡面直接穿上去，实际移动与阻弹共用骨架边界。
	actor.position=point(18.8,0)
	actor.velocity=Vector3.ZERO
	actor.test_motion=Vector2.RIGHT
	await frames(45)
	actor.test_motion=Vector2.ZERO
	check(actor.position.x<19.8,"垂直崖壁阻挡直接步行")
	var hit=preload("res://scripts/combat/space_trace.gd").trace(lab.get_world_3d(),Vector3(18,.5,0),Vector3(23,.5,0))
	check(hit.get("collider")==ground,"崖壁阻挡低位战斗射线")
	actor.position=point(22,2)
	actor.velocity=Vector3.ZERO
	actor.safe_zone=false
	var enemy=get_nodes_in_group("tactical_enemies")[0]
	enemy.position=point(22,10)
	enemy.home=enemy.position
	enemy.velocity=Vector3.ZERO
	enemy.state="chase"
	enemy.last_seen=actor.position
	enemy.facing=Vector3.FORWARD
	await frames(5)
	var skip: Array[RID]=[actor.get_rid(),enemy.get_rid()]
	var route: PackedVector3Array=lab.routes.path(enemy.position,actor.position,skip)
	check(route.size()>1 and route[route.size()-1].distance_to(actor.position)<1,"导航跨越平地与平台坡道")
	enemy.ai_enabled=true
	await frames(240)
	enemy.ai_enabled=false
	check(enemy.position.distance_to(actor.position)<3 and enemy.position.y>.75,"敌人实际沿坡追到一级平台")
	actor.hp=100
	actor.position=point(22,-1)
	actor.velocity=Vector3.ZERO
	enemy.position=point(22,-1.9)
	enemy.velocity=Vector3.ZERO
	enemy.knockback=Vector3.ZERO
	enemy.hp=100
	enemy.can_block=false
	await frames(5)
	lab.combat.apply_weapon(load("res://data/weapons/sword.tres"))
	lab.combat.cooldown=0
	lab.combat.attack(enemy.position+Vector3.UP)
	await frames(43)
	check(enemy.hp<100,"高台上实际挥剑命中")
	var rid: RID=ground.get_node("TerrainCollision").shape.get_rid()
	ground.set_guides(true)
	ground.set_artwork(false)
	check(ground.get_node("TerrainCollision").shape.get_rid()==rid,"网格与灰模切换不改碰撞")
	ground.set_guides(false)
	ground.set_artwork(true)
	check(await walk(22,10) and await walk(16,12) and await walk(8,13) and await walk(.8,13.6),"平台可步行返回原小院")
	if terrain_seed!=0:
		for cell in ground.layout.cells:
			if cell.y!=9 or ground.layout.spec(cell).rise==0: continue
			var x: float=Layout.ORIGIN.x+(cell.x+.5)*Layout.CELL
			check(await walk(8,13) and await walk(x,13) and await walk(x,22),"随机平台可从小院实际步行登顶")
			check(actor.is_on_floor() and actor.position.y>.9,"随机平台坡道与承托面实际相接")
			await shot("seed_%d"%terrain_seed)
			check(await walk(x,13) and await walk(8,13),"随机平台可以沿坡退出")
	else:
		# 只为核查半格、双格接缝取景；通行断言使用上面的真实步行，不把传送当通路验证。
		for sample in [[Vector2(16,-5),"half_block_art"],[Vector2(36,-5),"double_block_art"]]:
			actor.position=point(sample[0].x,sample[0].y)
			actor.velocity=Vector3.ZERO
			await frames(5)
			await shot(sample[1])
	print("TERRACE_GROUND: %d checks, %d failures"%[checks,failures])
	lab.queue_free()
	await process_frame
	quit(1 if failures else 0)
