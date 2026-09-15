extends SceneTree
## T02 combat acceptance tests. Drives the real scenes and the real ports: state machines, the
## physics-space hitbox, stamina, blocking, dodge windows, death and retry.
##
## Runnable with:
##   godot --headless --path <project> --script res://tests/t02_combat_test.gd
## Exits 0 when every case passes, 1 otherwise, so CI-style callers can rely on the code.

const PLAYER_SCENE := "res://scenes/player.tscn"
const BANDIT_SCENE := "res://scenes/bandit.tscn"
const DUMMY_SCENE := "res://scenes/training_dummy.tscn"
const STEP_SECONDS := 1.0 / 60.0
## Team ids from data/player_tuning.tres and data/bandit_tuning.tres.
const PLAYER_TEAM := 1
const ENEMY_TEAM := 2

var _failures: Array[String] = []
var _checks := 0
var _error_id := 900001
## Signal-counter helper: a lambda would capture its locals by value and never report back.
var _death_count := 0

func _on_died_counted(_source_id: int) -> void:
	_death_count += 1

func _initialize() -> void:
	_run()

func _run() -> void:
	print("=== T02 combat tests ===")
	await physics_frame
	await _test_stamina_is_atomic()
	await _test_attack_phases_and_locking()
	await _test_hit_lands_once_per_swing()
	await _test_active_window_only()
	await _test_dodge_invulnerability_window()
	await _test_block_front_and_back()
	await _test_guard_break()
	await _test_death_is_exactly_once()
	await _test_bandit_approaches_and_damages_player()
	await _test_retry_restores_both_sides()
	print("--- checks=%d failures=%d" % [_checks, _failures.size()])
	if _failures.is_empty():
		print("T02_COMBAT_TESTS: PASS")
		quit(0)
	else:
		for failure in _failures:
			print("T02_COMBAT_TESTS: FAIL %s" % failure)
		quit(1)

# --- harness -------------------------------------------------------------------------------

func _check(condition: bool, message: String) -> bool:
	_checks += 1
	if not condition:
		_failures.append(message)
		print("  [FAIL] %s" % message)
	return condition

func _check_close(actual: float, expected: float, tolerance: float, message: String) -> bool:
	return _check(absf(actual - expected) <= tolerance, "%s (actual=%.4f expected=%.4f tol=%.4f)" % [message, actual, expected, tolerance])

func _step() -> void:
	await physics_frame

func _steps(count: int) -> void:
	for _i in count:
		await _step()

## Steps until the port reaches `target` or the budget runs out; returns true when it arrived.
func _advance_until(port: ActorCommandPort, target: ActorCommandPort.State, max_steps := 240) -> bool:
	for _i in max_steps:
		if port.get_state() == target:
			return true
		await _step()
	return port.get_state() == target

func _spawn(scene_path: String, position: Vector2, parent: Node) -> Node2D:
	var actor := (load(scene_path) as PackedScene).instantiate() as Node2D
	parent.add_child(actor)
	actor.global_position = position
	await _step()
	return actor

func _port(actor: Node) -> ActorCommandPort:
	return actor.get_node("ActorActionPort") as ActorCommandPort

func _combatant(actor: Node) -> ActorCombatant:
	return actor.get_node("ActorCombatant") as ActorCombatant

func _new_root_group() -> Node2D:
	var group := Node2D.new()
	root.add_child(group)
	return group

func _free_group(group: Node) -> void:
	group.queue_free()
	await physics_frame

## A damage event addressed to `target` from a synthetic enemy attacker. The team id must be
## hostile to the target: a same-team event is friendly fire and is ignored by design.
func _event(raw_damage: float, origin: Vector2, stamina_damage := 16.0, attack_id := 0) -> DamageEvent:
	return _event_from_team(ENEMY_TEAM, raw_damage, origin, stamina_damage, attack_id)

func _event_from_team(team_id: int, raw_damage: float, origin: Vector2, stamina_damage := 16.0, attack_id := 0) -> DamageEvent:
	var event := DamageEvent.new()
	event.source_id = _error_id
	event.attack_id = attack_id
	event.team_id = team_id
	event.raw_damage = raw_damage
	event.stamina_damage = stamina_damage
	event.origin = origin
	return event

