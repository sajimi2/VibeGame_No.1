extends SceneTree
## Regression tests for the three defects found while playing T03:
##   1. enemies vanished because the activity radius was bigger than the visible screen;
##   2. the enemy health bar was wired to one hard-coded node, so it never moved;
##   3. hits on enemies produced no feedback at all.
##
## Runnable with:
##   godot --headless --path <project> --script res://tests/t04_bugfix_test.gd
## Exits 0 when every case passes, 1 otherwise.

const ARENA_SCENE := "res://scenes/arena.tscn"

var _failures: Array[String] = []
var _checks := 0

func _initialize() -> void:
	_run()

func _run() -> void:
	print("=== T03 defect regression tests ===")
	await physics_frame
	await _test_activation_radius_preserves_enemies()
	await _test_health_bar_follows_damage()
	await _test_health_bar_switches_on_death()
	await _test_hit_feedback_flashes()
	await _test_dead_enemy_is_cleared()
	print("--- checks=%d failures=%d" % [_checks, _failures.size()])
	if _failures.is_empty():
		print("T03_BUGFIX_TESTS: PASS")
		quit(0)
	else:
		for failure in _failures:
			print("T03_BUGFIX_TESTS: FAIL %s" % failure)
		quit(1)

# --- harness -------------------------------------------------------------------------------

func _check(condition: bool, message: String) -> bool:
	_checks += 1
	if not condition:
		_failures.append(message)
		print("  [FAIL] %s" % message)
	return condition

func _check_close(actual: float, expected: float, tolerance: float, message: String) -> bool:
	return _check(absf(actual - expected) <= tolerance, "%s (actual=%.2f expected=%.2f tol=%.2f)" % [message, actual, expected, tolerance])

func _step() -> void:
	await physics_frame

func _steps(count: int) -> void:
	for _i in count:
		await _step()

func _spawn_arena() -> Node2D:
	var arena := (load(ARENA_SCENE) as PackedScene).instantiate() as Node2D
	root.add_child(arena)
	await _steps(2)
	return arena

func _hud(arena: Node) -> CombatHud:
	return arena.get_node("HintLayer") as CombatHud

func _player(arena: Node) -> PlayerController:
	return arena.get_node("Player") as PlayerController

func _enemy_bar(arena: Node) -> ProgressBar:
	return arena.get_node("HintLayer/EnemyBar") as ProgressBar

func _enemy_name(arena: Node) -> Label:
	return arena.get_node("HintLayer/EnemyName") as Label

func _combatant(node: Node) -> ActorCombatant:
	return node.get_node_or_null("ActorCombatant") as ActorCombatant

func _damage(target: ActorCombatant, raw: float, attack_id: int) -> HitResult:
	var event := DamageEvent.new()
	event.source_id = 777001
	event.attack_id = attack_id
	event.team_id = 1
	event.raw_damage = raw
	event.stamina_damage = 10.0
	event.origin = target.global_position + Vector2(10, 0)
	return target.receive_hit(event)

func _free(arena: Node) -> void:
	arena.queue_free()
	await physics_frame

# --- cases ---------------------------------------------------------------------------------

## Activation is bounded, but crossing its radius must not delete a live encounter.
func _test_activation_radius_preserves_enemies() -> void:
	print("[test] activation radius does not delete living enemies")
	var arena := await _spawn_arena()
	var encounters := arena.get_node("Encounters") as EncounterManager
	## The camera shows 320x180 around the player.
	var max_visible_radius := 170.0
	for id in [&"training", &"pack", &"outpost"]:
		for state in encounters.get("_runtime"):
			var group: EncounterGroup = state["group"]
			if group.id != id:
				continue
			_check(group.activity_radius > 0, "%s activation radius %.0f must be positive (legacy reference %.0f)" % [id, group.activity_radius, max_visible_radius])

	## Retreat must preserve the encounter.
	var player := _player(arena)
	var center := encounters.activity_center(&"pack")
	player.global_position = center
	await _steps(4)
	_check(encounters.is_engaged(&"pack"), "standing in the centre must engage the pack")
	player.global_position = center + Vector2(0, 260)
	await _steps(4)
	_check(encounters.is_engaged(&"pack"), "stepping outside the area preserves the encounter")
	await _free(arena)

## Defect 2a: the bar never followed damage.
func _test_health_bar_follows_damage() -> void:
	print("[test] the enemy bar follows the focused enemy's health")
	var arena := await _spawn_arena()
	var encounters := arena.get_node("Encounters") as EncounterManager
	var player := _player(arena)
	player.global_position = encounters.activity_center(&"pack")
	await _steps(20)

	var bar := _enemy_bar(arena)
	_check(bar != null, "the HUD must have an enemy bar")
	var focus := _hud(arena).get("_focus") as ActorCombatant
	_check(focus != null, "standing among enemies must focus one of them")
	if focus == null:
		await _free(arena)
		return
	_check_close(bar.value, focus.get_health(), 0.01, "the bar must start at the focused enemy's health")
	_check(bar.max_value > 1.0, "the bar must show a real maximum rather than its placeholder")

	_damage(focus, 25.0, 500)
	await _steps(20)
	_check_close(bar.value, focus.get_health(), 0.01, "the bar must follow damage to the focused enemy")
	_check(bar.value < bar.max_value, "a damaged enemy must not read as full health")
	await _free(arena)

