extends SceneTree
## 实际射击后平移/旋转角色，验证附着变换、生命周期以及真实渲染中的深度遮挡。
const Arrow = preload("res://scripts/combat/arrow.gd")
const Trace = preload("res://scripts/combat/space_trace.gd")
const ArrowArt = preload("res://scripts/presentation/arrow_art.gd")
var lab: Node3D
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()
func frames(count: int) -> void:
	for i in count: await physics_frame
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ")+label)

func shoot(target: Node3D, hostile: bool = false) -> Node3D:
	var arrow := Arrow.new()
	arrow.hostile = hostile
	arrow.hit_mask = 2 if hostile else 16
	lab.add_child(arrow)
	arrow.global_position = target.global_position+Vector3(0,1.15,6)
	arrow.velocity = Trace.launch_velocity(arrow.global_position,target.global_position+Vector3.UP,18)
	for i in 90:
		await frames(1)
		if arrow.stopped: break
	return arrow

func same_transform(a: Transform3D, b: Transform3D) -> bool:
	return a.origin.distance_to(b.origin) < 0.0001 and a.basis.is_equal_approx(b.basis)

## 在真正的盾挡后检查箭尖是否在可见盾面，然后覆盖全部十二朝向和移动后的相对变换。
func shield(guard: CharacterBody3D) -> void:
	guard.position = Vector3(-18,0,1)
	guard.facing = Vector3.BACK
	guard.hp = guard.max_hp
	guard.state = "guard"
	guard.update_visuals(0)
	lab.player.position = Vector3(-18,0.02,15)
	await frames(2)
	var arrow := await shoot(guard)
	check(arrow.stopped and arrow.result.get("collider") == guard and arrow.attachment.region == "格挡","实际射击命中守卫盾挡")
	check(guard.hp == guard.max_hp-6 and guard.state == "investigate","盾挡减伤和远处受击警觉保持")
	var initial: Transform3D = guard.shield_node.global_transform.affine_inverse()*arrow.global_transform
	check(initial.origin.x > 0.12 and initial.origin.x < 0.6 and initial.origin.z < -0.30,"箭尖落在实际盾面而非胶囊正中央")
	arrow.lifetime = 10
	for direction in 12:
		guard.position += Vector3(0.13,0,0.09)
		guard.facing = Vector3.BACK.rotated(Vector3.UP,direction*PI/6)
		guard.update_visuals(0.1)
		await frames(2)
		check(is_instance_valid(arrow) and same_transform(guard.shield_node.global_transform.affine_inverse()*arrow.global_transform,initial),"盾箭随移动和朝向 %d 保持相对位置与入射方向" % direction)
	check(is_instance_valid(arrow),"角色仍存活时，附着箭不因原五秒飞行寿命消失")
	await capture_rotations(guard,arrow)
	guard.hp = 0
	await frames(3)
	check(not is_instance_valid(arrow),"死亡隐藏盾牌时同步释放附着箭")

## 非格挡身体箭也要跟随 facing；覆盖守卫、弓手、玩家三种实际受击入口。
func body(target: CharacterBody3D, player: bool = false) -> void:
	target.hp = 100 if player else target.max_hp
	target.position = Vector3(-18,0.02,1)
	if player:
		target.facing = Vector2(0,1)
		target.safe_zone = false
		target.invulnerable = 0
	else:
		target.state = "windup"
		target.facing = Vector3.BACK
		target.attack_time = 0.2
		target.update_visuals(0)
	await frames(2)
	var arrow := await shoot(target,player)
	check(arrow.stopped and arrow.result.get("collider") == target and arrow.attachment.region == "身体","实际%s身体命中" % ("玩家" if player else "弓手" if target.ranged else "守卫"))
	if not player and not target.ranged: await capture_rotations(target,arrow,"body")
	var initial: Transform3D = target.projectile_attachment_frame("身体").affine_inverse()*arrow.global_transform
	check(Vector2(initial.origin.x,initial.origin.z).length() <= 0.061,"身体箭尖深入纸片主体，不悬在胶囊外壳")
	var all_match := true
	for direction in 12:
		target.position += Vector3(0.07,0,0.08)
		var facing := Vector3.BACK.rotated(Vector3.UP,direction*PI/6)
		if player: target.facing = Vector2(facing.x,facing.z)
		else:
			target.facing = facing
			target.update_visuals(0.1)
		await frames(2)
		all_match = all_match and same_transform(target.projectile_attachment_frame("身体").affine_inverse()*arrow.global_transform,initial)
	check(all_match,"身体箭在十二朝向移动中保持附着")
	if player: await player_fade(target,arrow,initial)
	target.position = Vector3(15,0,18)
	if is_instance_valid(arrow): arrow.queue_free()
	await frames(2)

