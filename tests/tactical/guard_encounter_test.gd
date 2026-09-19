extends SceneTree
var lab: Node3D
var guard: CharacterBody3D
var player: CharacterBody3D
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func frames(n: int) -> void:
	for i in n: await physics_frame
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1
	print(("PASS " if value else "FAIL ")+label)
func arrange(enemy_pos: Vector3, player_pos: Vector3, direction: Vector3) -> void:
	guard.ai_enabled = false
	guard.position = enemy_pos
	guard.velocity = Vector3.ZERO
	guard.facing = direction
	player.position = player_pos
	player.velocity = Vector3.ZERO
	player.hp = 100
	player.invulnerable = 0
	player.test_crouch = false
	await frames(4)
func capture(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://work/guard_"+label+".png")
## 布置敌我位置，验证守卫与弓手的感知、攻击、受击及音效。
func run() -> void:
	lab = load("res://scenes/tactical_height.tscn").instantiate()
	lab.mission_enabled=false
	ProjectSettings.set_setting("tactical/testing",true)
	root.add_child(lab)
	current_scene = lab
	player = lab.player
	player.test_mode = true
	for i in 120:
		await frames(1)
		if is_instance_valid(lab.guard): break
	check(is_instance_valid(lab.guard),"encounter starts with one guard")
	if not is_instance_valid(lab.guard): quit(1); return
	guard = lab.guard
	guard.ai_enabled = false
	check(lab.routes.graph.get_point_count()>200,"walkable terrain graph built")
	await arrange(Vector3(-6,0,0),Vector3(-6,0.05,3),Vector3.BACK)
	check(guard.can_see_target(),"standing player visible above low wall")
	player.test_crouch = true
	await frames(3)
	check(not guard.can_see_target(),"crouched player hidden by low wall")
	await arrange(Vector3(-3,0,3),Vector3(1,0.05,3),Vector3.RIGHT)
	check(not guard.can_see_target(),"stone wall blocks sight")
	await arrange(Vector3(-6,0,4),Vector3(-4.6,0.05,4),Vector3.LEFT)
	check(not guard.can_see_target(),"rear target outside field of view")
	await arrange(Vector3(9,0,7.5),Vector3(9,0.05,5),Vector3.FORWARD)
	check(not guard.can_see_target(),"cloth blocks sight")
	var cloth := lab.get_node("ClothScreen")
	for i in 3: preload("res://scripts/combat/space_trace.gd").apply_cloth(cloth)
	await frames(3)
	check(guard.can_see_target(),"torn cloth restores sight")
	await arrange(Vector3(2,0,-0.5),Vector3(2,0.05,4),Vector3.BACK)
	guard.state="guard"
	guard.ai_enabled=true
	await frames(4)
	check(guard.state=="chase","visible player triggers chase")
	var remembered: Vector3 = guard.last_seen
	player.position=Vector3(-8,0.05,3)
	await frames(50)
	check(not guard.target_visible and guard.state=="investigate","losing sight enters investigation")
	check(guard.last_seen.distance_to(remembered)<0.03,"hidden player does not update remembered position")
	guard.ai_enabled=false
	var route: PackedVector3Array = lab.routes.path(Vector3(-3,0,3),Vector3(1,0,3))
	var detour := false
	for point in route:
		if point.z<0.4 or point.z>5.6: detour=true
	check(route.size()>3 and detour,"route detours around stone wall")
	await arrange(Vector3(5,0.05,2.5),Vector3(6,2.05,-7),Vector3.FORWARD)
	check(guard.can_see_target(),"highland target is inside sight range before pursuit")
	guard.state="chase"
	guard.repath=0
	guard.ai_enabled=true
	for i in 420:
		await frames(1)
		if guard.position.y>1.99 and guard.position.z<-4.4: break
	print("Highland guard: ",guard.position," state=",guard.state," last=",guard.last_seen," route=",guard.route.size())
	check(guard.position.y>1.99 and guard.position.z<-4.4 and guard.is_on_floor(),"guard physically follows ramp to highland")
	await capture("highland")
	await arrange(Vector3(-1.8,0,3),Vector3(-0.2,0.05,3),Vector3.RIGHT)
	guard.locked_direction=Vector3.RIGHT
	guard.perform_attack()
	check(player.hp==100,"melee cannot damage through stone wall")
	await arrange(Vector3(-6,0,4),Vector3(-4.6,0.05,4),Vector3.RIGHT)
	guard.locked_direction=Vector3.RIGHT
	guard.perform_attack()
	check(player.hp==80,"unblocked melee damages player")
	guard.perform_attack()
	check(player.hp==80,"brief invulnerability prevents duplicate damage")
	await arrange(Vector3(-6,0,4),Vector3(-6,0.05,6.5),Vector3.RIGHT)
	guard.state="windup"
	guard.locked_direction=Vector3.RIGHT
	guard.attack_time=0.2
	guard.ai_enabled=true
	await frames(20)
	check(player.hp==100,"moving away evades committed swing")
	guard.ai_enabled=false
	guard.hp=60
	guard.receive_strike(guard.position+Vector3.UP,Vector3.LEFT,Vector3.RIGHT)
	check(guard.hp==40,"guard takes body damage")
	guard.receive_strike(guard.position+Vector3.UP,Vector3.UP,Vector3.DOWN)
	check(guard.hp==10,"descending top strike deals increased damage")
	guard.receive_strike(guard.position,Vector3.LEFT,Vector3.RIGHT)
	check(guard.hp==0 and guard.collision_layer==0 and guard.state=="dead","dead guard stops blocking and fighting")
	check(lab.effects.streams.size()==6 and lab.effects.streams.hit.data.size()>1000,"six generated sound effects contain audio samples")
	guard.state="search"
	guard.hp=60
	guard.collision_layer=1|16
	guard.collision_mask=1|2
	guard.position=guard.home
	guard.velocity=Vector3.ZERO
	guard.search_time=0.12
	player.position=Vector3(-12,0.1,12)
	guard.ai_enabled=true
	await frames(20)
	check(guard.state in ["return","guard"],"search expires and guard gives up")
	guard.ai_enabled=false
	var audio_capture := AudioEffectCapture.new()
	AudioServer.add_bus_effect(0,audio_capture)
	lab.effects.sound("hit",player.position+Vector3.UP)
	await frames(30)
	var buffer := audio_capture.get_buffer(audio_capture.get_frames_available())
	var peak := 0.0
	for sample in buffer: peak=maxf(peak,sample.length())
	check(peak>0.0001,"sound reaches audio output with listener at player")
	AudioServer.remove_bus_effect(0,AudioServer.get_bus_effect_count(0)-1)
	await frames(20)
	var poses := {}
	var sheet := Image.create(96*5,96,false,Image.FORMAT_RGBA8)
	var samples := [["idle",0],["heavy_swing",16],["heavy_swing",24],["hurt",4],["bow_draw",8]]
	for pose in 5:
		var art: Image = preload("res://scripts/art/baked_character_source.gd").new().sample(samples[pose][0],2,samples[pose][1],{"part":"full"}).texture.get_image()
		poses[hash(art.get_data())] = true
		sheet.blit_rect(art,Rect2i(0,0,96,96),Vector2i(pose*96,0))
	sheet.save_png("res://work/guard_action_poses.png")
	check(poses.size()==5,"当前待机、蓄力、挥出、受击和拉弓使用不同实体姿态")
	player.hp=0
	player.test_motion=Vector2.RIGHT
	var dead_position: Vector3 = player.position
	await frames(8)
	check(Vector2(player.position.x-dead_position.x,player.position.z-dead_position.z).length()<0.01,"dead player cannot keep moving")
	lab.combat.cooldown=0
	check(not lab.combat.attack(player.position+Vector3.RIGHT),"dead player cannot attack")
	var old_guard: WeakRef = weakref(guard)
	var key := InputEventKey.new()
	key.physical_keycode=KEY_R
	key.pressed=true
	Input.parse_input_event(key)
	await frames(30)
	var restarted := current_scene
	check(old_guard.get_ref()==null and restarted.player.hp==100 and is_instance_valid(restarted.guard) and restarted.guard.hp==60,"R rebuilds encounter and restores both actors")
	print("GUARD_ENCOUNTER: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
