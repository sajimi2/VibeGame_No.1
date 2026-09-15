extends SceneTree
## T05 acceptance tests: level thresholds, multi-level rewards, one event per level, the level cap,
## point spending atomicity, no free healing, and one reward per death.
##
## Runnable with:
##   godot --headless --path <project> --script res://tests/t05_progression_test.gd
## Exits 0 when every case passes, 1 otherwise.

const ARENA_SCENE := "res://scenes/arena.tscn"

var _failures: Array[String] = []
var _checks := 0
var _levels_seen: Array[int] = []

func _initialize() -> void:
	_run()

func _run() -> void:
	print("=== T05 progression tests ===")
	await physics_frame
	await _test_thresholds_and_events()
	await _test_multi_level_keeps_excess()
	await _test_cap_does_not_loop()
	await _test_spend_point_is_atomic()
	await _test_spending_does_not_heal()
	await _test_death_grants_experience_once()
	print("--- checks=%d failures=%d" % [_checks, _failures.size()])
	if _failures.is_empty():
		print("T05_PROGRESSION_TESTS: PASS")
		quit(0)
	else:
		for failure in _failures:
			print("T05_PROGRESSION_TESTS: FAIL %s" % failure)
		quit(1)

# --- harness -------------------------------------------------------------------------------

func _check(condition: bool, message: String) -> bool:
	_checks += 1
	if not condition:
		_failures.append(message)
		print("  [FAIL] %s" % message)
	return condition

func _check_eq(actual: int, expected: int, message: String) -> bool:
	return _check(actual == expected, "%s (actual=%d expected=%d)" % [message, actual, expected])

func _step() -> void:
	await physics_frame

func _steps(count: int) -> void:
	for _i in count:
		await _step()

func _new_progression() -> ActorProgression:
	var progression := ActorProgression.new()
	root.add_child(progression)
	return progression

func _on_leveled_up(new_level: int) -> void:
	_levels_seen.append(new_level)

# --- cases ---------------------------------------------------------------------------------

func _test_thresholds_and_events() -> void:
	print("[test] level 1 needs 50 experience and each level fires once")
	var progression := _new_progression()
	await _step()
	_check_eq(progression.get_level(), 1, "a fresh run starts at level 1")
	_check_eq(progression.xp_to_next(), 50, "level 1 must require 50 experience")
	_check_eq(progression.get_unspent_points(), 0, "a fresh run starts with no points")

	_levels_seen.clear()
	progression.leveled_up.connect(_on_leveled_up)
	progression.grant_experience(0)
	_check_eq(progression.get_xp_in_level(), 0, "zero experience must be ignored")
	progression.grant_experience(-10)
	_check_eq(progression.get_xp_in_level(), 0, "negative experience must be ignored")

	progression.grant_experience(49)
	_check_eq(progression.get_level(), 1, "49 experience must not level up")
	_check_eq(progression.get_xp_in_level(), 49, "experience below the threshold must accumulate")
	_check(_levels_seen.is_empty(), "no level event before the threshold")

	progression.grant_experience(1)
	_check_eq(progression.get_level(), 2, "the 50th experience must reach level 2")
	_check_eq(progression.get_xp_in_level(), 0, "exactly reaching the threshold must leave no excess")
	_check_eq(_levels_seen.size(), 1, "one level must fire exactly one event (got %d)" % _levels_seen.size())
	_check_eq(progression.get_unspent_points(), 1, "each level must grant one point")
	_check_eq(progression.xp_to_next(), 100, "level 2 must require 100 experience")
	progression.queue_free()
	await _step()

func _test_multi_level_keeps_excess() -> void:
	print("[test] one reward crossing several levels keeps the excess")
	var progression := _new_progression()
	await _step()
	_levels_seen.clear()
	progression.leveled_up.connect(_on_leveled_up)
	## 50 (to level 2) + 100 (to level 3) = 150, so 170 must reach level 3 with 20 left over.
	progression.grant_experience(170)
	_check_eq(progression.get_level(), 3, "170 experience must reach level 3")
	_check_eq(progression.get_xp_in_level(), 20, "the excess 20 must be preserved, not discarded")
	_check_eq(_levels_seen.size(), 2, "crossing two levels must fire two events (got %d)" % _levels_seen.size())
	_check_eq(_levels_seen[0], 2, "the first crossed level must be reported first")
	_check_eq(_levels_seen[1], 3, "the second crossed level must be reported second")
	_check_eq(progression.get_unspent_points(), 2, "two levels must grant two points")
	progression.queue_free()
	await _step()

func _test_cap_does_not_loop() -> void:
	print("[test] the level cap stops progression without looping")
	var progression := _new_progression()
	await _step()
	progression.grant_experience(100000)
	_check_eq(progression.get_level(), ActorProgression.MAX_LEVEL, "experience must not exceed the cap (got %d)" % progression.get_level())
	_check_eq(progression.xp_to_next(), 0, "at the cap the next requirement must be zero")
	_check_eq(progression.get_xp_in_level(), 0, "at the cap experience must be zeroed")
	var points_at_cap := progression.get_unspent_points()

	## Further experience must be ignored, not loop.
	for _i in 5:
		progression.grant_experience(500)
	_check_eq(progression.get_level(), ActorProgression.MAX_LEVEL, "further experience must not raise the level")
	_check_eq(progression.get_unspent_points(), points_at_cap, "further experience must not grant more points")
	progression.queue_free()
	await _step()

