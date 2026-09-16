extends SceneTree
var lab: Node3D
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func frames(n: int) -> void:
	for i in n: await physics_frame
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func run() -> void:
	lab=load("res://scenes/tactical_height.tscn").instantiate()
	lab.results_enabled=false
	ProjectSettings.set_setting("tactical/testing",true)
	root.add_child(lab)
	current_scene=lab
	lab.player.test_mode=true
	while not is_instance_valid(lab.archer): await frames(1)
	var guard=lab.guard
	var archer=lab.archer
	var player=lab.player
	guard.ai_enabled=false
	archer.ai_enabled=false
	player.position=Vector3(4,0.02,9)
	guard.position=Vector3(4,0.02,6)
	archer.position=Vector3(12,0.02,-8)
	await frames(8)
	var body: Vector3=guard.position+Vector3.UP
	var cursor: Vector2=lab.camera.unproject_position(body)+Vector2(18,0)
	var raw: Vector3=body+Vector3.RIGHT
	var corrected: Vector3=lab.combat.assisted_point(raw,cursor)
	check(corrected.distance_to(body)<0.01 and lab.combat.assist_target==guard,"small visible miss assists torso")
	check(lab.combat.assisted_point(raw,cursor+Vector2(50,0))==raw,"far cursor does not lock")
	var shift := InputEventKey.new()
	shift.physical_keycode=KEY_SHIFT
	shift.pressed=true
	Input.parse_input_event(shift)
	await frames(1)
	check(lab.combat.assisted_point(raw,cursor)==raw,"Shift disables assist")
	shift.pressed=false
	Input.parse_input_event(shift)
	await frames(1)
	guard.state="recover"
	player.test_mode=false
	var click := InputEventMouseButton.new()
	click.button_index=MOUSE_BUTTON_RIGHT
	click.position=cursor
	click.pressed=true
	Input.parse_input_event(click)
	await frames(24)
	check(guard.hp==40,"production right click assist lands a physical arrow")
	player.test_mode=true
	guard.hp=60
	guard.position=Vector3(-2,0.02,3)
	player.position=Vector3(0,0.02,3)
	await frames(5)
	body=guard.position+Vector3.UP
	cursor=lab.camera.unproject_position(body)+Vector2(18,0)
	check(lab.combat.assisted_point(raw,cursor)==raw,"stone blocks assist")
	guard.position=Vector3(9,0.02,5)
	player.position=Vector3(9,0.02,8)
	await frames(5)
	body=guard.position+Vector3.UP
	cursor=lab.camera.unproject_position(body)+Vector2(18,0)
	check(lab.combat.assisted_point(raw,cursor)==raw,"opaque penetrable cloth blocks assist")
	guard.hp=0
	check(lab.combat.assisted_point(raw,cursor)==raw,"dead enemies never assist")
	guard.hp=60
	player.position=Vector3(0,0.02,5)
	archer.position=Vector3(0,0.02,-7)
	archer.facing=Vector3.BACK
	archer.state="guard"
	await frames(5)
	check(not archer.can_see_target(),"flat archer has finite sight range")
	archer.position.y=2
	await frames(2)
	check(archer.can_see_target(),"elevated archer sees same distant lower player")
	check(archer.sight_range()<=17,"height sight bonus capped")
	guard.position=Vector3(0,0.02,3)
	guard.facing=Vector3.BACK
	guard.state="chase"
	guard.receive_strike(guard.position,Vector3.BACK,Vector3.FORWARD)
	check(guard.hp==54 and guard.state=="chase","frontal guard reduces damage without stun lock")
	guard.receive_strike(guard.position,Vector3.RIGHT,Vector3.LEFT)
	check(guard.hp==34 and guard.state=="recover","flank bypasses shield")
	guard.state="recover"
	guard.receive_strike(guard.position,Vector3.BACK,Vector3.FORWARD)
	check(guard.hp==14,"recovery window takes full frontal damage")
	guard.hp=60
	guard.state="chase"
	guard.attack_cycle=1
	guard.cooldown=0
	guard.position=Vector3(0,0.02,2.9)
	player.position=Vector3(0,0.02,5)
	guard.ai_enabled=true
	await frames(3)
	check(guard.thrust and guard.state=="windup" and guard.attack_time>0.35,"thrust retains a readable windup longer than slash")
	guard.ai_enabled=false
	guard.position=Vector3(-12,0,0)
	archer.position=Vector3(0,0.02,0)
	archer.facing=Vector3.BACK
	archer.state="chase"
	archer.cooldown=0
	archer.lost_time=0
	archer.ai_enabled=true
	player.hp=100
	player.invulnerable=0
	var shots:=0
	var was_windup:=false
	var long_recovery:=false
	for i in 175:
		await frames(1)
		if was_windup and archer.state in ["nock","recover"]: shots+=1
		was_windup=archer.state=="windup"
		if shots==2 and archer.state=="recover" and archer.attack_time>1.1: long_recovery=true; break
	check(shots==2 and long_recovery,"archer fires two telegraphed shots then exposes long recovery")
	if DisplayServer.get_name()!="headless":
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://work/combat_polish.png")
	print("COMBAT_POLISH: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