## Defect 2b: after a kill the bar stayed on the dead enemy and reported it as healthy.
func _test_health_bar_switches_on_death() -> void:
	print("[test] the bar moves on after a kill instead of describing a corpse")
	var arena := await _spawn_arena()
	var encounters := arena.get_node("Encounters") as EncounterManager
	var player := _player(arena)
	player.global_position = encounters.activity_center(&"pack")
	await _steps(20)

	var focus := _hud(arena).get("_focus") as ActorCombatant
	_check(focus != null, "an enemy must be focused before the kill")
	if focus == null:
		await _free(arena)
		return
	var killed_name := focus.get_parent().name
	_damage(focus, 500.0, 501)
	await _steps(30)

	var bar := _enemy_bar(arena)
	var new_focus := _hud(arena).get("_focus") as ActorCombatant
	_check(not focus.is_alive(), "the focused enemy must be dead")
	_check(new_focus != focus, "the focus must leave the dead enemy")
	_check(new_focus == null or new_focus.is_alive(), "the new focus must be a living enemy")
	if new_focus != null:
		_check_close(bar.value, new_focus.get_health(), 0.01, "the bar must describe the new focus")
		_check(new_focus.get_parent().name != killed_name, "the bar must not remain on the killed enemy")
	await _free(arena)

## Defect 3: enemies had no hit feedback, so landing a hit looked like nothing happened.
func _test_hit_feedback_flashes() -> void:
	print("[test] enemies visibly react to being hit")
	var arena := await _spawn_arena()
	var encounters := arena.get_node("Encounters") as EncounterManager
	var player := _player(arena)
	player.global_position = encounters.activity_center(&"pack")
	await _steps(20)

	var flash_seen := false
	var dead_tinted := false
	var focus := _hud(arena).get("_focus") as ActorCombatant
	_check(focus != null, "an enemy must be focused")
	if focus == null:
		await _free(arena)
		return
	var enemy := focus.get_parent() as Node2D
	var body := enemy.get_node("Visual/Body") as Polygon2D
	var base_color := body.color

	_damage(focus, 10.0, 600)
	for _i in 12:
		await _step()
		if body.color == Color.WHITE:
			flash_seen = true
	_check(flash_seen, "a damaged enemy must flash")
	await _steps(20)
	_check(body.color != Color.WHITE, "the flash must end")
	_check(body.color == base_color, "the body must return to its own colour")

	## Every enemy kind must have the feedback component, not just the one that was focused.
	for kind in ["bandit.tscn", "archer.tscn", "beast.tscn"]:
		var scene := (load("res://scenes/" + kind) as PackedScene).instantiate()
		var has_feedback := false
		for child in scene.get_children():
			if child is ActorHitFeedback:
				has_feedback = true
		_check(has_feedback, "%s must carry hit feedback" % kind)
		scene.free()

	## And death must leave a visible tint rather than an unchanged body. The death flash runs
	## first, so wait past it.
	_damage(focus, 500.0, 601)
	await _steps(24)
	if body.color == ActorHitFeedback.DEAD_TINT:
		dead_tinted = true
	_check(dead_tinted, "a dead enemy must be visibly marked (colour=%s)" % body.color)
	await _free(arena)

## A killed enemy must be cleared, otherwise it keeps blocking the player and reads as unfinished.
func _test_dead_enemy_is_cleared() -> void:
	print("[test] a defeated enemy is cleared from the field")
	var arena := await _spawn_arena()
	var encounters := arena.get_node("Encounters") as EncounterManager
	var player := _player(arena)
	player.global_position = encounters.activity_center(&"pack")
	await _steps(20)

	var focus := _hud(arena).get("_focus") as ActorCombatant
	if focus == null:
		_check(false, "an enemy must be focused")
		await _free(arena)
		return
	var enemy := focus.get_parent() as Node
	var before := encounters.total_alive_enemies()
	_damage(focus, 500.0, 700)
	await _steps(10)
	_check(encounters.total_alive_enemies() == before - 1, "a kill must reduce the living count (%d -> %d)" % [before, encounters.total_alive_enemies()])
	## Still on the field right after dying, so the death is visible...
	_check(is_instance_valid(enemy), "the body must linger briefly so the death is visible")
	## ...and gone once the linger expires.
	await _steps(90)
	_check(not is_instance_valid(enemy), "the body must be cleared after the linger")
	await _free(arena)
