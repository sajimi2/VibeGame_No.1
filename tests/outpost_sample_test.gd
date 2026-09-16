extends SceneTree
var lab: Node3D
var failures := 0
var checks := 0
func _initialize() -> void: run.call_deferred()
func frames(count: int) -> void:
	for i in count: await physics_frame
func check(value: bool, label: String) -> void:
	checks += 1
	print(("PASS " if value else "FAIL ") + label)
	if not value: failures += 1
func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://work/outpost_" + label + ".png")
func run() -> void:
	lab = load("res://scenes/tactical_height.tscn").instantiate()
	lab.encounter_enabled = false
	ProjectSettings.set_setting("tactical/testing",true)
	root.add_child(lab)
	current_scene = lab
	var actor: CharacterBody3D = lab.player
	actor.test_mode = true
	await frames(15)
	await capture("entrance")
	actor.position = Vector3(-8,0.2,13.5)
	actor.velocity = Vector3.ZERO
	await frames(15)
	actor.test_motion = Vector2(0,-1)
	await frames(42)
	actor.test_motion = Vector2.ZERO
	await frames(6)
	check(actor.is_on_floor() and absf(actor.position.y-1.2)<0.04,"tower ramp reaches timber platform")
	await capture("tower")
	actor.test_motion = Vector2(0,1)
	await frames(42)
	actor.test_motion = Vector2.ZERO
	await frames(6)
	check(actor.is_on_floor() and actor.position.y<0.35,"tower ramp allows descent")
	actor.position = Vector3(-4,0.1,9)
	actor.velocity = Vector3.ZERO
	await frames(15)
	var previous: Vector2 = lab.camera.unproject_position(Vector3(-8,1.2,10))
	var max_error := 0.0
	actor.test_motion = Vector2(1,0)
	for i in 30:
		await frames(1)
		var point: Vector2 = lab.camera.unproject_position(Vector3(-8,1.2,10))
		var movement := point-previous
		max_error = maxf(max_error,(movement-movement.round()).length())
		previous = point
	actor.test_motion = Vector2.ZERO
	check(max_error<0.02,"static edges move in whole render pixels")
	check(lab.camera.projection == Camera3D.PROJECTION_ORTHOGONAL,"fixed orthographic projection")
	check(root.content_scale_size == Vector2i(1280,720),"higher native render resolution")
	var ray := PhysicsRayQueryParameters3D.create(Vector3(-8,3,11.3),Vector3(-8,0,11.3),1)
	var hit := lab.get_world_3d().direct_space_state.intersect_ray(ray)
	check(not hit.is_empty() and absf(hit.position.y-1.2)<0.04,"visible platform and floor collider agree")
	actor.position = Vector3(4,2.1,-6)
	actor.velocity = Vector3.ZERO
	await frames(15)
	await capture("terrain")
	print("OUTPOST_SAMPLE: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