# --- tests ---------------------------------------------------------------------------------

func _test_stamina_is_atomic() -> void:
	print("[test] stamina spending is atomic and attacks are refused without side effects")
	var group := _new_root_group()
	var player := await _spawn(PLAYER_SCENE, Vector2(200, 200), group)
	var port := _port(player)
	var combatant := _combatant(player)
	var light_cost: float = _combatant(player).tuning.light_attack.stamina_cost

	_check(combatant.try_spend_stamina(0.0) == false, "spending zero must be refused")
	_check(combatant.try_spend_stamina(-5.0) == false, "spending a negative amount must be refused")
	var before := combatant.get_stamina()
	_check_close(before, combatant.max_stamina(), 0.001, "no spend must leave stamina untouched")

	## Drain to just under a light attack's cost, then a request must be refused with no residue.
	## The cost is read from the spec instead of hardcoded: what the player swings is now data (an
	## equipped weapon's spec, or the unarmed fallback), and this check is about atomicity rather
	## than about one particular number.
	while combatant.get_stamina() >= light_cost:
		if not combatant.try_spend_stamina(light_cost):
			break
	_check(combatant.get_stamina() < light_cost, "stamina drained below one light attack (%.1f < %.1f)" % [combatant.get_stamina(), light_cost])
	await _step()
	var stamina_before := combatant.get_stamina()
	var state_before := port.get_state()
	var attack_id_before := port.get_attack_id()
	_check(port.request_action(ActorCommandPort.Action.LIGHT_ATTACK) == false, "an attack must be refused when stamina is insufficient")
	_check_close(combatant.get_stamina(), stamina_before, 0.001, "a refused attack must not change stamina")
	_check(port.get_state() == state_before, "a refused attack must not change state")
	_check(port.get_attack_id() == attack_id_before, "a refused attack must not consume an attack id")

	## And a dodge must be refused and unchanged for the same reason.
	_check(port.request_action(ActorCommandPort.Action.DODGE) == false, "a dodge must be refused when stamina is insufficient")
	_check(port.get_state() == state_before, "a refused dodge must not change state")

	## Stamina returns after the regen delay.
	var before_regen := combatant.get_stamina()
	await _steps(120)
	_check(combatant.get_stamina() > before_regen, "stamina must regenerate after the delay (before=%.2f after=%.2f)" % [before_regen, combatant.get_stamina()])
	await _free_group(group)

func _test_attack_phases_and_locking() -> void:
	print("[test] attack phases run in order and lock facing and re-entry")
	var group := _new_root_group()
	var player := await _spawn(PLAYER_SCENE, Vector2(200, 200), group)
	var port := _port(player)
	var tuning := _combatant(player).tuning

	player.test_intent_override = true
	player.test_intent_aim = Vector2.RIGHT
	await _step()
	_check(port.get_state() == ActorCommandPort.State.IDLE, "player starts IDLE")
	_check(port.request_action(ActorCommandPort.Action.LIGHT_ATTACK), "a light attack with full stamina must start")
	_check(port.get_state() == ActorCommandPort.State.WINDUP, "an accepted attack enters WINDUP")
	var attack_id := port.get_attack_id()
	_check(attack_id > 0, "an accepted attack must consume an attack id")

	## Facing is locked for the whole attack: aiming left must not turn the actor.
	player.test_intent_aim = Vector2.LEFT
	await _steps(2)
	_check(port.get_facing().distance_to(Vector2.RIGHT) < 0.001, "facing must be locked during the attack (got %s)" % port.get_facing())

	## No cancelling and no re-entry while busy.
	_check(port.request_action(ActorCommandPort.Action.LIGHT_ATTACK) == false, "a second attack must be refused mid-swing")
	_check(port.request_action(ActorCommandPort.Action.DODGE) == false, "a dodge must be refused mid-swing")
	_check(port.get_attack_id() == attack_id, "a refused request must not consume another attack id")

	_check(await _advance_until(port, ActorCommandPort.State.ACTIVE, 60), "WINDUP must lead to ACTIVE")
	_check(port.is_attack_window_open(), "the damage window must be open in ACTIVE")
	_check(await _advance_until(port, ActorCommandPort.State.RECOVERY, 60), "ACTIVE must lead to RECOVERY")
	_check(not port.is_attack_window_open(), "the damage window must be closed in RECOVERY")
	_check(port.request_action(ActorCommandPort.Action.HEAVY_ATTACK) == false, "a heavy attack must be refused during recovery")
	_check(await _advance_until(port, ActorCommandPort.State.IDLE, 120), "RECOVERY must return to IDLE")
	_check_close(port.get_state_elapsed(), 0.0, 0.05, "IDLE must not keep accumulating attack time")

	## After recovering, the actor is free again.
	_check(port.request_action(ActorCommandPort.Action.HEAVY_ATTACK), "a heavy attack must be allowed once idle again")
	_check(port.get_active_attack() == tuning.heavy_attack, "the running attack must be the heavy spec")
	await _advance_until(port, ActorCommandPort.State.IDLE, 240)
	await _free_group(group)

