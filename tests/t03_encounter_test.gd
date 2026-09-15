extends SceneTree
## T03 acceptance tests: walls block shots, cover prevents fire, encounters engage/disengage, and
## a retry cleans up both enemies and arrows.
##
## Runnable with:
##   godot --headless --path <project> --script res://tests/t03_encounter_test.gd
## Exits 0 when every case passes, 1 otherwise.

const ARENA_SCENE := "res://scenes/arena.tscn"
const PLAYER_SCENE := "res://scenes/player.tscn"
const BANDIT_SCENE := "res://scenes/bandit.tscn"
const ARCHER_SCENE := "res://scenes/archer.tscn"
const BEAST_SCENE := "res://scenes/beast.tscn"

var _failures: Array[String] = []
var _checks := 0

func _initialize() -> void:
	_run()

func _run() -> void:
	print("=== T03 encounter/archer/beast tests ===")
	await physics_frame
	await _test_wall_blocks_arrow()
	await _test_no_shot_through_wall()
	await _test_archer_hits_with_clear_line()
	await _test_beast_lunges_forward()
	await _test_encounter_persists_after_retreat()
	await _test_leaving_preserves_survivors()
	await _test_retry_clears_everything()
	await _test_retreat_does_not_despawn()
	print("--- checks=%d failures=%d" % [_checks, _failures.size()])
	if _failures.is_empty():
		print("T03_ENCOUNTER_TESTS: PASS")
		quit(0)
	else:
		for failure in _failures:
			print("T03_ENCOUNTER_TESTS: FAIL %s" % failure)
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

func _spawn(scene_path: String, position: Vector2, parent: Node) -> Node2D:
	var actor := (load(scene_path) as PackedScene).instantiate() as Node2D
	parent.add_child(actor)
	actor.global_position = position
	await _step()
	return actor

func _combatant(actor: Node) -> ActorCombatant:
	return actor.get_node("ActorCombatant") as ActorCombatant

func _port(actor: Node) -> ActorCommandPort:
	return actor.get_node("ActorActionPort") as ActorCommandPort

func _new_group() -> Node2D:
	var group := Node2D.new()
	root.add_child(group)
	return group

func _free_group(group: Node) -> void:
	group.queue_free()
	await physics_frame

func _enemy_event(raw_damage: float, origin: Vector2) -> DamageEvent:
	var event := DamageEvent.new()
	event.source_id = 900002
	event.attack_id = 1
	event.team_id = 2
	event.raw_damage = raw_damage
	event.stamina_damage = 10.0
	event.origin = origin
	return event

# --- archer / projectile -------------------------------------------------------------------

## Builds an isolated shooting range: one wall (or none), one archer, one player. The arena's own
## encounters are deliberately not used here, so a hit can only have come from the archer.
func _spawn_range(with_wall: bool, archer_at: Vector2, player_at: Vector2) -> Node2D:
	var group := Node2D.new()
	root.add_child(group)
	if with_wall:
		_add_wall(group, Vector2(270, 200), Vector2(40, 300))
	var player := (load(PLAYER_SCENE) as PackedScene).instantiate() as Node2D
	group.add_child(player)
	player.global_position = player_at
	var archer := (load(ARCHER_SCENE) as PackedScene).instantiate() as Node2D
	group.add_child(archer)
	archer.global_position = archer_at
	## Deterministic firing line: the cover cases must test the wall, not the archer's flanking.
	(archer as ArcherController).hold_position = true
	archer.set_target_path(player.get_path())
	await _steps(2)
	return group

func _add_wall(parent: Node, center: Vector2, size: Vector2) -> void:
	var body := StaticBody2D.new()
	body.position = center
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	body.add_child(shape)
	parent.add_child(body)

## Arena's centre block spans x 408..552, y 222..318. Archer on the left, player behind it.
func _test_wall_blocks_arrow() -> void:
	print("[test] a wall stops an arrow")
	var group := await _spawn_range(true, Vector2(200, 200), Vector2(340, 200))
	var archer := _find_archer(group)
	var player := _find_player(group)
	var player_combatant := _combatant(player)
	var health_before := player_combatant.get_health()

	## Cover prevents the AI from starting an attack.
	await _steps(90)
	var saw_attempt := _port(archer).get_state() == ActorCommandPort.State.IDLE
	_check(saw_attempt, "cover keeps the archer idle")
	_check(_projectile_count(group) == 0, "no arrow may be released into a wall (in flight=%d)" % _projectile_count(group))
	_check_close(player_combatant.get_health(), health_before, 0.001, "an arrow stopped by a wall must deal no damage")
	await _free_group(group)

