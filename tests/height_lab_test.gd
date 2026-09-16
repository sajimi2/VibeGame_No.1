extends SceneTree
var checks := 0
var failures := 0
var lab: Node3D
var actor: CharacterBody3D

func _initialize() -> void: run.call_deferred()

func frames(count: int) -> void:
	for i in count: await physics_frame

func check(value: bool, text: String) -> void:
	checks += 1
	if not value: failures += 1
	print("%s %s" % ["PASS" if value else "FAIL", text])

func place(point: Vector3) -> void:
	actor.test_motion = Vector2.ZERO
	actor.global_position = point
	actor.velocity = Vector3.ZERO
	await frames(15)

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://work/height_%s.png" % label)

func run() -> void:
	lab = load("res://scenes/tactical_height.tscn").instantiate()
	lab.encounter_enabled = false
	ProjectSettings.set_setting("tactical/testing",true)
	root.add_child(lab)
	current_scene = lab
	actor = lab.player
	actor.test_mode = true
	await frames(15)
	check(actor.is_on_floor(), "spawn grounded")
	check(absf(actor.position.y) < 0.05, "flat ground elevation")
	check(lab.camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "orthographic camera")
	var angle: Vector3 = lab.camera.rotation
	await capture("overview")
	await place(Vector3(5, 0.05, 3))
	actor.test_motion = Vector2(0, -1)
	await frames(130)
	actor.test_motion = Vector2.ZERO
	await frames(5)
	print("platform position: ", actor.position)
	check(actor.position.y > 1.95 and actor.is_on_floor(), "walk up actual slope onto platform")
	check(lab.camera.rotation.is_equal_approx(angle), "camera follows without rotation")
	await capture("platform")
	actor.test_motion = Vector2(0, 1)
	await frames(130)
	actor.test_motion = Vector2.ZERO
	await frames(5)
	check(absf(actor.position.y) < 0.06 and actor.is_on_floor(), "walk down slope without hovering")
	await place(Vector3(-7, -0.9, -3))
	check(actor.position.y < -0.9, "depression has real negative elevation")
	actor.test_motion = Vector2(0, -1)
	await frames(110)
	actor.test_motion = Vector2.ZERO
	await frames(5)
	check(actor.position.y > -0.06 and actor.is_on_floor(), "exit depression by slope")
	await place(Vector3(-6, 0.1, 2.5))
	actor.test_motion = Vector2(0, -1)
	await frames(55)
	check(actor.position.z > 1.5, "low cover blocks walking")
	actor.test_motion = Vector2.ZERO
	actor.test_crouch = true
	await place(Vector3(-6, 0.1, 0.15))
	check(actor.crouched and actor.shape_node.shape.height < 1, "crouching changes collider")
	check(actor.occluded and actor.outline.visible, "hidden player receives outline")
	await capture("occlusion")
	await place(Vector3(-10, 0.1, 4))
	actor.test_motion = Vector2(0, 1)
	await frames(60)
	actor.test_motion = Vector2.ZERO
	await frames(2)
	check(actor.position.z > 5.8, "crouch under low beam")
	actor.test_crouch = false
	await frames(4)
	check(actor.crouched, "blocked standing does not penetrate ceiling")
	await capture("beam")
	actor.test_motion = Vector2(0, -1)
	await frames(75)
	actor.test_motion = Vector2.ZERO
	await frames(5)
	check(not actor.crouched, "stand after clearing beam")
	await place(Vector3(9, 0.1, 8))
	actor.test_motion = Vector2(0, -1)
	await frames(60)
	check(actor.position.z < 5, "cloth does not block locomotion")
	var hashes := {}
	for heading in 12:
		var image: Image = preload("res://scripts/tactical/directional_art.gd").texture(heading, 0, false).get_image()
		hashes[hash(image.get_data())] = true
	check(hashes.size() == 12, "twelve distinct direction textures")
	actor.reset_position()
	actor.test_motion = Vector2.ZERO
	await frames(10)
	check(Vector2(actor.position.x, actor.position.z).distance_to(Vector2(actor.spawn.x, actor.spawn.z)) < 0.1 and actor.is_on_floor(), "reset restores spawn")
	actor.test_mode = false
	Input.action_press("move_right")
	var before: Vector3 = actor.position
	await frames(10)
	Input.action_release("move_right")
	check(actor.position.x > before.x + 0.5, "production input action moves actor")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_C
	key.pressed = true
	Input.parse_input_event(key)
	await frames(3)
	check(actor.crouched, "physical C input crouches")
	key = InputEventKey.new()
	key.physical_keycode = KEY_C
	Input.parse_input_event(key)
	await frames(3)
	check(not actor.crouched, "releasing C stands in open space")
	print("HEIGHT_LAB: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