func _test_hit_lands_once_per_swing() -> void:
	print("[test] one swing damages a target at most once")
	var group := _new_root_group()
	var player := await _spawn(PLAYER_SCENE, Vector2(200, 200), group)
	var dummy := await _spawn(DUMMY_SCENE, Vector2(220, 200), group)
	var port := _port(player)
	var target := _combatant(dummy)
	var before := target.get_health()

	player.test_intent_override = true
	player.test_intent_aim = Vector2.RIGHT
	await _step()
	_check(port.request_action(ActorCommandPort.Action.LIGHT_ATTACK), "the swing must start")
	## Run well past the whole attack: the target sits inside reach the entire time.
	await _steps(90)
	var after := target.get_health()
	## Derived from the player's actual spec plus its equipment bonus, because the light attack's
	## damage is data now (a weapon profile's move, or the unarmed fallback).
	var expected := before - (_combatant(player).tuning.light_attack.damage + _combatant(player).attack_bonus())
	_check_close(after, expected, 0.001, "the swing must deal its damage exactly once")
	_check(port.get_state() == ActorCommandPort.State.IDLE or port.get_state() == ActorCommandPort.State.MOVE, "the attack must have finished")
	await _free_group(group)

func _test_active_window_only() -> void:
	print("[test] WINDUP and RECOVERY deal no damage")
	var group := _new_root_group()
	var player := await _spawn(PLAYER_SCENE, Vector2(200, 200), group)
	var dummy := await _spawn(DUMMY_SCENE, Vector2(220, 200), group)
	var port := _port(player)
	var target := _combatant(dummy)
	var before := target.get_health()

	player.test_intent_override = true
	player.test_intent_aim = Vector2.RIGHT
	await _step()
	port.request_action(ActorCommandPort.Action.LIGHT_ATTACK)
	## Still in wind-up: no damage may have landed yet.
	await _steps(4)
	_check(port.get_state() == ActorCommandPort.State.WINDUP, "must still be winding up (state=%d)" % port.get_state())
	_check_close(target.get_health(), before, 0.001, "wind-up must deal no damage")

	## Let the ACTIVE window pass, then check the landing frame is inside it.
	await _advance_until(port, ActorCommandPort.State.RECOVERY, 60)
	_check(target.get_health() < before, "the ACTIVE window must have dealt damage")
	var after_active := target.get_health()
	await _advance_until(port, ActorCommandPort.State.IDLE, 120)
	_check_close(target.get_health(), after_active, 0.001, "recovery must deal no further damage")
	await _free_group(group)

