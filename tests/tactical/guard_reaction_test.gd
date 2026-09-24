extends SceneTree
## 回归守卫刀光坐标与盾挡后的受击感知；全程隔离玩家存档。
const Arrow = preload("res://scripts/combat/arrow.gd")
const Trace = preload("res://scripts/combat/space_trace.gd")
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

## 对比最终送往渲染的世界顶点与刀刃采样点，而非仅确认刀光节点存在。
func trail_error(trail: MeshInstance3D) -> float:
	if trail.mesh.get_surface_count() == 0: return INF
	var vertices: PackedVector3Array = trail.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var worst := 0.0
	for vertex in vertices:
		var rendered: Vector3 = trail.global_transform * vertex
		var nearest := INF
		for sample in trail.samples:
			nearest = minf(nearest, minf(rendered.distance_to(sample.base), rendered.distance_to(sample.tip)))
		worst = maxf(worst, nearest)
	return worst

## 在每名守卫的实际出生点生成挥刀，并在其移动和转身后检查历史刀光仍在原世界位置。
func verify_guard_trail(guard: CharacterBody3D, index: int) -> void:
	var spawn: Vector3 = guard.global_position
	for thrust in [false, true]:
		guard.trail.samples.clear()
		guard.thrust = thrust
		guard.state = "recover"
		guard.hurt_recovery = false
		guard.action_duration = 0.5 if thrust else 0.32
		guard.recovery_duration = 0.8 if thrust else 0.65
		guard.attack_time = guard.recovery_duration - 0.04
		guard.facing = Vector3.BACK.rotated(Vector3.UP, index * 1.4)
		guard.update_visuals(0)
		guard.position += Vector3(0.13, 0, -0.09)
		guard.attack_time -= 0.025
		guard.update_visuals(0.1)
		var error := trail_error(guard.trail)
		print("Trail guard=%d thrust=%s world_error=%.5fm origin=%s" % [index, thrust, error, guard.trail.global_position])
		check(error < 0.001, "守卫 %d 的%s刀光与刀刃对齐" % [index, "突刺" if thrust else "横斩"])
		guard.position += Vector3(0.7, 0, 0.4)
		guard.rotation.y = 0.6
		check(trail_error(guard.trail) < 0.001, "守卫移动转身不拖动已生成的刀光")
		guard.rotation = Vector3.ZERO
		guard.position = spawn
	guard.thrust = false
	guard.trail.samples.clear()
	guard.attack_time = guard.recovery_duration - 0.04
	guard.update_visuals(0)
	guard.attack_time -= 0.035
	guard.update_visuals(0)
	lab.player.position = spawn + Vector3(0, 0.02, 3)
	lab.player.velocity = Vector3.ZERO
	lab.update_camera_position()
	await capture("trail_%d" % index)
	for i in 4: guard.trail.sample_blade(false, Vector3.ZERO, Vector3.ZERO)
	check(guard.trail.mesh.get_surface_count() == 0, "挥刀结束后刀光自然消退")

## 非原点且带旋转缩放的父节点，同样不能让世界空间刀光发生二次变换。
func verify_transformed_parent() -> void:
	var parent := Node3D.new()
	parent.position = Vector3(12, 3, -7)
	parent.rotation = Vector3(0.15, 0.7, -0.1)
	parent.scale = Vector3(1.2, 0.8, 1.4)
	lab.add_child(parent)
	var trail = preload("res://scripts/presentation/swing_trail.gd").new()
	parent.add_child(trail)
	trail.sample_blade(true, Vector3(10, 4, -5), Vector3(11, 4, -5))
	trail.sample_blade(true, Vector3(10, 4, -4.8), Vector3(11, 4, -4.5))
	check(trail_error(trail) < 0.001, "父节点初始旋转缩放不改变世界刀刃采样")
	parent.position += Vector3(3, 2, 4)
	parent.rotate_y(0.5)
	check(trail_error(trail) < 0.001, "父节点后续变换不拖走历史刀光")
	parent.queue_free()

