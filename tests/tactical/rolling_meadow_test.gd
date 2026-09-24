extends SceneTree
## 在原小院中实际走到草地：采样碰撞、跑跳滚、寻路追击、坡上命中和绘画阴影。
var lab: Node3D
var player: CharacterBody3D
var ground: StaticBody3D
var checks:=0
var failures:=0
var max_ground_gap:=0.0
func _initialize() -> void: run.call_deferred()
func frames(count: int) -> void:
	for i in count: await physics_frame
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+message)
func point(x: float,z: float) -> Vector3: return Vector3(x,ground.height_at(Vector2(x,z))+.04,z)

func walk_to(target: Vector3) -> bool:
	for i in 600:
		var delta:=Vector2(target.x-player.position.x,target.z-player.position.z)
		if delta.length()<.22:
			player.test_motion=Vector2.ZERO
			return true
		player.test_motion=delta.normalized()
		max_ground_gap=maxf(max_ground_gap,absf(player.position.y-ground.height_at(Vector2(player.position.x,player.position.z))))
		await physics_frame
	player.test_motion=Vector2.ZERO
	return false

func shot(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://work/meadow_"+label+".png")

func run() -> void:
	ProjectSettings.set_setting("tactical/testing",true)
	lab=load("res://scenes/courtyard_combat.tscn").instantiate()
	lab.story_mode=false # 显式运行保留的地形实验，F5 故事默认平地。
	lab.outskirts_mode=1
	root.add_child(lab)
	current_scene=lab
	while not is_instance_valid(lab.routes): await frames(1)
	await frames(5)
	if is_instance_valid(lab.run_flow): lab.run_flow.queue_free()
	lab.objective.set_physics_process(false)
	player=lab.player
	player.test_mode=true
	ground=lab.rolling_meadow
	for enemy in get_nodes_in_group("tactical_enemies"):
		enemy.ai_enabled=false
		enemy.update_visuals(0)
	check(ground!=null and lab.courtyard.props.size()==24,"原小院直接装配东侧地表和八件复用画稿")
	var repeat=ground.get_script().new()
	repeat.position=Vector3(500,0,0)
	lab.add_child(repeat)
	check(repeat.heights==ground.heights,"相同种子生成完全一致的地形")
	repeat.queue_free()
	var alternate=ground.get_script().new()
	alternate.terrain_seed=17
	alternate.position=Vector3(500,0,0)
	lab.add_child(alternate)
	check(alternate.heights!=ground.heights,"改变种子生成不同的自然细节")
	alternate.queue_free()
	var lowest:=10.0
	var highest:=-10.0
	var steepest:=0.0
	for z in ground.rows-1:
		for x in ground.columns-1:
			var h: float=ground.heights[z*ground.columns+x]
			lowest=minf(lowest,h)
			highest=maxf(highest,h)
			var dx: float=(ground.heights[z*ground.columns+x+1]-h)/ground.STEP
			var dz: float=(ground.heights[(z+1)*ground.columns+x]-h)/ground.STEP
			steepest=maxf(steepest,Vector2(dx,dz).length())
			var d: float=ground.heights[(z+1)*ground.columns+x+1]
			dx=(d-ground.heights[(z+1)*ground.columns+x])/ground.STEP
			dz=(d-ground.heights[z*ground.columns+x+1])/ground.STEP
			steepest=maxf(steepest,Vector2(dx,dz).length())
	print("MEADOW_RANGE: %.3f .. %.3f m, maximum slope %.2f degrees"%[lowest,highest,rad_to_deg(atan(steepest))])
	check(highest-lowest>2.0 and highest-lowest<3.5,"有可感知的两到三米起伏")
	check(steepest<tan(deg_to_rad(30)),"地表坡度保留角色和寻路余量")
	var accurate:=true
	for p in [Vector2(8,13),Vector2(12.3,14.4),Vector2(23.2,1.3),Vector2(24.2,12.1),Vector2(32.8,19.2)]:
		var ray:=PhysicsRayQueryParameters3D.create(Vector3(p.x,5,p.y),Vector3(p.x,-2,p.y),1)
		var hit:=lab.get_world_3d().direct_space_state.intersect_ray(ray)
		accurate=accurate and not hit.is_empty() and absf(hit.position.y-ground.height_at(p))<.005
	check(accurate,"显示高度采样与真实三角形碰撞一致")
	check(is_equal_approx(ground.height_at(Vector2(8,13)),-.02),"院外接缝同高，无叠层平板托住谷底")
	var player_excluded: Array[RID]=[player.get_rid()]
	var connecting_route: PackedVector3Array=lab.routes.path(player.position,point(29,13),player_excluded)
	check(connecting_route.size()>1 and connecting_route[connecting_route.size()-1].distance_to(point(29,13))<1.0,"院内与草地使用同一张连通导航图")
	await shot("entry")
	check(await walk_to(point(8,13)),"从原出生点实际走到支路入口")
	check(await walk_to(point(15,ground.path_z(15))),"实际跨越平地与高度场接缝")
	await shot("path")
	check(await walk_to(point(23,ground.path_z(23))),"沿弯路步行进入浅谷")
	await shot("valley")
	player.test_sprint=true
	check(await walk_to(point(23,3)),"真实疾跑爬上土丘")
	player.test_sprint=false
	await frames(5)
	check(max_ground_gap<.16,"连续行走没有悬空或钻地")
	await shot("hill")
	var guide_key:=InputEventKey.new()
	guide_key.physical_keycode=KEY_F3
	guide_key.pressed=true
	lab._unhandled_input(guide_key)
	check(ground.surface.material_override.get_shader_parameter("terrain_guides"),"F3 开启真实坡面参考网格")
	await shot("hill_grid")
	lab._unhandled_input(guide_key)
	var start:=player.position
	check(player.request_jump(),"坡顶允许正常跳跃")
	await frames(18)
	check(player.position.y>start.y+.5,"跳跃确实离开坡面")
	await frames(45)
	check(player.is_on_floor() and absf(player.position.y-start.y)<.15,"跳跃落回真实坡面")
	player.facing=Vector2(0,1)
	player.move_intent=Vector2(0,1)
	start=player.position
	check(player.request_roll(),"斜坡可以启动翻滚")
	await frames(40)
	check(player.position.distance_to(start)>2 and player.is_on_floor(),"下坡翻滚实际位移且保持地面碰撞")
	var enemy=get_nodes_in_group("tactical_enemies")[0]
	player.position=point(23,9)
	player.velocity=Vector3.ZERO
	player.safe_zone=false
	player.hp=100
	enemy.position=point(17,10)
	enemy.home=enemy.position
	enemy.velocity=Vector3.ZERO
	enemy.knockback=Vector3.ZERO
	enemy.state="chase"
	enemy.last_seen=player.position
	enemy.facing=(player.position-enemy.position).normalized()
	await frames(3)
	var excluded: Array[RID]=[enemy.get_rid(),player.get_rid()]
	check(lab.routes.path(enemy.position,player.position,excluded).size()>1,"原寻路图覆盖新坡面")
	enemy.ai_enabled=true
	await frames(145)
	enemy.ai_enabled=false
	check(Vector2(enemy.position.x-player.position.x,enemy.position.z-player.position.z).length()<3.0,"现有敌人真实沿坡追击")
	player.hp=100
	player.hurt_time=0
	player.position=point(20,6)
	player.velocity=Vector3.ZERO
	enemy.position=point(20,5.1)
	enemy.velocity=Vector3.ZERO
	enemy.knockback=Vector3.ZERO
	enemy.can_block=false
	enemy.hp=100
	await frames(5)
	lab.combat.apply_weapon(load("res://data/weapons/sword.tres"))
	lab.combat.cooldown=0
	lab.combat.attack(enemy.position+Vector3.UP)
	await frames(43)
	check(enemy.hp<100,"坡上实际挥剑物理命中敌人")
	var trace=preload("res://scripts/combat/space_trace.gd").trace(lab.get_world_3d(),Vector3(12,.7,1),Vector3(34,.7,1))
	check(trace.get("collider")==ground,"土丘真实阻挡低位弹道和战斗射线")
	var fitted:=true
	for prop in lab.courtyard.props:
		if not prop.name.begins_with("MeadowProp"): continue
		var arrays: Array=prop.shadow.mesh.surface_get_arrays(0)
		for vertex in arrays[Mesh.ARRAY_VERTEX]:
			var world: Vector3=prop.shadow.global_transform*vertex
			if absf(world.y-ground.height_at(Vector2(world.x,world.z))-.018)>.002: fitted=false
	check(fitted,"新增物件阴影顶点贴合地表，沿用公共样式")
	player.position=point(23,14)
	player.velocity=Vector3.ZERO
	await frames(10)
	await shot("combat")
	var reached_summit:=true
	for p in ground.climb_path():
		if not await walk_to(point(p.x,p.y)):
			reached_summit=false
			break
	check(reached_summit and player.position.y>2.5,"沿新土路从谷底实际步行到丘顶，无需跳跃")
	check(await walk_to(point(15,16)) and await walk_to(point(8,13)) and await walk_to(point(.8,13.6)),"扩展区可以实际步行返回小院")
	print("ROLLING_MEADOW: %d checks, %d failures"%[checks,failures])
	lab.queue_free()
	await process_frame
	quit(1 if failures else 0)
