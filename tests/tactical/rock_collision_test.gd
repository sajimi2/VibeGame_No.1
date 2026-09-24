extends SceneTree
## 用主场景的真实巨石参数复现蹲姿卡死，并验证敌人的完整绕石返回路线。
const Actor = preload("res://scripts/actors/player.gd")
const Enemy = preload("res://scripts/actors/enemy.gd")
const Prop = preload("res://scripts/world/battle_prop.gd")
const Routes = preload("res://scripts/world/terrain_routes.gd")
var checks := 0
var failures := 0
var world: Node3D
var actor: CharacterBody3D
var enemy: CharacterBody3D
var routes: Node

func _initialize() -> void: run.call_deferred()
func frames(n: int) -> void:
	for i in n: await physics_frame
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", label)

## 玩家从十二侧分别站立/蹲行贴石，然后反向退出；这组轨迹在旧版有 66/240 卡死。
func check_player(original: Node3D) -> void:
	for crouch in [false, true]:
		actor.test_crouch = crouch
		for direction in 12:
			var outward := Vector3(sin(direction * TAU / 12), 0, cos(direction * TAU / 12))
			actor.position = outward * 4.8 + Vector3.UP * 0.05
			actor.velocity = Vector3.ZERO
			actor.test_motion = Vector2.ZERO
			await frames(4)
			actor.test_motion = Vector2(-outward.x, -outward.z)
			await frames(150 if crouch else 85)
			var near: Vector3 = actor.position
			actor.test_motion = Vector2(outward.x, outward.z)
			await frames(75 if crouch else 40)
			check((actor.position - near).dot(outward) > 1.0, "%s 蹲姿=%s 方向=%d 无法退出，位置=%s" % [original.name, crouch, direction, near])
	actor.test_motion = Vector2.ZERO
	actor.position = Vector3(15, 0.05, 15)
	actor.safe_zone = true

## 让真实守卫状态机沿导航绕石回家；不会用传送或直接设置终点假装路径通过。
func check_enemy(label: String) -> void:
	routes.build(world.get_world_3d(), Rect2(-6, -6, 12, 12))
	for direction in 4:
		var side := Vector3(sin(direction * PI / 2), 0, cos(direction * PI / 2))
		enemy.ai_enabled = false
		enemy.position = side * 4.8 + Vector3.UP * 0.03
		enemy.velocity = Vector3.ZERO
		enemy.home = -side * 4.8
		enemy.state = "return"
		enemy.repath = 0
		enemy.ai_enabled = true
		for i in 650:
			await frames(1)
			if enemy.position.distance_to(enemy.home) < 0.65: break
		check(enemy.position.distance_to(enemy.home) < 0.65, "%s 守卫绕石方向 %d，位置=%s" % [label, direction, enemy.position])
		enemy.ai_enabled = false
		enemy.position = Vector3(18, 0.05, 18)

func run() -> void:
	ProjectSettings.set_setting("tactical/testing", true)
	world = Node3D.new()
	root.add_child(world)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(50, 0.2, 50)
	floor_shape.shape = box
	floor_body.add_child(floor_shape)
	floor_body.position.y = -0.1
	world.add_child(floor_body)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(0, 20, 20)
	camera.look_at(Vector3.ZERO)
	actor = Actor.new()
	actor.test_mode = true
	actor.safe_zone = true
	actor.camera = camera
	world.add_child(actor)
	routes = Routes.new()
	world.add_child(routes)
	enemy = Enemy.new()
	enemy.ai_enabled = false
	enemy.camera = camera
	enemy.player = actor
	enemy.routes = routes
	enemy.position = Vector3(18, 0.05, 18)
	world.add_child(enemy)
	var scene: Node3D = load("res://tests/fixtures/legacy/battlefield.tscn").instantiate()
	for original in scene.get_node("Cover").get_children():
		if original.kind != 0: continue
		var prop := Prop.new()
		prop.extent = original.extent
		prop.variation = original.variation
		world.add_child(prop)
		await frames(2)
		await check_player(original)
		# 敌箭包含地形层也应击中原石面，而非范围略大的移动代理。
		var ray := PhysicsRayQueryParameters3D.create(Vector3(-5, 1, 0), Vector3(5, 1, 0), 1 | 8)
		check(world.get_world_3d().direct_space_state.intersect_ray(ray).get("collider") == prop, "%s 箭矢仍命中真实石面" % original.name)
		await check_enemy(str(original.name))
		prop.queue_free()
		await frames(2)
	scene.free()
	print("ROCK_COLLISION: %d checks, %d failures" % [checks, failures])
	world.queue_free()
	await process_frame
	quit(1 if failures else 0)
