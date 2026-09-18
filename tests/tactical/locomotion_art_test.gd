extends SceneTree
## 验证疾跑输入、跳跃阶段、持械握点，以及渲染器中的真实墙前/墙后遮挡。
const Art = preload("res://scripts/presentation/directional_art.gd")
const Pose = preload("res://scripts/presentation/character_pose.gd")
var lab: Node3D
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()
func frames(n: int) -> void:
	for i in n: await physics_frame
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ") + label)

## 每个方向均检查跑步八相位和五段跳跃，不用放大旧步行帧来冒充新动画。
func atlas() -> void:
	var run_sheet := Image.create(384, 384, false, Image.FORMAT_RGBA8)
	var jump_sheet := Image.create(384, 240, false, Image.FORMAT_RGBA8)
	for direction in 12:
		var run_frames := {}
		var jump_frames := {}
		for step in 8:
			var pic := Art.texture(direction, step, false, false, direction, 0, false, -1, 0, -1, 0, true).get_image()
			run_frames[hash(pic.get_data())] = true
			run_sheet.blit_rect(pic, Rect2i(0, 0, 32, 48), Vector2i(direction * 32, step * 48))
		check(run_frames.size() >= 7, "方向 %d 有完整疾跑步态" % direction)
		for phase in 5:
			var pic := Art.texture(direction, -1, false, false, direction, 0, false, -1, 0, -1, 0, false, phase).get_image()
			jump_frames[hash(pic.get_data())] = true
			jump_sheet.blit_rect(pic, Rect2i(0, 0, 32, 48), Vector2i(direction * 32, phase * 48))
		check(jump_frames.size() == 5, "方向 %d 有五段不同跳跃姿态" % direction)
	run_sheet.resize(768, 768, Image.INTERPOLATE_NEAREST)
	run_sheet.save_png("res://work/player_run_12.png")
	jump_sheet.resize(768, 480, Image.INTERPOLATE_NEAREST)
	jump_sheet.save_png("res://work/player_jump_12.png")

## 膝盖应位于髋踝连线的身体前侧；脚尖指向与膝盖折向不能因后退或横移而相反。
func knees_face_body(data: Dictionary) -> bool:
	for side in [-1, 1]:
		var hip: Vector3 = data.joints["hip%d" % side]
		var knee: Vector3 = data.joints["knee%d" % side]
		var foot: Vector3 = data.joints["foot%d" % side]
		var toe: Vector3 = data.joints["toe%d" % side]
		var straight := hip.lerp(foot, (knee.y - hip.y) / (foot.y - hip.y))
		var bend := knee - straight
		var front := Vector3(toe.x-foot.x, 0, toe.z-foot.z).normalized()
		if bend.dot(front) <= 0.4 or absf(bend.x) > 0.01: return false
	return true

## 交叉遍历身体十二朝向与移动十二朝向，覆盖此前图集漏掉的后退/横移。
func leg_facing() -> void:
	var backward := Image.create(384, 240, false, Image.FORMAT_RGBA8)
	for facing in 12:
		var jumps_ok := true
		var runs_ok := true
		for movement_direction in 12:
			for phase in 5:
				jumps_ok = knees_face_body(Pose.build(facing, -1, false, movement_direction, 0, -1, 0, -1, 0, false, phase)) and jumps_ok
			for phase in 8:
				runs_ok = knees_face_body(Pose.build(facing, phase, false, movement_direction, 0, -1, 0, -1, 0, true)) and runs_ok
		check(jumps_ok, "身体方向 %d 跳跃时膝盖不随移动方向反弯" % facing)
		check(runs_ok, "身体方向 %d 疾跑时膝盖不随移动方向反弯" % facing)
		for phase in 5:
			var pic := Art.texture(facing, -1, false, false, (facing+6)%12, 0, false, -1, 0, -1, 0, false, phase).get_image()
			backward.blit_rect(pic, Rect2i(0,0,32,48), Vector2i(facing*32,phase*48))
	backward.resize(768, 480, Image.INTERPOLATE_NEAREST)
	backward.save_png("res://work/player_backjump_12.png")