func _test_dodge_invulnerability_window() -> void:
	print("[test] dodge grants invulnerability only inside its window")
	var group := _new_root_group()
	var player := await _spawn(PLAYER_SCENE, Vector2(200, 200), group)
	var port := _port(player)
	var combatant := _combatant(player)

	player.test_intent_override = true
	player.test_intent_move = Vector2.RIGHT
	await _step()
	_check(port.request_action(ActorCommandPort.Action.DODGE), "a dodge with full stamina must start")
	_check(port.get_state() == ActorCommandPort.State.DODGE, "the port must enter DODGE")

	## Before the window opens the actor is still hittable.
	await _advance_until_before_elapsed(port, 0.02)
	_check(port.get_state_elapsed() < 0.08, "must still be before the invulnerability window (%.3f)" % port.get_state_elapsed())
	var early := combatant.receive_hit(_event(10.0, Vector2(240, 200)))
	_check(early.outcome == HitResult.Outcome.DAMAGED, "a hit before the window must land (outcome=%d)" % early.outcome)

	## Inside the window the same hit must be dodged.
	await _advance_until_elapsed(port, 0.12)
	_check(port.get_state() == ActorCommandPort.State.DODGE, "must still be dodging (%.3f)" % port.get_state_elapsed())
	var dodged := combatant.receive_hit(_event(10.0, Vector2(240, 200)))
	_check(dodged.outcome == HitResult.Outcome.DODGED, "a hit inside the window must be dodged (outcome=%d)" % dodged.outcome)
	_check_close(dodged.damage_applied, 0.0, 0.001, "a dodged hit must deal no damage")

	## After the window closes the dodge is committed but no longer invulnerable.
	await _advance_until_elapsed(port, 0.25)
	_check(port.get_state() == ActorCommandPort.State.DODGE, "must still be dodging (%.3f)" % port.get_state_elapsed())
	var late := combatant.receive_hit(_event(10.0, Vector2(240, 200)))
	_check(late.outcome == HitResult.Outcome.DAMAGED, "a hit after the window must land (outcome=%d)" % late.outcome)
	await _free_group(group)

func _test_block_front_and_back() -> void:
	print("[test] the shield covers the front and not the back")
	var group := _new_root_group()
	var player := await _spawn(PLAYER_SCENE, Vector2(200, 200), group)
	var port := _port(player)
	var combatant := _combatant(player)

	player.test_intent_override = true
	player.test_intent_aim = Vector2.RIGHT
	player.test_intent_block = true
	await _steps(2)
	_check(port.get_state() == ActorCommandPort.State.BLOCK, "holding block must enter BLOCK (state=%d)" % port.get_state())

	var health_before := combatant.get_health()
	var stamina_before := combatant.get_stamina()
	var front := combatant.receive_hit(_event(18.0, Vector2(260, 200)))
	_check(front.outcome == HitResult.Outcome.BLOCKED, "a frontal attack must be blocked (outcome=%d)" % front.outcome)
	_check_close(combatant.get_health(), health_before, 0.001, "a blocked hit must deal no health damage")
	_check_close(stamina_before - combatant.get_stamina(), 16.0, 0.001, "a blocked hit must consume its stamina damage")

	var back := combatant.receive_hit(_event(18.0, Vector2(140, 200)))
	_check(back.outcome == HitResult.Outcome.DAMAGED, "an attack from behind must land (outcome=%d)" % back.outcome)
	_check_close(health_before - combatant.get_health(), 18.0, 0.001, "a back attack must deal full damage")

	## Releasing block returns to a free state.
	player.test_intent_block = false
	await _steps(2)
	_check(port.get_state() != ActorCommandPort.State.BLOCK, "releasing block must leave BLOCK (state=%d)" % port.get_state())
	await _free_group(group)

func _test_guard_break() -> void:
	print("[test] running out of stamina breaks the guard and staggers")
	var group := _new_root_group()
	var player := await _spawn(PLAYER_SCENE, Vector2(200, 200), group)
	var port := _port(player)
	var combatant := _combatant(player)

	player.test_intent_override = true
	player.test_intent_aim = Vector2.RIGHT
	player.test_intent_block = true
	await _steps(2)
	## Spend down to less than one block's stamina damage.
	while combatant.get_stamina() > 5.0:
		if not combatant.try_spend_stamina(10.0):
			break
	var health_before := combatant.get_health()
	var result := combatant.receive_hit(_event(18.0, Vector2(260, 200)))
	_check(result.outcome == HitResult.Outcome.GUARD_BROKEN, "a block without stamina must break the guard (outcome=%d)" % result.outcome)
	_check_close(health_before - combatant.get_health(), 18.0, 0.001, "a guard break must take full damage")
	_check(port.get_state() == ActorCommandPort.State.STAGGER, "a guard break must stagger the actor (state=%d)" % port.get_state())
	await _free_group(group)