func _test_no_shot_through_wall() -> void:
	print("[test] cover prevents attacks and damage")
	var group := await _spawn_range(true, Vector2(200, 200), Vector2(340, 200))
	var archer := _find_archer(group)
	var port := _port(archer)
	var player := _find_player(group)
	var player_combatant := _combatant(player)
	var health_before := player_combatant.get_health()
	var open_windows := 0

	## Stand still behind cover: the archer may glare and even loose, but nothing may connect.
	for _i in 900:
		await _step()
		if port.is_attack_window_open():
			open_windows += 1
	_check(open_windows == 0, "cover prevents attack windows")
	_check_close(player_combatant.get_health(), health_before, 0.001, "no damage may come through a wall (open windows=%d)" % open_windows)
	_check(archer.blocked_shot_count() == 0, "AI does not commit blocked shots (blocked=%d)" % archer.blocked_shot_count())
	await _free_group(group)

func _test_archer_hits_with_clear_line() -> void:
	print("[test] with a clear line the arrow lands")
	var group := await _spawn_range(false, Vector2(200, 200), Vector2(340, 200))
	var player := _find_player(group)
	var player_combatant := _combatant(player)
	var health_before := player_combatant.get_health()

	for _i in 900:
		await _step()
		if player_combatant.get_health() < health_before:
			break
	_check(player_combatant.get_health() < health_before, "an unobstructed archer must be able to hit (health=%.1f)" % player_combatant.get_health())
	_check_close(health_before - player_combatant.get_health(), 10.0, 0.001, "the arrow must deal its configured damage")
	await _free_group(group)

func _test_beast_lunges_forward() -> void:
	print("[test] the beast's lunge carries it forward")
	var group := _new_group()
	var beast := await _spawn(BEAST_SCENE, Vector2(200, 200), group)
	var player := await _spawn(PLAYER_SCENE, Vector2(400, 200), group)
	beast.set_target_path(player.get_path())
	var port := _port(beast)

	## Watch for a committed lunge and measure the ground it covers while dashing.
	var travelled_during_lunge := 0.0
	var saw_lunge := false
	var previous: Vector2 = beast.global_position
	for _i in 600:
		await _step()
		var state := port.get_state()
		if state == ActorCommandPort.State.WINDUP or state == ActorCommandPort.State.ACTIVE or state == ActorCommandPort.State.RECOVERY:
			saw_lunge = true
			travelled_during_lunge += beast.global_position.distance_to(previous)
		previous = beast.global_position
	_check(saw_lunge, "the beast must commit to a lunge")
	_check(travelled_during_lunge > 30.0, "the lunge must move the body forward (covered %.1f px)" % travelled_during_lunge)
	_check(_combatant(player).get_health() < _combatant(player).max_health(), "the lunge must be able to connect")
	await _free_group(group)

# --- encounters ----------------------------------------------------------------------------

func _test_encounter_persists_after_retreat() -> void:
	print("[test] an encounter activates inside and persists outside")
	var arena := await _spawn_arena()
	var encounters := arena.get_node("Encounters") as EncounterManager
	var player := arena.get_node("Player") as PlayerController

	var center := encounters.activity_center(&"pack")
	player.global_position = center + Vector2(0, 60)
	await _steps(4)
	_check(encounters.is_engaged(&"pack"), "standing inside the area must engage it")
	_check(encounters.alive_enemy_count(&"pack") >= 2, "the pack must field more than one enemy (got %d)" % encounters.alive_enemy_count(&"pack"))

	## Far away, outside every area.
	player.global_position = Vector2(80, 80)
	await _steps(4)
	_check(encounters.is_engaged(&"pack"), "retreat keeps the encounter active")
	_check(encounters.alive_enemy_count(&"pack") >= 2, "retreat preserves survivors")
	arena.queue_free()
	await physics_frame

