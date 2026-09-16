extends SceneTree
var lab: Node3D
var player: CharacterBody3D
var archer: CharacterBody3D
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func frames(n: int) -> void:
	for i in n: await physics_frame
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func place(at: Vector3) -> void:
	player.position=at
	player.velocity=Vector3.ZERO
	player.test_motion=Vector2.ZERO
	player.test_crouch=false
	player.jumped=false
	player.hp=100
	player.invulnerable=0
	await frames(15)
func capture(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://work/mission_"+label+".png")
func run() -> void:
	lab=load("res://scenes/tactical_height.tscn").instantiate()
	lab.results_enabled=false
	ProjectSettings.set_setting("tactical/testing",true)
	root.add_child(lab)
	current_scene=lab
	player=lab.player
	player.test_mode=true
	while not is_instance_valid(lab.archer): await frames(1)
	archer=lab.archer
	lab.objective.accepted=true
	lab.guard.ai_enabled=false
	archer.ai_enabled=false
	check(is_instance_valid(lab.objective) and archer.ranged,"mission has two enemy roles and objective")
	await place(Vector3(0,0.1,9))
	check(player.request_jump(),"grounded jump starts")
	check(not player.request_jump(),"same-frame double jump rejected")
	var peak := 0.0
	for i in 32:
		await frames(1)
		peak=maxf(peak,player.position.y)
		if i==10: check(not player.request_jump(),"airborne double jump rejected")
	check(peak>0.55 and peak<0.8,"short jump height bounded")
	await frames(12)
	check(player.is_on_floor() and not player.jumped,"lands and clears airborne state")
	var key := InputEventKey.new()
	key.physical_keycode=KEY_SPACE
	key.pressed=true
	Input.parse_input_event(key)
	await frames(7)
	check(player.position.y>0.25,"physical Space input jumps")
	check(absf(player.shadow.patch.global_position.y)<0.08,"jump shadow stays on ground")
	var before_hp: int=player.hp
	player.receive_damage(10,Vector3.RIGHT)
	check(player.hp==before_hp-10,"jump grants no invulnerability")
	await frames(40)
	player.test_crouch=true
	await frames(3)
	check(not player.request_jump(),"crouched jump rejected")
	player.test_crouch=false
	await frames(3)
	player.hp=0
	check(not player.request_jump(),"dead jump rejected")
	await place(Vector3(-4,0.02,3.2))
	player.test_motion=Vector2(0,-1)
	await frames(9)
	player.request_jump()
	await frames(26)
	check(player.position.z<1.8,"jump crosses low broken fence")
	player.test_motion=Vector2.ZERO
	await frames(15)
	await place(Vector3(0,0.02,-7))
	player.test_motion=Vector2(1,0)
	player.request_jump()
	await frames(40)
	check(player.position.y<0.2 and player.position.x<1.0,"jump cannot climb two metre cliff")
	await place(Vector3(5,1.4,-2))
	check(player.request_jump(),"jump starts on slope")
	await frames(45)
	check(player.is_on_floor() and player.position.y>1.2,"lands on slope")
	await place(Vector3(0,0.02,8))
	lab.box("JumpCeiling",Vector3(0,2.02,8),Vector3(2,0.2,2),"wood")
	await frames(3)
	player.request_jump()
	var roof_peak:=0.0
	for i in 30:
		await frames(1)
		roof_peak=maxf(roof_peak,player.position.y)
	check(roof_peak<0.31,"head collision prevents jumping through ceiling")
	await place(Vector3(0,0.02,5))
	archer.position=Vector3(0,0.02,0)
	archer.velocity=Vector3.ZERO
	archer.locked_target=player.position+Vector3.UP
	archer.perform_attack()
	await frames(38)
	check(player.hp==85,"enemy arrow actually damages player")
	await place(Vector3(-2,0.02,3))
	archer.position=Vector3(0,0.02,3)
	archer.locked_target=player.position+Vector3.UP
	archer.perform_attack()
	await frames(25)
	check(player.hp==100,"enemy arrow stops at stone wall")
	await place(Vector3(0,0.02,6))
	archer.position=Vector3(0,0.02,0)
	archer.facing=Vector3.BACK
	archer.state="chase"
	archer.cooldown=0
	archer.ai_enabled=true
	await frames(3)
	check(archer.state=="windup" and archer.attack_time>0.7,"archer telegraphs aim before firing")
	var locked: Vector3=archer.locked_target
	player.position.x=2
	await frames(8)
	check(archer.locked_target==locked,"aim remains committed during windup")
	archer.ai_enabled=false
	await place(Vector3(0,0.02,1.5))
	archer.position=Vector3(0,0.02,0)
	archer.state="chase"
	archer.last_seen=player.position
	archer.lost_time=0
	archer.facing=Vector3.BACK
	archer.retreat_timer=0
	archer.ai_enabled=true
	await frames(40)
	check(archer.position.distance_to(player.position)>2,"archer retreats when approached")
	archer.ai_enabled=false
	archer.receive_strike(archer.position,Vector3.RIGHT,Vector3.RIGHT)
	check(archer.hp==20 and archer.health_bar.displayed==21,"damage updates half health bar")
	check(not archer.marker.text.contains("40"),"enemy marker no longer displays numeric health")
	check(lab.combat.weapon.get_child_count()>5 and lab.combat.bow.get_child_count()>5,"blade hilt and bow limbs have geometry")
	check(not lab.objective.interact(),"cannot collect objective remotely")
	await place(lab.objective.pickup_point+Vector3(0,0.02,0.7))
	check(lab.objective.interact(),"collect objective nearby")
	check(not lab.objective.interact(),"objective collected only once")
	await place(lab.objective.exit_point+Vector3.UP*0.05)
	await frames(2)
	check(lab.objective.completed and lab.guard.hp>0,"extraction succeeds without clearing enemies")
	await capture("complete")
	player.position=Vector3(4,2.03,-5)
	player.velocity=Vector3.ZERO
	archer.position=Vector3(6,2.03,-5.2)
	archer.state="windup"
	archer.attack_time=0.9
	archer.facing=Vector3.LEFT
	archer.ai_enabled=true
	await frames(3)
	await capture("weapons")
	var restart := InputEventKey.new()
	restart.physical_keycode=KEY_R
	restart.pressed=true
	Input.parse_input_event(restart)
	await frames(40)
	check(is_instance_valid(current_scene.archer) and not current_scene.objective.carried and not current_scene.objective.completed and current_scene.player.hp==100,"R resets both enemies and objective")
	print("MISSION: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
