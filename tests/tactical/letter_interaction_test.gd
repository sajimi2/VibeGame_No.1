extends SceneTree
var fails := 0
func _initialize() -> void: run.call_deferred()
func frames(n: int) -> void:
	for i in n: await physics_frame
func check(ok: bool,label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: fails+=1
## 检查越距提示、未先接任务时直接取信，以及随后正常返营领奖。
func run() -> void:
	ProjectSettings.set_setting("tactical/testing",true)
	var lab=load("res://tests/fixtures/legacy/tactical_height.tscn").instantiate()
	lab.results_enabled=false
	root.add_child(lab)
	current_scene=lab
	while not is_instance_valid(lab.progression): await frames(1)
	lab.player.test_mode=true
	lab.guard.ai_enabled=false
	lab.archer.ai_enabled=false
	var quest=lab.objective
	lab.player.position=Vector3(4,2.05,-3.9)
	await frames(8)
	check(not quest.interact() and quest.message_time>0,"out of range reports why")
	lab.player.position=quest.pickup_point+Vector3(0,0.03,0.7)
	lab.player.velocity=Vector3.ZERO
	await frames(10)
	check(not quest.accepted,"quest not accepted at camp")
	var key := InputEventKey.new()
	key.keycode=KEY_E
	key.physical_keycode=KEY_E
	key.pressed=true
	Input.parse_input_event(key)
	Input.flush_buffered_events()
	await frames(3)
	check(quest.carried and quest.accepted and not quest.relic.visible,"E collects letter without prior acceptance")
	check(not quest.interact() and quest.message_time>0,"repeat pickup gives return instruction")
	lab.player.position=quest.exit_point+Vector3.UP*0.03
	lab.player.velocity=Vector3.ZERO
	await frames(10)
	check(quest.interact() and quest.claimed and lab.progression.rewarded,"unaccepted pickup still allows normal reward hand-in")
	print("LETTER_INTERACTION: 5 checks, ",fails," failures")
	quit(1 if fails else 0)