## 真命中后计时，淡出中转身依旧附着；生命只扣一次，材质不影响别的箭。
func player_fade(target: CharacterBody3D, arrow: Node3D, initial: Transform3D) -> void:
	var hp: int = target.hp
	var other := ArrowArt.model()
	check(arrow.attachment.fade_after==4.0,"仅玩家声明四秒附着停留时间")
	while arrow.attached_time<3.9: await frames(1)
	check(is_instance_valid(arrow) and arrow.shaft.material_override.albedo_color.a==1,"停留阶段箭仍完整显示")
	if DisplayServer.get_name()!="headless":
		lab.camera.size = 5
		await frames(2)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://work/player_arrow_hold.png")
	while arrow.attached_time<4.4: await frames(1)
	target.facing = Vector2(1,0)
	target.position += Vector3(0.1,0,0.1)
	await frames(1)
	check(arrow.shaft.material_override.albedo_color.a>0.15 and arrow.shaft.material_override.albedo_color.a<0.6 and same_transform(target.projectile_attachment_frame("身体").affine_inverse()*arrow.global_transform,initial),"淡出中保持半透明并跟随玩家转身")
	check(other.material_override.albedo_color.a==1 and other.material_override.transparency==BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR,"一支箭淡出不会修改别的箭材质")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://work/player_arrow_fade.png")
	await frames(35)
	check(not is_instance_valid(arrow) and target.hp==hp,"淡出结束清理节点，不重复扣血")
	other.free()

## 保存真实盾箭十二朝向截图；临时冻结测试镜头，避免跟随远处玩家把守卫拍出画面。
func capture_rotations(guard: CharacterBody3D, arrow: Node3D, label: String = "shield") -> void:
	if DisplayServer.get_name() == "headless": return
	lab.set_physics_process(false)
	guard.position = Vector3(-4,0.02,17)
	guard.marker.hide()
	lab.camera.size = 5
	lab.camera.global_position = guard.global_position+Vector3.UP+lab.camera.global_basis.z*16
	var sheet := Image.create(4*320,3*320,false,Image.FORMAT_RGBA8)
	for direction in 12:
		guard.facing = Vector3.BACK.rotated(Vector3.UP,direction*PI/6)
		guard.hurt = 0
		guard.update_visuals(0)
		await frames(2)
		await RenderingServer.frame_post_draw
		var screen := root.get_texture().get_image()
		var center := Vector2i(lab.camera.unproject_position(guard.global_position+Vector3.UP))
		sheet.blit_rect(screen,Rect2i(center-Vector2i(160,160),Vector2i(320,320)),Vector2i(direction%4,direction/4)*320)
	sheet.save_png("res://work/arrow_%s_12.png" % label)
	check(arrow.is_inside_tree(),"真实渲染十二朝向期间附着箭保持有效")
	lab.set_physics_process(true)

func count_arrow(image: Image) -> int:
	var count := 0
	for y in image.get_height():
		for x in image.get_width():
			var color := image.get_pixel(x,y)
			if color.r > 0.15 and color.b > 0.10 and color.g < 0.02: count += 1
	return count