func _test_spend_point_is_atomic() -> void:
	print("[test] spending points is atomic and refuses invalid requests")
	var progression := _new_progression()
	await _step()

	## No points yet: every request must be refused with no side effects.
	var before := progression.get_snapshot()
	_check(progression.spend_point(ProgressionPort.Attribute.MAX_HEALTH) == false, "a point cannot be spent when none are available")
	_check(progression.spend_point(ProgressionPort.Attribute.MAX_STAMINA) == false, "a dodge-style second request must also be refused")
	_check(JSON.stringify(before) == JSON.stringify(progression.get_snapshot()), "a refused spend must change nothing")

	## Earn two points and spend one of each.
	progression.grant_experience(150)
	_check(progression.spend_point(ProgressionPort.Attribute.MAX_HEALTH), "the first point must be spendable")
	_check(progression.spend_point(ProgressionPort.Attribute.MAX_STAMINA), "the second point must be spendable")
	_check_eq(progression.get_unspent_points(), 0, "both points must be consumed")
	_check(progression.spend_point(ProgressionPort.Attribute.MAX_HEALTH) == false, "a third request must be refused")
	_check_eq(progression.bonus_max_health(), 5.0, "one point must add 5 maximum health")
	_check_eq(progression.bonus_max_stamina(), 5.0, "one point must add 5 maximum stamina")

	## An unknown attribute must be refused without consuming a point.
	progression.grant_experience(100)
	var points_before := progression.get_unspent_points()
	_check(progression.spend_point(99 as ProgressionPort.Attribute) == false, "an unknown attribute must be refused")
	_check_eq(progression.get_unspent_points(), points_before, "a refused attribute must not consume a point")
	progression.queue_free()
	await _step()

func _test_spending_does_not_heal() -> void:
	print("[test] raising a maximum never heals the player")
	var arena := (load(ARENA_SCENE) as PackedScene).instantiate()
	root.add_child(arena)
	await _steps(3)
	var player := arena.get_node("Player") as PlayerController
	var combatant := player.get_node("ActorCombatant") as ActorCombatant
	var progression := player.get_node("ActorProgression") as ActorProgression
	_check(combatant != null and progression != null, "the player must have a combatant and a progression")
	if combatant == null or progression == null:
		arena.queue_free()
		return

	## Take damage first, then level up and spend a point.
	var event := DamageEvent.new()
	event.source_id = 555001
	event.attack_id = 1
	event.team_id = 2
	event.raw_damage = 40.0
	event.origin = player.global_position + Vector2(10, 0)
	combatant.receive_hit(event)
	await _steps(2)
	var health_after_damage := combatant.get_health()
	var max_before := combatant.max_health()
	_check(health_after_damage < max_before, "the player must have taken damage for this case to mean anything")

	progression.grant_experience(150)
	_check(progression.get_unspent_points() > 0, "levelling must grant a point")
	_check(progression.spend_point(ProgressionPort.Attribute.MAX_HEALTH), "the point must be spendable")
	await _steps(2)
	_check(combatant.max_health() > max_before, "spending on health must raise the maximum")
	_check(combatant.get_health() <= health_after_damage + 0.001, "spending a point must not heal (health %.1f -> %.1f)" % [health_after_damage, combatant.get_health()])

	## Stamina has the same rule.
	var stamina_combatant := player.get_node("ActorCombatant") as ActorCombatant
	stamina_combatant.try_spend_stamina(50.0)
	var stamina_after = stamina_combatant.get_stamina()
	var stamina_max_before := stamina_combatant.max_stamina()
	progression.grant_experience(100)
	progression.spend_point(ProgressionPort.Attribute.MAX_STAMINA)
	await _steps(2)
	_check(stamina_combatant.max_stamina() > stamina_max_before, "spending on stamina must raise the maximum")
	_check(stamina_combatant.get_stamina() <= stamina_after + 0.001, "spending a point must not refill stamina (%.1f -> %.1f)" % [stamina_after, stamina_combatant.get_stamina()])
	arena.queue_free()
	await _steps(2)

func _test_death_grants_experience_once() -> void:
	print("[test] each enemy death grants its reward exactly once")
	var arena := (load(ARENA_SCENE) as PackedScene).instantiate()
	root.add_child(arena)
	await _steps(2)
	var player := arena.get_node("Player") as PlayerController
	var progression := player.get_node("ActorProgression") as ActorProgression
	var encounters := arena.get_node("Encounters") as EncounterManager
	var player_combatant := player.get_node("ActorCombatant") as ActorCombatant
	if progression == null or encounters == null:
		_check(false, "the arena must provide progression and encounters")
		arena.queue_free()
		return

	## Walk into the pack encounter and kill one enemy outright.
	player.global_position = encounters.activity_center(&"pack")
	await _steps(6)
	var enemy := encounters.all_enemy_nodes()[0] if not encounters.all_enemy_nodes().is_empty() else null
	_check(enemy != null, "an enemy must exist to kill")
	if enemy == null:
		arena.queue_free()
		return
	var reward := int(enemy.call("get_experience_reward"))
	var xp_before := progression.get_xp_in_level()
	var kill := DamageEvent.new()
	kill.source_id = player_combatant.get_instance_id()
	kill.attack_id = 900
	kill.team_id = 1
	kill.raw_damage = 500.0
	kill.origin = enemy.global_position
	var target := enemy.get_node("ActorCombatant") as ActorCombatant
	target.receive_hit(kill)
	await _steps(4)
	_check_eq(progression.get_xp_in_level(), xp_before + reward, "one death must grant exactly the enemy's reward")

	## Killing the same corpse again is impossible, but a second hit on a dead target must not pay.
	target.receive_hit(kill)
	await _steps(4)
	_check_eq(progression.get_xp_in_level(), xp_before + reward, "further hits on a dead enemy must grant nothing")
	arena.queue_free()
	await _steps(2)
