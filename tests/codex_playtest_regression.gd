extends SceneTree

var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("%s %s" % ["PASS" if ok else "FAIL", label])

func steps(n: int) -> void:
	for i in n:
		await physics_frame

func spawn(path: String, parent: Node, pos: Vector2) -> Node2D:
	var node := load(path).instantiate() as Node2D
	node.position = pos
	parent.add_child(node)
	return node

func _run() -> void:
	await steps(2)
	GameSession.current = null
	var village := spawn("res://scenes/level_village.tscn", root, Vector2.ZERO)
	current_scene = village
	var player := village.get_node("Player") as Node2D
	player.global_position = village.get_node("QuestGiver").global_position + Vector2(25, 0)
	await steps(3)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_E
	key.pressed = true
	Input.parse_input_event(key)
	await steps(2)
	key = InputEventKey.new()
	key.physical_keycode = KEY_E
	Input.parse_input_event(key)
	check(GameSession.current.quest_stage == GameSession.QuestStage.IN_PROGRESS, "cold start: physical E accepts quest")
	var shape := village.get_node("Well/Shape") as CollisionShape2D
	check((shape.shape as RectangleShape2D).size == Vector2(40, 40), "well collider matches 40x40 visual")
	village.free()
	await steps(2)
	for direction in [Vector2.LEFT, Vector2.UP, Vector2(1, -1).normalized()]:
		await shooting(direction)
	await projectile_walls()
	await encounters()
	print("CODEX_PLAYTEST: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func shooting(direction: Vector2) -> void:
	var scope := Node2D.new()
	root.add_child(scope)
	var target := spawn("res://scenes/player.tscn", scope, Vector2(400, 400) + direction * 140)
	var archer := spawn("res://scenes/archer.tscn", scope, Vector2(400, 400)) as ArcherController
	archer.hold_position = true
	archer.set_target_path(target.get_path())
	var arrows: Array[CombatProjectile] = []
	archer.get_node("AttackSpawner").projectile_spawned.connect(func(arrow: CombatProjectile): arrows.append(arrow))
	for i in 140:
		await steps(1)
		if not arrows.is_empty():
			break
	check(not arrows.is_empty(), "first arrow spawned toward %s" % direction)
	if not arrows.is_empty() and is_instance_valid(arrows[0]):
		var arrow := arrows[0]
		check(Vector2.RIGHT.rotated(arrow.global_rotation).dot(direction) > 0.999, "first arrow direction matches target")
		var line := archer.get_node("Visual/AimLine") as Line2D
		check(line.points[1].normalized().dot(direction) > 0.999, "telegraph matches shot")
		var before := arrow.global_position
		archer.global_position += Vector2(50, 50)
		check(arrow.global_position.distance_to(before) < 0.01, "moving shooter cannot drag arrow through geometry")
	await steps(55)
	check(target.get_node("ActorCombatant").get_health() < 100.0, "arrow actually hits target")
	scope.free()
	await steps(2)

func wall(parent: Node, position: Vector2, size: Vector2) -> void:
	var body := StaticBody2D.new()
	body.position = position
	body.collision_layer = 1
	var rect := RectangleShape2D.new()
	rect.size = size
	var collider := CollisionShape2D.new()
	collider.shape = rect
	body.add_child(collider)
	parent.add_child(body)

func projectile_walls() -> void:
	var scope := Node2D.new()
	root.add_child(scope)
	wall(scope, Vector2(100, 100), Vector2(36, 36))
	await steps(2)
	for start in [Vector2(40, 100), Vector2(100, 100)]:
		var arrow := spawn("res://scenes/arrow.tscn", scope, start) as CombatProjectile
		arrow.setup(Vector2.RIGHT, 2, load("res://data/archer_shot.tres"), 0, 1)
		await steps(30)
		check(not is_instance_valid(arrow), "wall stops arrow starting at %s" % start)
	scope.free()
	await steps(2)
	# Test a shot whose locked muzzle direction meets cover, although target LOS is clear.
	scope = Node2D.new()
	root.add_child(scope)
	var archer := spawn("res://scenes/archer.tscn", scope, Vector2(100, 100)) as ArcherController
	archer.set_physics_process(false)
	wall(scope, Vector2(110, 100), Vector2(2, 30))
	await steps(2)
	var arrows: Array[CombatProjectile] = []
	archer.get_node("AttackSpawner").projectile_spawned.connect(func(a: CombatProjectile): arrows.append(a))
	archer.get_node("ActorActionPort").set_intent(Vector2.ZERO, Vector2.RIGHT, false)
	archer.get_node("ActorActionPort").request_action(ActorCommandPort.Action.LIGHT_ATTACK)
	await steps(80)
	check(arrows.is_empty() and archer.blocked_shot_count() > 0, "muzzle offset cannot skip thin wall")
	scope.free()
	await steps(2)

func encounters() -> void:
	var arena := spawn("res://scenes/arena.tscn", root, Vector2.ZERO)
	var manager := arena.get_node("Encounters") as EncounterManager
	var player := arena.get_node("Player") as Node2D
	player.global_position = manager.activity_center(&"pack") + Vector2(0, 50)
	await steps(5)
	var count := manager.alive_enemy_count(&"pack")
	check(count > 0, "encounter activates")
	var originals := manager.all_enemy_nodes()
	player.global_position = Vector2(80, 80)
	await steps(5)
	check(manager.alive_enemy_count(&"pack") == count and manager.is_engaged(&"pack"), "retreat preserves living enemies")
	var same := true
	for enemy in originals:
		same = same and is_instance_valid(enemy)
	check(same, "retreat preserves original instances")
	var disengaged: Array[StringName] = []
	manager.encounter_disengaged.connect(func(id: StringName): disengaged.append(id))
	for enemy in manager.all_enemy_nodes():
		var event := DamageEvent.new()
		event.source_id = 9876
		event.attack_id = 1
		event.team_id = 1
		event.raw_damage = 9999
		event.origin = player.global_position
		enemy.get_node("ActorCombatant").receive_hit(event)
	await steps(3)
	check(manager.is_defeated(&"pack") and not manager.is_engaged(&"pack"), "full defeat ends engagement")
	player.global_position = manager.activity_center(&"pack")
	await steps(3)
	player.global_position = Vector2(80, 80)
	await steps(3)
	check(disengaged.is_empty() and manager.alive_enemy_count(&"pack") == 0, "defeated encounter neither respawns nor reports disengagement")
	manager.reset_all()
	await steps(3)
	check(not manager.is_defeated(&"pack"), "retry resets defeated state")
	arena.free()
	await steps(2)