func _test_death_is_exactly_once() -> void:
	print("[test] death fires once, disables the actor, and further hits are ignored")
	var group := _new_root_group()
	var player := await _spawn(PLAYER_SCENE, Vector2(200, 200), group)
	var port := _port(player)
	var combatant := _combatant(player)

	_death_count = 0
	combatant.died.connect(_on_died_counted)
	var killed := combatant.receive_hit(_event(500.0, Vector2(260, 200)))
	_check(killed.killed, "a lethal hit must report killed")
	_check(not combatant.is_alive(), "the actor must be dead")
	_check(_death_count == 1, "death must be signalled exactly once (got %d)" % _death_count)
	_check(port.get_state() == ActorCommandPort.State.DEAD, "the port must be DEAD (state=%d)" % port.get_state())

	## Further hits do nothing and never re-signal death.
	var again := combatant.receive_hit(_event(500.0, Vector2(260, 200)))
	_check(again.outcome == HitResult.Outcome.IGNORED, "a hit on a dead actor must be ignored (outcome=%d)" % again.outcome)
	_check(_death_count == 1, "death must not be signalled twice (got %d)" % _death_count)

	## A dead actor accepts no actions and does not move.
	_check(port.request_action(ActorCommandPort.Action.LIGHT_ATTACK) == false, "a dead actor must refuse actions")
	_check(port.request_action(ActorCommandPort.Action.DODGE) == false, "a dead actor must refuse a dodge")
	player.test_intent_override = true
	player.test_intent_move = Vector2.RIGHT
	var position_before := player.global_position
	await _steps(10)
	_check_close(player.global_position.distance_to(position_before), 0.0, 0.001, "a dead actor must not move")

	## Damage never heals.
	_check_close(combatant.get_health(), 0.0, 0.001, "health must stay at zero")
	await _free_group(group)

func _test_bandit_approaches_and_damages_player() -> void:
	print("[test] the bandit closes in, winds up, and can damage the player")
	var group := _new_root_group()
	var player := await _spawn(PLAYER_SCENE, Vector2(200, 270), group)
	var bandit := await _spawn(BANDIT_SCENE, Vector2(420, 270), group)
	bandit.set_target_path(player.get_path())
	var player_combatant := _combatant(player)
	var bandit_combatant := _combatant(bandit)
	var start_distance := bandit.global_position.distance_to(player.global_position)

	## Let the fight run itself. The player stands still so the bandit must do the work.
	var saw_windup := false
	var health_before := player_combatant.get_health()
	for _i in 600:
		await _step()
		if _port(bandit).get_state() == ActorCommandPort.State.WINDUP:
			saw_windup = true
		if player_combatant.get_health() < health_before:
			break
	var end_distance := bandit.global_position.distance_to(player.global_position)
	_check(end_distance < start_distance, "the bandit must close the distance (%.1f -> %.1f)" % [start_distance, end_distance])
	_check(saw_windup, "the bandit must visibly wind up before attacking")
	_check(player_combatant.get_health() < health_before, "the bandit must be able to damage the player (health=%.1f)" % player_combatant.get_health())
	_check(bandit_combatant.is_alive(), "the bandit must survive its own approach")

	## The player can kill the bandit, and it is the shared hitbox that does it.
	var bandit_health := bandit_combatant.get_health()
	var attack_id_before := _port(player).get_attack_id()
	player.test_intent_override = true
	player.test_intent_aim = (bandit.global_position - player.global_position).normalized()
	await _step()
	for _i in 12:
		var port := _port(player)
		if ActionRules.allows_locomotion(port.get_state()):
			if not port.request_action(ActorCommandPort.Action.LIGHT_ATTACK):
				break
		await _steps(40)
		if not bandit_combatant.is_alive():
			break
	_check(_port(player).get_attack_id() > attack_id_before, "the player must have swung at the bandit")
	_check(bandit_combatant.get_health() < bandit_health, "the player's swings must damage the bandit (health=%.1f)" % bandit_combatant.get_health())
	await _free_group(group)

