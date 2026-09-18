extends SceneTree
## 验证十二朝向的人体/蹲姿、实际握柄投影和石材碰撞一致性，存档全程隔离。
const Art = preload("res://scripts/presentation/directional_art.gd")
const Pose = preload("res://scripts/presentation/character_pose.gd")
var lab: Node3D
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()
func frames(count: int) -> void:
	for i in count: await physics_frame
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ") + label)

## 导出全方向预览与蹲起过渡，便于人眼验收比例；不把图片差异等同于美术质量。
func verify_atlas() -> void:
	var atlas := Image.create(32 * 12, 48 * 5, false, Image.FORMAT_RGBA8)
	var standing := {}
	var crouching := {}
	for direction in 12:
		standing[hash(Art.texture(direction, -1, false).get_image().get_data())] = true
		crouching[hash(Art.texture(direction, -1, true).get_image().get_data())] = true
		var transition := {}
		for frame in 7:
			transition[hash(Art.texture(direction, -1, true, false, direction, 0, false, -1, 0, -1, frame).get_image().get_data())] = true
		check(transition.size() >= 6, "方向 %d 有实际蹲起过渡帧" % direction)
		for row in 5:
			var pic := Art.texture(direction, -1 if row in [0, 1] else row, row in [1, 2], false, direction, 2 if row == 3 else 4 if row == 4 else 0).get_image()
			atlas.blit_rect(pic, Rect2i(0, 0, 32, 48), Vector2i(direction * 32, row * 48))
	check(standing.size() == 12, "站姿保留十二个不同朝向")
	check(crouching.size() == 12, "蹲姿保留十二个不同朝向")
	atlas.resize(1536, 960, Image.INTERPOLATE_NEAREST)
	atlas.save_png("res://work/character_pose_sheet.png")
	var transition_sheet := Image.create(32 * 7, 48 * 2, false, Image.FORMAT_RGBA8)
	for row in 2:
		for frame in 7:
			var pic := Art.texture(3 if row == 0 else 9, -1, true, false, -1, 0, false, -1, 0, -1, frame).get_image()
			transition_sheet.blit_rect(pic, Rect2i(0, 0, 32, 48), Vector2i(frame * 32, row * 48))
	transition_sheet.resize(896, 384, Image.INTERPOLATE_NEAREST)
	transition_sheet.save_png("res://work/player_crouch_transition.png")

## 独立用相机投影和当前纹理帧检查握柄，能发现更新顺序造成的一帧脱手。
func grip_error() -> float:
	var player = lab.player
	var projected: Vector2 = lab.camera.unproject_position(lab.combat.hand.global_position)
	var anchor: Vector2 = lab.camera.unproject_position(player.sprite.global_position)
	var pixels_per_meter: float = root.size.y / lab.camera.size
	var expected: Vector2 = anchor + (player.grip_pixel - Vector2(16, 48)) * player.sprite.pixel_size * pixels_per_meter
	return projected.distance_to(expected)

## 实际蹲起过程中保持原碰撞高度，姿态动画不能退回整张纸片缩放。
func verify_player() -> void:
	var player = lab.player
	var combat = lab.combat
	player.position = Vector3(-18, 0.02, 12)
	await frames(4)
	var largest_error := 0.0
	var upright_scale: Vector3 = player.sprite.scale
	for direction in 12:
		var facing := Vector3(sin(direction * PI / 6), 0, cos(direction * PI / 6)).rotated(Vector3.UP, lab.camera.rotation.y)
		player.facing = Vector2(facing.x, facing.z)
		player.test_crouch = true
		var changed := {}
		for i in 12:
			await frames(1)
			changed[player.sprite.texture.get_instance_id()] = true
			largest_error = maxf(largest_error, grip_error())
		check(changed.size() >= 4 and player.sprite.scale == upright_scale, "方向 %d 蹲下改变关节帧而非缩放" % direction)
		player.test_crouch = false
		await frames(12)
	check(is_equal_approx(player.shape_node.shape.height, player.STAND_HEIGHT), "站起仍恢复原胶囊高度")
	for crouch in [false, true]:
		player.test_crouch = crouch
		await frames(12)
		combat.cooldown = 0
		combat.attack(player.position + Vector3.FORWARD * 2 + Vector3.UP)
		for i in 20:
			await frames(1)
			largest_error = maxf(largest_error, grip_error())
		check(player.sprite.scale == upright_scale, "蹲姿或站姿挥刀不压缩整个人物")
	print("握柄最大投影偏差：%.6f px" % largest_error)
	check(largest_error < 0.1, "静止、蹲起、挥刀时剑柄与本帧手心对齐")
	check(is_equal_approx(player.shape_node.shape.height, player.CROUCH_HEIGHT), "蹲姿仍使用原胶囊高度")
	player.test_crouch = false

## 石面射线仍贴合外观；角色使用独立移动代理，不能误改箭矢命中轮廓。
func verify_stone() -> void:
	var matches := true
	var count := 0
	for cover in get_nodes_in_group("battle_cover"):
		var visual: MeshInstance3D = cover.get_node("StoneVisual")
		var collider: CollisionShape3D = cover.get_node("StoneCollision")
		matches = matches and visual.mesh.get_faces() == collider.shape.get_faces()
		count += 1
	check(count >= 19 and matches, "所有石墙、巨石的可见形状仍与射线碰撞三角面一致")
	var pixel_shader: ShaderMaterial = lab.lighting.pixel_material
	check(not pixel_shader.shader.code.contains("floor("), "世界调色层没有新增整幅画面降采样")

## 在真实战场保存正常视距及近景；只冻结测试实例，不操作用户运行中的游戏。
func capture_scene() -> void:
	if DisplayServer.get_name() == "headless": return
	var player = lab.player
	player.position = Vector3(-9, 0.02, 12)
	player.facing = Vector2(0, -1)
	await frames(16)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://work/art_battlefield_after.png")
	lab.camera.size = 7.0
	var view_angle: float = lab.camera.rotation.y + PI / 6
	player.facing = Vector2(sin(view_angle), cos(view_angle))
	await frames(16)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://work/art_character_closeup.png")
	player.test_crouch = true
	await frames(12)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://work/art_crouch_closeup.png")

func run() -> void:
	verify_atlas()
	ProjectSettings.set_setting("tactical/testing", true)
	lab = load("res://scenes/battlefield.tscn").instantiate()
	lab.results_enabled = false
	root.add_child(lab)
	current_scene = lab
	lab.player.test_mode = true
	while not is_instance_valid(lab.guard): await frames(1)
	for enemy in get_nodes_in_group("tactical_enemies"):
		enemy.ai_enabled = false
		# 冻结 AI 前尚未经历首个物理帧，主动摆好武器，避免预览到初始化原点。
		enemy.update_visuals(0)
	await verify_player()
	verify_stone()
	await capture_scene()
	print("CHARACTER_ART: %d checks, %d failures" % [checks, failures])
	await create_timer(0.5).timeout
	lab.queue_free()
	await process_frame
	quit(1 if failures else 0)