func place() -> void:
	lab.player.test_motion = Vector2.ZERO
	lab.player.test_crouch = false
	lab.player.test_sprint = false
	lab.player.position = Vector3(0, 0.02, 17)
	lab.player.velocity = Vector3.ZERO
	lab.player.jumped = false
	await frames(15)

## 用游戏实际输入与物理位移测速度，再检查跳跃整段的握柄投影和阴影帧。
func movement() -> void:
	var player = lab.player
	await place()
	var origin: Vector3 = player.position
	player.test_motion = Vector2.RIGHT
	await frames(30)
	check(absf(player.position.x - origin.x - 2.1) < 0.12, "普通行走仍为 4.2 米每秒")
	await place()
	origin = player.position
	player.test_mode = false
	Input.action_press("move_right")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_SHIFT
	key.pressed = true
	Input.parse_input_event(key)
	await frames(30)
	check(Vector2(player.position.x-origin.x, player.position.z-origin.z).length() > 3.2 and player.sprinting, "实际 Shift 输入以 6.8 米每秒疾跑")
	key.pressed = false
	Input.parse_input_event(key)
	Input.action_release("move_right")
	player.test_mode = true
	await place()
	player.test_motion = Vector2.RIGHT
	player.test_crouch = true
	player.test_sprint = true
	origin = player.position
	await frames(30)
	check(absf(player.position.x-origin.x-1.0) < 0.1 and not player.sprinting, "下蹲不会叠加疾跑速度")
	await place()
	player.test_motion = Vector2.RIGHT
	player.test_sprint = true
	check(player.request_jump(), "疾跑途中可以起跳")
	var phases := {}
	var peak := 0.0
	var max_grip_error := 0.0
	var shadows_match := true
	for i in 60:
		await frames(1)
		peak = maxf(peak, player.position.y)
		phases[player.jump_frame] = true
		if i == 10: lab.combat.attack(player.position + Vector3.RIGHT * 2 + Vector3.UP)
		var grip: Vector2 = lab.camera.unproject_position(lab.combat.hand.global_position)
		var anchor: Vector2 = lab.camera.unproject_position(player.sprite.global_position)
		var expected: Vector2 = anchor + (player.grip_pixel-Vector2(16,48)) * player.sprite.pixel_size * root.size.y / lab.camera.size
		max_grip_error = maxf(max_grip_error, grip.distance_to(expected))
		shadows_match = shadows_match and player.world_shadow.texture == player.sprite.texture
	check(peak > 0.95 and peak < 1.15, "实测跳高约 1.05 米")
	check(phases.has(0) and phases.has(1) and phases.has(2) and phases.has(3) and phases.has(4), "运行经过蹬地、上升、顶点、下落和落地")
	check(max_grip_error < 0.1, "疾跑、跳跃和空中挥刀均保持握柄对齐")
	check(shadows_match, "太阳投影逐帧使用当前人物剪影")
	await place()
	var wall = lab.box("SprintStop", player.position+Vector3(1.0,0.8,0), Vector3(0.3,1.6,4), "wall")
	player.test_motion = Vector2.RIGHT
	player.test_sprint = true
	await frames(35)
	check(player.art_step == -1, "疾跑顶墙时停止踏步动画")
	wall.queue_free()
	await place()

func screen_image() -> Image:
	await frames(3)
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

## 使用实际鼠标事件朝右瞄准、向左移动起跳，再在空中改变瞄准方向。
func backward_jump() -> void:
	await place()
	var player = lab.player
	player.test_mode = false
	Input.action_press("move_left")
	var was_opposite := false
	var knees_ok := true
	var captured := false
	var aim_changed := false
	var first_direction := -1
	for i in 52:
		var aim_axis: Vector3 = lab.camera.global_basis.x
		if i >= 20: aim_axis = aim_axis.rotated(Vector3.UP, PI / 2)
		var target: Vector3 = Vector3(player.position.x, 0, player.position.z) + aim_axis * 8
		var mouse := InputEventMouseMotion.new()
		mouse.position = lab.camera.unproject_position(target)
		Input.parse_input_event(mouse)
		if i == 3: check(player.request_jump(), "鼠标瞄准与后退移动同时生效时能够起跳")
		await frames(1)
		if player.jump_frame < 0: continue
		if first_direction < 0: first_direction = player.direction_index
		if i < 20 and posmod(player.direction_index-player.movement_direction,12) == 6: was_opposite = true
		if i > 20 and player.direction_index != first_direction: aim_changed = true
		var data := Pose.build(player.direction_index, player.art_step, player.crouched, player.movement_direction, player.attack_pose, player.attack_arm, player.attack_weight, player.bow_draw, 0, player.sprinting, player.jump_frame)
		knees_ok = knees_face_body(data) and knees_ok
		if not captured and player.jump_frame == 1 and DisplayServer.get_name() != "headless":
			captured = true
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://work/player_backward_jump_live.png")
	check(was_opposite, "运行中身体朝向与移动方向确实相反")
	check(aim_changed and knees_ok, "后退跳及空中转动鼠标后，膝盖仍朝身体前方")
	Input.action_release("move_left")
	player.test_mode = true
	await place()

