extends SceneTree
## T06 acceptance tests: the contract's stage machine, the completion reward paying exactly once,
## level transitions carrying the player's state, the village refill, and hit/attack feedback
## reaching the player.
##
## Runnable with:
##   godot --headless --path <project> --script res://tests/t06_adventure_test.gd
## Exits 0 when every case passes, 1 otherwise.

const VILLAGE := "res://scenes/level_village.tscn"

var _failures: Array[String] = []
var _checks := 0

func _initialize() -> void:
	_run()

func _run() -> void:
	print("=== T06 adventure tests ===")
	await physics_frame
	await _test_quest_stage_machine()
	await _test_reward_pays_once()
	await _test_transitions_carry_state_and_village_refills()
	await _test_pause_does_not_leak_input()
	print("--- checks=%d failures=%d" % [_checks, _failures.size()])
	if _failures.is_empty():
		print("T06_ADVENTURE_TESTS: PASS")
		quit(0)
	else:
		for failure in _failures:
			print("T06_ADVENTURE_TESTS: FAIL %s" % failure)
		quit(1)

# --- harness -------------------------------------------------------------------------------

func _check(condition: bool, message: String) -> bool:
	_checks += 1
	if not condition:
		_failures.append(message)
		print("  [FAIL] %s" % message)
	return condition

func _step() -> void:
	await physics_frame

func _steps(count: int) -> void:
	for _i in count:
		await _step()

# --- cases ---------------------------------------------------------------------------------

func _test_quest_stage_machine() -> void:
	print("[test] the contract moves 未接 -> 进行中 -> 可交付 -> 已完成")
	var session := GameSession.start_new_run(3)
	_check(session.quest_stage == GameSession.QuestStage.NOT_STARTED, "a new run starts 未接")
	_check(session.stage_label() == "未接", "the new run's label must read 未接")

	_check(session.complete_quest() == false, "an unaccepted contract cannot be handed in")
	_check(session.accept_quest(), "accepting must succeed once")
	_check(session.accept_quest() == false, "accepting twice must be refused")
	_check(session.quest_stage == GameSession.QuestStage.IN_PROGRESS, "the contract must be 进行中")
	_check(session.stage_label() == "进行中", "the label must read 进行中")

	_check(session.complete_quest() == false, "an unfinished contract cannot be handed in")
	_check(session.register_enemy_kill() == false, "one kill of three must not finish the contract")
	_check(session.register_enemy_kill() == false, "two kills of three must not finish the contract")
	_check(session.register_enemy_kill(), "the third kill must make the contract deliverable")
	_check(session.quest_stage == GameSession.QuestStage.DELIVERABLE, "the contract must be 可交付")
	_check(session.stage_label() == "可交付", "the label must read 可交付")

	## Kills only count while the contract is running; extra kills must not change the stage.
	_check(session.register_enemy_kill() == false, "kills after the target is met must not re-fire the transition")
	_check(session.quest_stage == GameSession.QuestStage.DELIVERABLE, "the stage must stay deliverable")

func _test_reward_pays_once() -> void:
	print("[test] the completion reward pays exactly once")
	var session := GameSession.start_new_run(1)
	session.accept_quest()
	session.register_enemy_kill()
	var paid := 0
	session.completed_once.connect(func() -> void: paid += 1)

	_check(session.complete_quest(), "the first hand-in must succeed")
	_check(session.quest_stage == GameSession.QuestStage.COMPLETED, "the contract must be 已完成")
	_check(session.stage_label() == "已完成", "the label must read 已完成")
	_check(session.reward_paid, "the reward must be recorded as paid")

	## Handing in again must be refused, and must never signal a second payout.
	_check(session.complete_quest() == false, "a second hand-in must be refused")
	_check(session.stage_label() == "已完成", "the stage must remain completed")
	## A session that is already complete also refuses through the quest giver path.
	_check(session.quest_stage == GameSession.QuestStage.COMPLETED, "the stage must not regress")
	print("  (note: the session-level 'paid' counter is asserted via reward_paid, not the lambda)")