func _test_leaving_preserves_survivors() -> void:
	print("[test] walking away preserves living enemies")
	var arena := await _spawn_arena()
	var encounters := arena.get_node("Encounters") as EncounterManager
	var player := arena.get_node("Player") as PlayerController

	var center := encounters.activity_center(&"outpost")
	player.global_position = center + Vector2(-70, 40)
	await _steps(6)
	_check(encounters.is_engaged(&"outpost"), "the outpost area must engage")
	var spawned := encounters.all_enemy_nodes().size()
	_check(spawned >= 3, "the outpost must field three enemies (got %d)" % spawned)

	## Give the archers time to put arrows in the air, then leave.
	await _steps(120)
	var _arrows_before := _projectile_count(arena)
	player.global_position = Vector2(80, 500)
	await _steps(6)
	_check(encounters.alive_enemy_count(&"outpost") >= 3, "leaving must preserve survivors (got %d)" % encounters.alive_enemy_count(&"outpost"))
	_check(encounters.is_engaged(&"outpost"), "retreat does not reset the encounter")
	arena.queue_free()
	await physics_frame

func _test_retry_clears_everything() -> void:
	print("[test] retry clears enemies and arrows")
	var arena := await _spawn_arena()
	var encounters := arena.get_node("Encounters") as EncounterManager
	var player := arena.get_node("Player") as PlayerController

	var center := encounters.activity_center(&"outpost")
	player.global_position = center + Vector2(-70, 40)
	await _steps(120)
	_check(encounters.total_alive_enemies() > 0, "the encounter must be live before the retry")

	arena.restart()
	await _steps(3)
	## The player spawns inside the training area, so that one dummy may legitimately come back;
	## every other encounter must be gone, and nothing may be left in flight.
	_check(encounters.alive_enemy_count(&"outpost") == 0, "retry must clear the outpost (got %d)" % encounters.alive_enemy_count(&"outpost"))
	_check(encounters.alive_enemy_count(&"pack") == 0, "retry must clear the pack (got %d)" % encounters.alive_enemy_count(&"pack"))
	_check(_projectile_count(arena) == 0, "retry must clear arrows in flight (got %d)" % _projectile_count(arena))
	_check(not encounters.is_defeated(&"outpost"), "retry must not leave the outpost marked as defeated")
	arena.queue_free()
	await physics_frame

func _test_retreat_does_not_despawn() -> void:
	print("[test] enemies persist beyond the activation area")
	var arena := await _spawn_arena()
	var encounters := arena.get_node("Encounters") as EncounterManager
	var player := arena.get_node("Player") as PlayerController

	var center := encounters.activity_center(&"pack")
	player.global_position = center + Vector2(0, 50)
	await _steps(6)
	_check(encounters.is_engaged(&"pack"), "the pack must engage")

	## Retreat across the original boundary; survivors must remain.
	player.global_position = Vector2(120, 480)
	for _i in 240:
		await _step()
		player.global_position = Vector2(120, 480)
	_check(encounters.alive_enemy_count(&"pack") > 0, "enemies remain outside activation area (alive=%d)" % encounters.total_alive_enemies())
	_check(encounters.is_engaged(&"pack"), "the pack remains active while player is away")
	arena.queue_free()
	await physics_frame

# --- helpers -------------------------------------------------------------------------------

func _spawn_arena() -> Node2D:
	var arena := (load(ARENA_SCENE) as PackedScene).instantiate() as Node2D
	root.add_child(arena)
	await _steps(2)
	return arena

## Steps until an arrow exists (or the budget runs out); returns whether one was fired.
func _fire_until_projectile(scope: Node, max_steps: int) -> bool:
	for _i in max_steps:
		await _step()
		if _projectile_count(scope) > 0:
			return true
	return false

## Steps until the archer has committed a shot that cover cancelled.
func _wait_for_blocked_shot(archer: ArcherController, max_steps: int) -> bool:
	for _i in max_steps:
		await _step()
		if archer.blocked_shot_count() == 0:
			return true
	return false

func _find_archer(scope: Node) -> ArcherController:
	for node in _all_descendants(scope):
		if node is ArcherController:
			return node as ArcherController
	return null

func _find_player(scope: Node) -> PlayerController:
	for node in _all_descendants(scope):
		if node is PlayerController:
			return node as PlayerController
	return null

func _projectile_count(scope: Node) -> int:
	var count := 0
	for node in _all_descendants(scope):
		if node is CombatProjectile:
			count += 1
	return count

func _all_descendants(scope: Node) -> Array[Node]:
	var found: Array[Node] = []
	for child in scope.get_children():
		found.append(child)
		found.append_array(_all_descendants(child))
	return found
