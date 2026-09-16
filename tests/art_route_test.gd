extends SceneTree
var lab: Node3D
var failures := 0
func _initialize() -> void: run.call_deferred()
func frames(count: int) -> void:
	for i in count: await physics_frame
func check(value: bool, label: String) -> void:
	print(("PASS " if value else "FAIL ") + label)
	if not value: failures += 1
func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://work/art_route_" + label + ".png")
func run() -> void:
	lab = load("res://scenes/tactical_height.tscn").instantiate()
	root.add_child(lab)
	current_scene = lab
	var actor: CharacterBody3D = lab.player
	actor.test_mode = true
	actor.position = Vector3(12.5, 0.05, -6.9)
	await frames(15)
	actor.test_motion = Vector2(0, -1)
	await frames(60)
	actor.test_motion = Vector2.ZERO
	await frames(5)
	check(actor.is_on_floor() and absf(actor.position.y - 0.8) < 0.04, "walk onto low irregular shelf")
	actor.test_motion = Vector2(0, 1)
	await frames(60)
	actor.test_motion = Vector2.ZERO
	await frames(5)
	check(actor.is_on_floor() and absf(actor.position.y) < 0.04, "walk off low shelf via ramp")
	for point in [Vector3(2.5, 2, -7), Vector3(7, 2, -8), Vector3(12.5, 0.8, -10.5)]:
		var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP, point - Vector3.UP, 1)
		var hit := lab.get_world_3d().direct_space_state.intersect_ray(query)
		check(not hit.is_empty() and absf(hit.position.y - point.y) < 0.01 and hit.normal.y > 0.99, "flat cap has upward collision at " + str(point))
	actor.position = Vector3(5, 2.05, -5.8)
	actor.velocity = Vector3.ZERO
	await frames(15)
	await capture("orthographic")
	print("ART_ROUTE: 5 checks, %d failures" % failures)
	quit(1 if failures else 0)
