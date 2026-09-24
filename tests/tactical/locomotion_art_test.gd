extends SceneTree
## 验证疾跑输入、跳跃阶段、持械握点，以及渲染器中的真实墙前/墙后遮挡。
const Source = preload("res://scripts/art/baked_character_source.gd")
const Frame = preload("res://scripts/art/frame_spec.gd")
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
	# 中型装备是未加速的移动基准；轻型增益由 weapon_choreography 实测。
	lab.combat.apply_weapon(load("res://data/weapons/sword.tres"))
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
		var expected: Vector2 = lab.camera.unproject_position(player.baked_visual.last_grip)
		max_grip_error = maxf(max_grip_error, grip.distance_to(expected))
		for layer in player.baked_visual.layers.values(): shadows_match = shadows_match and layer.shadow.texture != null and layer.shadow.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
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
	if DisplayServer.get_name()=="headless":
		print("SKIP 后退跳真实指针验证需要 Rendered；其余移动检查照常执行")
		return
	await place()
	var player = lab.player
	player.test_mode = false
	Input.action_press("move_left")
	var was_opposite := false
	var knees_ok := true
	var rig: Node3D=load("res://assets/characters/player_rig.tscn").instantiate()
	root.add_child(rig)
	var captured := false
	var aim_changed := false
	var first_direction := -1
	for i in 52:
		var aim_axis: Vector3 = lab.camera.global_basis.x
		if i >= 20: aim_axis = aim_axis.rotated(Vector3.UP, PI / 2)
		var target: Vector3 = Vector3(player.position.x, 0, player.position.z) + aim_axis * 8
		var mouse := InputEventMouseMotion.new()
		mouse.position = lab.camera.unproject_position(target)
		# 生产玩家逐帧采样 Viewport 指针，仅发 MouseMotion 不会移动系统指针。
		root.warp_mouse(mouse.position)
		Input.parse_input_event(mouse)
		if i == 3: check(player.request_jump(), "鼠标瞄准与后退移动同时生效时能够起跳")
		await frames(1)
		if player.jump_frame < 0: continue
		if first_direction < 0: first_direction = player.direction_index
		if i < 20 and posmod(player.direction_index-player.movement_direction,12) == 6: was_opposite = true
		if i > 20 and player.direction_index != first_direction: aim_changed = true
		rig.apply_state(Frame.character(player.direction_index,player.art_step,player.crouched,player.movement_direction,0,-1,0,-1,0,player.sprinting,player.jump_frame))
		for side in ["L","R"]:
			var hip: Vector3=rig._bone_point("Thigh"+side)
			var knee: Vector3=rig._bone_point("Shin"+side)
			var foot: Vector3=rig._bone_point("Foot"+side)
			var axis: Vector3=(foot-hip).normalized()
			knees_ok=knees_ok and (knee-hip-axis*(knee-hip).dot(axis)).dot(Vector3.BACK)>-.0001
		if not captured and player.jump_frame == 1 and DisplayServer.get_name() != "headless":
			captured = true
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://work/player_backward_jump_live.png")
	rig.free()
	check(was_opposite, "运行中身体朝向与移动方向确实相反")
	check(aim_changed and knees_ok, "后退跳及空中转动鼠标后，膝盖仍朝身体前方")
	Input.action_release("move_left")
	player.test_mode = true
	await place()

func run() -> void:
	ProjectSettings.set_setting("tactical/testing", true)
	lab = load("res://tests/fixtures/legacy/battlefield.tscn").instantiate()
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
	print("LOCOMOTION_ART: %d checks, %d failures" % [checks, failures])
	lab.queue_free()
	await process_frame
	quit(1 if failures else 0)