## Retry now runs through the encounter system (T03 moved enemies out of the scene into managed
## encounters), so this drives the arena as a player would: walk in, fight, die, press retry.
func _test_retry_restores_both_sides() -> void:
	print("[test] retry restores the player and re-arms the encounter")
	var arena := (load("res://scenes/arena.tscn") as PackedScene).instantiate()
	root.add_child(arena)
	await _steps(3)
	var player := arena.get_node("Player") as PlayerController
	var encounters := arena.get_node("Encounters") as EncounterManager
	var player_combatant := _combatant(player)
	var player_spawn := player.global_position

	## Walk into the enemy encounter (the training area only holds an inert dummy).
	var pack_center := encounters.activity_center(&"pack")
	player.global_position = pack_center + Vector2(-60, 100)
	await _steps(5)
	_check(encounters.is_engaged(&"pack"), "walking into an enemy area must engage it")
	var enemies_before := encounters.all_enemy_nodes().size()
	_check(enemies_before >= 2, "the pack encounter must put more than one enemy on the field (got %d)" % enemies_before)

	## Losing a fight: kill the player outright, then retry.
	player_combatant.receive_hit(_event_from_team(ENEMY_TEAM, 500.0, player.global_position + Vector2(10, 0)))
	await _steps(2)
	_check(not player_combatant.is_alive(), "the player must be dead before the retry")

	arena.restart()
	_check(_port(player).get_state() == ActorCommandPort.State.IDLE, "retry must clear the player's action state")
	await _steps(2)
	_check(player_combatant.is_alive(), "retry must revive the player")
	_check_close(player_combatant.get_health(), player_combatant.max_health(), 0.001, "retry must restore player health")
	_check_close(player.global_position.distance_to(player_spawn), 0.0, 0.001, "retry must return the player to its spawn")
	_check(encounters.total_alive_enemies() == encounters.alive_enemy_count(&"training"), "retry must clear every encounter except the one the player spawns inside (alive=%d)" % encounters.total_alive_enemies())

	## Walking back in must start the encounter over, and it must be playable again.
	player.global_position = pack_center + Vector2(-60, 100)
	await _steps(5)
	_check(encounters.is_engaged(&"pack"), "re-entering must re-arm the encounter")
	_check(encounters.all_enemy_nodes().size() == enemies_before, "re-entering must respawn the same number of enemies")
	_check(not encounters.is_defeated(&"pack"), "a re-armed encounter must not still count as defeated")

	var nearest := _nearest_enemy(encounters, player.global_position)
	if nearest != null:
		var distance_before := nearest.global_position.distance_to(player.global_position)
		await _steps(180)
		var distance_after := nearest.global_position.distance_to(player.global_position)
		_check(distance_after < distance_before, "an enemy must engage again after a retry (%.1f -> %.1f)" % [distance_before, distance_after])
	arena.queue_free()
	await physics_frame

func _collect_enemy_spawns(encounters: EncounterManager) -> Array[Vector2]:
	var positions: Array[Vector2] = []
	for enemy in encounters.all_enemy_nodes():
		positions.append(enemy.global_position)
	return positions

func _nearest_enemy(encounters: EncounterManager, from: Vector2) -> Node2D:
	var best: Node2D = null
	var best_distance := INF
	for enemy in encounters.all_enemy_nodes():
		var distance := enemy.global_position.distance_to(from)
		if distance < best_distance:
			best_distance = distance
			best = enemy
	return best

func _advance_until_elapsed(port: ActorCommandPort, seconds: float, max_steps := 240) -> bool:
	for _i in max_steps:
		if port.get_state_elapsed() >= seconds:
			return true
		await _step()
	return port.get_state_elapsed() >= seconds

func _advance_until_before_elapsed(port: ActorCommandPort, seconds: float, max_steps := 240) -> bool:
	for _i in max_steps:
		if port.get_state_elapsed() >= seconds:
			return false
		await _step()
	return true
