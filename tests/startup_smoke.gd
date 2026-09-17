extends SceneTree
## 加载配置中的主场景，并隔离玩家真实进度。
var checks := 0
var failures := 0
func _initialize() -> void:
	run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ") + label)
## 以隔离存档方式加载默认入口，检查运行时装配、相机、装备和安全出生点。
func run() -> void:
	ProjectSettings.set_setting("tactical/testing", true)
	var path: String = ProjectSettings.get_setting("application/run/main_scene")
	check(path == "res://scenes/battlefield.tscn", "F5 boots the current 3D battlefield")
	var scene = load(path).instantiate()
	root.add_child(scene)
	current_scene = scene
	for i in 120:
		await physics_frame
		if is_instance_valid(scene.run_flow): break
	# 运行时节点需经过物理帧，才能更新出生点的安全区状态。
	for i in 3: await physics_frame
	check(is_instance_valid(scene.run_flow), "runtime assembly completes")
	check(get_nodes_in_group("tactical_enemies").size() == 5, "three guards and two archers")
	check(scene.camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "fixed orthographic camera")
	check(not scene.progression.persist, "startup does not access player progress")
	check(scene.combat.melee_damage == 16 and scene.combat.attack_interval == 0.29, "knife resource applied")
	check(scene.player.safe_zone, "spawn is inside safe camp")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://work/battlefield_refactored.png")
	print("STARTUP: %d checks, %d failures" % [checks, failures])
	scene.queue_free()
	await process_frame
	quit(1 if failures else 0)
