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
## 覆盖接取、取信、交付、换装、隔离存档恢复及背包暂停闭环。
func run() -> void:
	ProjectSettings.set_setting("tactical/testing",true)
	lab=load("res://scenes/tactical_height.tscn").instantiate()
	lab.results_enabled=false
	root.add_child(lab)
	current_scene=lab
	while not is_instance_valid(lab.progression): await frames(1)
	var player=lab.player
	player.test_mode=true
	lab.guard.ai_enabled=false
	lab.archer.ai_enabled=false
	var quest=lab.objective
	var progress=lab.progression
	check(progress.inventory is ActorInventory,"reuses original inventory component")
	check(not quest.accepted,"starts with unaccepted camp quest")
	await frames(10)
	print("Start ",player.position," exit ",quest.exit_point)
	var key := InputEventKey.new()
	key.physical_keycode=KEY_E
	key.keycode=KEY_E
	key.pressed=true
	Input.parse_input_event(key)
	Input.flush_buffered_events()
	await frames(2)
	check(quest.accepted,"E accepts camp quest")
	player.position=quest.pickup_point+Vector3(0,0.03,0.7)
	player.velocity=Vector3.ZERO
	await frames(8)
	check(quest.interact(),"accepted quest allows collection")
	check(not progress.rewarded,"collecting alone grants no reward")
	player.position=quest.exit_point+Vector3.UP*0.03
	player.velocity=Vector3.ZERO
	await frames(8)
	check(quest.completed and quest.interact(),"return and hand-in grants reward")
	check(progress.level==2 and player.max_hp==105,"reward raises level and maximum health")
	check(progress.inventory.has_instance("camp_reward_cleaver"),"reward weapon goes into bag")
	check(not progress.grant_reward() and progress.inventory.bag_used()==1,"reward cannot be duplicated")
	var fast: float=lab.combat.attack_interval
	check(progress.equip("camp_reward_cleaver"),"equip reward at camp")
	check(lab.combat.melee_range>2.3 and lab.combat.attack_interval>fast and lab.combat.melee_damage==26,"heavy weapon changes reach speed and damage")
	check(progress.inventory.get_in_bag("camp_knife")!=null,"old weapon returns to bag")
	progress.persist=true
	progress.save_path="res://work/camp_progress_test.json"
	progress.changed()
	var saved=JSON.parse_string(FileAccess.get_file_as_string(progress.save_path))
	check(saved.rewarded and saved.inventory.equipment.weapon.definition_id=="great_cleaver","save captures reward and equipped item")
	var restored=load("res://scripts/progression/camp_progress.gd").new()
	restored.setup(lab.player, lab.combat)
	restored.save_path=progress.save_path
	lab.add_child(restored)
	check(restored.rewarded and restored.level==2 and restored.inventory.get_equipped(&"weapon").definition_id==&"great_cleaver","progress restores from separate save")
	restored.queue_free()
	progress.persist=false
	player.position=Vector3(4,0.03,6)
	await frames(8)
	check(progress.equip("camp_knife") and lab.combat.melee_range==1.45,"can equip knife away from camp")
	check(progress.equip("camp_reward_cleaver") and lab.combat.melee_range==2.45,"can swap back outside camp")
	var guard=lab.guard
	guard.position=Vector3(4,0.03,4.7)
	guard.state="chase"
	guard.attack_cycle=0
	guard.cooldown=0
	guard.facing=Vector3.BACK
	guard.ai_enabled=true
	var poses := {}
	var transforms := {}
	for i in 36:
		await frames(1)
		poses[guard.sprite.texture.get_instance_id()]=true
		transforms[str(guard.sword.transform)]=true
	check(guard.action_duration==0.32,"slash windup shortened")
	check(poses.size()>=6 and transforms.size()>=10,"attack uses multiple arm poses and continuous weapon motion")
	guard.ai_enabled=false
	guard.position=Vector3(4,0.03,6)
	player.position=Vector3(4,0.03,9)
	await frames(5)
	player.test_mode=false
	var cursor: Vector2=lab.camera.unproject_position(guard.position+Vector3.UP)+Vector2(18,0)
	var mouse := InputEventMouseMotion.new()
	mouse.position=cursor
	Input.parse_input_event(mouse)
	await frames(4)
	check(lab.combat.assist_marker.visible and lab.combat.assist_marker.global_position.distance_to(guard.global_position+Vector3.UP*0.04)<0.01,"assist ring follows enemy feet")
	player.test_mode=true
	player.position=quest.exit_point+Vector3.UP*0.03
	await frames(5)
	key=InputEventKey.new()
	key.pressed=true
	key.physical_keycode=KEY_I
	key.keycode=KEY_I
	Input.parse_input_event(key)
	Input.flush_buffered_events()
	await process_frame
	await process_frame
	check(progress.open and paused,"I opens bag and pauses gameplay")
	progress.view.content.get_child(progress.view.content.get_child_count()-1).get_child(0).pressed.emit()
	check(progress.inventory.get_equipped(&"weapon").definition_id==&"hunting_knife", "bag button swaps equipped weapon")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://work/camp_inventory.png")
	progress.toggle()
	check(not paused,"closing bag resumes gameplay")
	print("CAMP_LOOP: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