## 渲染模式保存证据；命令行 -- before/after 区分修复前后的截图。
func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	var suffix := "after" if OS.get_cmdline_user_args().is_empty() else OS.get_cmdline_user_args()[0]
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://work/guard_reaction_%s_%s.png" % [label, suffix])

## 让实际箭从视距外击中正面盾牌，验证减伤、调查、后续搜索及重新发现玩家。
func verify_shield_alert(guard: CharacterBody3D) -> void:
	var player = lab.player
	guard.position = Vector3(-18, 0, 1)
	guard.home = guard.position
	guard.state = "guard"
	guard.hp = guard.max_hp
	guard.facing = Vector3.BACK
	guard.target_visible = false
	guard.lost_time = 10
	guard.search_time = 0
	guard.last_seen = Vector3.ZERO
	guard.velocity = Vector3.ZERO
	guard.knockback = Vector3.ZERO
	player.position = Vector3(-18, 0.02, 15)
	await frames(4)
	check(not guard.can_see_target(), "射手位于守卫视距外")
	var arrow := Arrow.new()
	lab.add_child(arrow)
	arrow.global_position = player.global_position + Vector3.UP * 1.15
	arrow.velocity = Trace.launch_velocity(arrow.global_position, guard.global_position + Vector3.UP)
	for i in 90:
		await frames(1)
		if arrow.stopped: break
	check(arrow.stopped and arrow.result.get("collider") == guard, "实际远程箭命中守卫")
	check(guard.hp == guard.max_hp - 6 and guard.block_flash > 0, "盾挡仍只承受三成伤害")
	check(guard.state == "investigate" and not guard.hurt_recovery, "未看见射手时受盾击立即调查，不进入受击硬直")
	var estimate: Vector3 = guard.last_seen
	check(estimate.z > guard.position.z and estimate.distance_to(player.position) > 8, "只调查来袭方向，不读取远处射手精确位置")
	player.position = Vector3(15, 0.02, 18)
	guard.ai_enabled = true
	var initial: Vector3 = guard.position
	await frames(30)
	check(guard.position.distance_to(initial) > 0.25, "警觉后实际向调查点移动")
	check(guard.last_seen.distance_to(estimate) < 0.01 and not guard.target_visible, "隐藏射手移动不会更新调查点")
	guard.ai_enabled = false
	guard.state = "search"
	guard.search_time = 0.01
	guard.choose_movement(0.02)
	check(guard.state == "return", "未发现目标时仍可结束搜索并返回")
	guard.state = "guard"
	guard.facing = Vector3.BACK
	player.position = guard.position + Vector3(0, 0.02, 3)
	await frames(3)
	guard.update_senses(0.02)
	check(guard.target_visible and guard.state == "chase", "重新看见玩家后进入追击")
	var before: int = guard.hp
	guard.receive_strike(guard.position + Vector3.UP, Vector3.BACK, Vector3.FORWARD)
	check(guard.hp == before - 6 and guard.state == "chase", "已追击的守卫盾挡不被强制切回调查或硬直")
	arrow.queue_free()

## 加载最新战场，覆盖三名守卫的不同出生位置及两种攻击动作。
func run() -> void:
	ProjectSettings.set_setting("tactical/testing", true)
	lab = load("res://tests/fixtures/legacy/battlefield.tscn").instantiate()
	lab.results_enabled = false
	root.add_child(lab)
	current_scene = lab
	lab.player.test_mode = true
	for i in 120:
		await frames(1)
		if is_instance_valid(lab.guard): break
	var guards: Array[CharacterBody3D] = []
	for enemy in get_nodes_in_group("tactical_enemies"):
		enemy.ai_enabled = false
		if not enemy.ranged: guards.append(enemy)
	check(guards.size() == 3, "使用最新战场的三名守卫")
	for i in guards.size(): await verify_guard_trail(guards[i], i)
	verify_transformed_parent()
	if not guards.is_empty(): await verify_shield_alert(guards[0])
	print("GUARD_REACTION: %d checks, %d failures" % [checks, failures])
	# 等末次受击音效播放完成再卸载场景，避免无头进程退出时音频资源仍被占用。
	await create_timer(0.5).timeout
	lab.queue_free()
	await process_frame
	quit(1 if failures else 0)