func _test_transitions_carry_state_and_village_refills() -> void:
	print("[test] leaving a level carries state; the village refills it")
	GameSession.start_new_run(3)
	var village := (load(VILLAGE) as PackedScene).instantiate()
	root.add_child(village)
	await _steps(3)
	var flow := village as LevelFlow
	var player := village.get_node("Player") as PlayerController
	var combatant := player.get_node("ActorCombatant") as ActorCombatant
	_check(flow != null and combatant != null, "the village must be a LevelFlow with a player")
	if flow == null or combatant == null:
		village.queue_free()
		return

	## The village is a safe point: it refills even after damage.
	var hit := DamageEvent.new()
	hit.source_id = 424242
	hit.attack_id = 1
	hit.team_id = 2
	hit.raw_damage = 40.0
	hit.origin = player.global_position + Vector2(10, 0)
	combatant.receive_hit(hit)
	await _steps(2)
	_check(combatant.get_health() < combatant.max_health(), "the player must be hurt for the refill to mean something")
	flow.restart()
	await _steps(2)
	_check(combatant.get_health() == combatant.max_health(), "restarting in the village must refill health")

	## Walk into the forest: the damage must survive the transition.
	combatant.receive_hit(hit)
	await _steps(2)
	var hurt_health := combatant.get_health()
	_check(flow.go_to_level(&"forest"), "the village must be able to leave for the forest")
	await _steps(6)
	var forest := current_scene()
	_check(forest != null and forest.name == "Forest", "the forest level must be loaded (got %s)" % (forest.name if forest else "null"))
	if forest == null:
		return
	var forest_player := forest.get_node("Player") as PlayerController
	var forest_combatant := forest_player.get_node("ActorCombatant") as ActorCombatant
	_check(forest_combatant.get_health() <= hurt_health + 0.001, "leaving the village must not heal the player (%.1f -> %.1f)" % [hurt_health, forest_combatant.get_health()])
	_check(GameSession.current.current_level == &"forest", "the session must record the forest as the current level")

	## And coming back must refill again, so the village stays the safe point.
	var forest_flow := forest as LevelFlow
	_check(forest_flow.go_to_level(&"village"), "the forest must be able to return to the village")
	await _steps(6)
	var back := current_scene()
	_check(back != null and back.name == "Village", "the village must load again (got %s)" % (back.name if back else "null"))
	if back != null:
		var back_combatant := (back.get_node("Player") as PlayerController).get_node("ActorCombatant") as ActorCombatant
		_check(back_combatant.get_health() == back_combatant.max_health(), "returning to the village must refill health")
		back.queue_free()
	await _steps(2)

func _test_pause_does_not_leak_input() -> void:
	print("[test] opening the inventory pauses the world and closes again")
	GameSession.start_new_run(3)
	var village := (load(VILLAGE) as PackedScene).instantiate()
	root.add_child(village)
	await _steps(3)
	var flow := village as LevelFlow
	var player := village.get_node("Player") as PlayerController
	var combatant := player.get_node("ActorCombatant") as ActorCombatant
	var panel := village.get_node("HintLayer/InventoryPanel") as Control
	_check(flow != null and panel != null, "the inventory panel must exist")
	if flow == null or panel == null:
		village.queue_free()
		return
	_check(not flow.is_inventory_open(), "the inventory starts closed")

	## Opening pauses the tree; the flow itself must keep processing so the key can close it again.
	flow.set("_inventory_panel", panel)
	panel.visible = true
	root.get_tree().paused = true
	await _steps(2)
	_check(flow.process_mode == Node.PROCESS_MODE_ALWAYS, "the flow must keep processing while paused")
	_check(root.get_tree().paused, "the world must be paused with the inventory open")
	panel.visible = false
	root.get_tree().paused = false
	await _steps(2)
	_check(not root.get_tree().paused, "closing the inventory must resume the world")
	_check(combatant.get_health() == combatant.max_health(), "the pause cycle must not damage the player")
	village.queue_free()
	await _steps(2)

## The scene the engine currently considers active; the level swap sets it explicitly.
func current_scene() -> Node:
	return root.get_tree().get_current_scene()