## 同一像素位置比较有墙/无墙的本体颜色：前景人物保留，后景人物只露出墙上的部分。
func depth_render() -> void:
	if DisplayServer.get_name() == "headless": return
	var player = lab.player
	player.position = Vector3(-4, 0.02, 17)
	lab.camera.size = 7.0
	lab.combat.hand.hide()
	player.facing = Vector2(0,1)
	await frames(8)
	var baseline := await screen_image()
	var tex: Image = player.sprite.texture.get_image()
	var anchor: Vector2 = lab.camera.unproject_position(player.sprite.global_position)
	var factor: float = player.sprite.pixel_size * root.size.y / lab.camera.size
	var toward := Vector3(lab.camera.global_basis.z.x,0,lab.camera.global_basis.z.z).normalized()
	var wall = lab.box("DepthWall", player.position-toward*0.75+Vector3.UP*0.7, Vector3(3,1.4,0.7), "wall")
	wall.rotation.y = lab.camera.rotation.y
	var front := await screen_image()
	front.save_png("res://work/depth_player_front.png")
	wall.position = player.position+toward*0.75+Vector3.UP*0.7
	var behind := await screen_image()
	behind.save_png("res://work/depth_player_behind.png")
	var total := 0
	var kept_front := 0
	var kept_behind := 0
	for y in 48:
		for x in 32:
			if tex.get_pixel(x,y).a < 0.9: continue
			var pixel := Vector2i(anchor+(Vector2(x+0.5,y+0.5)-Vector2(16,48))*factor)
			var base := baseline.get_pixelv(pixel)
			total += 1
			if base.is_equal_approx(front.get_pixelv(pixel)): kept_front += 1
			if base.is_equal_approx(behind.get_pixelv(pixel)): kept_behind += 1
	print("墙前本体保留 %d/%d；墙后本体保留 %d/%d" % [kept_front,total,kept_behind,total])
	check(float(kept_front)/total > 0.97, "实际渲染：靠墙前站立的人物不被墙切掉")
	check(float(kept_behind)/total < 0.6, "实际渲染：墙后的腿和躯干被墙正确遮住")
	wall.queue_free()
	lab.combat.hand.show()
	var image := await screen_image()
	image.save_png("res://work/character_shadow_after.png")
	player.test_crouch = true
	image = await screen_image()
	await frames(12)
	image = await screen_image()
	image.save_png("res://work/crouch_shadow_after.png")

func run() -> void:
	atlas()
	leg_facing()
	ProjectSettings.set_setting("tactical/testing", true)
	lab = load("res://scenes/battlefield.tscn").instantiate()
	lab.results_enabled = false
	root.add_child(lab)
	current_scene = lab
	lab.player.test_mode = true
	while not is_instance_valid(lab.guard): await frames(1)
	for enemy in get_nodes_in_group("tactical_enemies"):
		enemy.ai_enabled = false
		enemy.update_visuals(0)
	# 本专项只测运动与画面；加速无头模拟不启动实时音频，音频由 guard_encounter 验证。
	if DisplayServer.get_name() == "headless": lab.effects.streams.clear()
	await movement()
	await backward_jump()
	await depth_render()
	print("LOCOMOTION_ART: %d checks, %d failures" % [checks, failures])
	lab.queue_free()
	await process_frame
	quit(1 if failures else 0)