## 用独立视口和实际箭材质比较墙前/墙后像素数，而非只断言 no_depth_test 参数。
func depth_render() -> void:
	if DisplayServer.get_name() == "headless": return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(384,384)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3
	world.add_child(camera)
	camera.position = Vector3(0,1,8)
	var arrow := ArrowArt.model()
	arrow.material_override = arrow.material_override.duplicate()
	arrow.material_override.albedo_color = Color.MAGENTA
	world.add_child(arrow)
	arrow.position = Vector3(-0.4,1,1)
	arrow.rotation.y = PI/2
	var wall := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(3,3,0.2)
	wall.mesh = box
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color("32424a")
	wall.material_override = mat
	world.add_child(wall)
	wall.position = Vector3(0,1,0)
	await frames(3)
	await RenderingServer.frame_post_draw
	var front := viewport.get_texture().get_image()
	front.save_png("res://work/arrow_depth_front.png")
	arrow.position.z = -1
	await frames(3)
	await RenderingServer.frame_post_draw
	var behind := viewport.get_texture().get_image()
	behind.save_png("res://work/arrow_depth_behind.png")
	check(count_arrow(front)>60,"实际渲染：墙前可见箭头、木杆与尾羽像素")
	check(count_arrow(behind)==0,"实际渲染：墙后箭矢完全遮住，不穿墙显示")
	arrow.position.z = 1
	ArrowArt.set_opacity(arrow,0.5)
	await frames(2)
	await RenderingServer.frame_post_draw
	var faded := viewport.get_texture().get_image()
	var dimmer := 0
	for y in front.get_height():
		for x in front.get_width():
			var color := front.get_pixel(x,y)
			if color.r>0.5 and color.g<0.02 and color.b>0.5 and faded.get_pixel(x,y).r<color.r*0.9 and faded.get_pixel(x,y).r>0.1: dimmer+=1
	check(dimmer>40,"实际渲染：箭像素逐渐变淡而非整支突然裁掉")
	arrow.position.z = -1
	await frames(2)
	await RenderingServer.frame_post_draw
	check(count_arrow(viewport.get_texture().get_image())==0,"半透明阶段仍被墙正确遮挡")
	viewport.queue_free()
	await process_frame

func lifetimes() -> void:
	var target := Node3D.new()
	lab.add_child(target)
	var arrow := Arrow.new()
	lab.add_child(arrow)
	arrow.stopped = true
	arrow.attachment = preload("res://scripts/combat/impact_attachment.gd").new()
	arrow.attachment.bind(arrow,target,"身体",Vector3.FORWARD)
	target.queue_free()
	await frames(3)
	check(not is_instance_valid(arrow),"命中节点卸载后箭矢安全清理")
	arrow = Arrow.new()
	lab.add_child(arrow)
	arrow.lifetime = 6
	await frames(3)
	check(not is_instance_valid(arrow),"未附着的飞行箭仍按五秒寿命释放")
	arrow = Arrow.new()
	lab.add_child(arrow)
	arrow.velocity = Vector3.DOWN*10
	arrow.orient_flight()
	check((-arrow.global_basis.z).is_equal_approx(Vector3.DOWN),"垂直射击箭尖朝向稳定，无 look_at 退化")
	arrow.queue_free()

func run() -> void:
	ProjectSettings.set_setting("tactical/testing",true)
	lab = load("res://scenes/battlefield.tscn").instantiate()
	lab.results_enabled = false
	root.add_child(lab)
	current_scene = lab
	lab.player.test_mode = true
	while not is_instance_valid(lab.guard): await frames(1)
	var archer: CharacterBody3D
	for enemy in get_nodes_in_group("tactical_enemies"):
		enemy.ai_enabled = false
		if enemy.ranged: archer = enemy
	lab.effects.streams.clear()
	lab.player.set_physics_process(false)
	lab.combat.set_physics_process(false)
	await shield(lab.guard)
	await body(lab.guard)
	await body(archer)
	await body(lab.player,true)
	await lifetimes()
	await depth_render()
	print("ARROW_ATTACHMENT: %d checks, %d failures" % [checks,failures])
	lab.queue_free()
	await process_frame
	quit(1 if failures else 0)
