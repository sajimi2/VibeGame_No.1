extends SceneTree

var checks := 0
var failures := 0
const SAVE := "res://work/v02_test_save.json"

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
	print("%s %s" % ["PASS" if condition else "FAIL", description])

func frames(n := 4) -> void:
	for i in n:
		await physics_frame

func buttons(node: Node) -> Array[Button]:
	var result: Array[Button] = []
	for child in node.get_children():
		if child is Button:
			result.append(child)
		result.append_array(buttons(child))
	return result

func click(panel: Node, caption: String) -> bool:
	for button in buttons(panel):
		if button.text == caption and not button.disabled:
			button.pressed.emit()
			return true
	return false

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await frames(2)
	event = InputEventKey.new()
	event.physical_keycode = code
	Input.parse_input_event(event)
	await frames(2)

func run() -> void:
	await frames()
	GameSession.current = null
	var level := load("res://scenes/level_village.tscn").instantiate() as LevelFlow
	root.add_child(level)
	current_scene = level
	await frames()
	var player := level.get_node("Player") as PlayerController
	var inventory := player.get_node("ActorInventory") as ActorInventory
	var progression := player.get_node("ActorProgression") as ActorProgression
	var panel := level.get_node("HintLayer/InventoryPanel") as InventoryPanel
	var item := ItemCatalog.build().roll(&"bandit_cleaver", "v02-sword")
	var pickup := load("res://scenes/item_pickup.tscn").instantiate() as ItemPickup
	level.add_child(pickup)
	pickup.global_position = player.global_position
	pickup.setup(item, inventory)
	await frames(8)
	check(not is_instance_valid(pickup) and inventory.has_instance(item.instance_id), "real overlap picks up into production inventory")
	await key(KEY_I)
	check(level.is_inventory_open() and paused, "I opens inventory and pauses")
	check(not player.can_process(), "world is actually paused behind inventory")
	var caption := ("★" if item.rarity == 1 else "") + "盗匪砍刀"
	check(click(panel, caption), "UI renders and selects acquired item")
	check(inventory.get_equipped(&"weapon") == null, "selection does not equip immediately")
	check(click(panel, "装备"), "equipment button connected")
	check(inventory.get_equipped(&"weapon") != null, "UI equips item")
	var combatant := player.get_node("ActorCombatant") as ActorCombatant
	check(combatant.attack_bonus() == float(item.modifiers.get("attack", 0)), "equipment affects real actor stats")
	check(click(panel, "卸下"), "unequip button connected")
	check(inventory.get_equipped(&"weapon") == null and inventory.has_instance(item.instance_id), "unequip preserves item")
	click(panel, caption)
	click(panel, "丢弃")
	check(not inventory.has_instance(item.instance_id), "discard removes exactly selected item")
	await key(KEY_I)
	await frames(8)
	check(not inventory.has_instance(item.instance_id), "discard is not immediately recollected")
	var origin := player.global_position
	player.global_position += Vector2(35, 0)
	await frames(5)
	player.global_position = origin
	await frames(5)
	check(inventory.has_instance(item.instance_id), "leave and return recollects same item")
	await key(KEY_I)
	click(panel, caption)
	click(panel, "装备")
	await key(KEY_I)
	progression.grant_experience(50)
	check(click(level.get_node("HintLayer/LevelUpPanel"), "+5 最大生命"), "real level-up button connected")
	check(combatant.max_health() == 105, "level-up UI changes maximum health")
	var before_inventory := inventory.get_snapshot()
	var before_progression := progression.get_snapshot()
	check(level.go_to_level(&"forest"), "transition to forest")
	await frames()
	level = current_scene as LevelFlow
	player = level.get_node("Player") as PlayerController
	inventory = player.get_node("ActorInventory") as ActorInventory
	progression = player.get_node("ActorProgression") as ActorProgression
	check(inventory.get_snapshot() == before_inventory, "cross-map equipment and bag preserved")
	check(progression.get_snapshot() == before_progression, "cross-map growth preserved")
	check(level.go_to_level(&"village"), "return village")
	await frames()
	level = current_scene as LevelFlow
	player = level.get_node("Player") as PlayerController
	inventory = player.get_node("ActorInventory") as ActorInventory
	progression = player.get_node("ActorProgression") as ActorProgression
	combatant = player.get_node("ActorCombatant") as ActorCombatant
	check(inventory.get_snapshot() == before_inventory and progression.get_snapshot() == before_progression, "village preserves equipment and growth")
	check(combatant.get_health() == 105, "village refills AFTER restored max health")
	player.global_position = level.get_node("QuestGiver").global_position + Vector2(25, 0)
	await frames()
	await key(KEY_E)
	for i in 3:
		GameSession.current.register_enemy_kill()
	var xp_before := int(progression.get_snapshot()["xp_in_level"])
	await key(KEY_E)
	check(GameSession.current.reward_paid and int(progression.get_snapshot()["xp_in_level"]) == xp_before + 50, "E hands in quest and grants 50 XP")
	var rewarded := progression.get_snapshot()
	await key(KEY_E)
	check(progression.get_snapshot() == rewarded, "repeat hand-in cannot grant extra XP")
	check(level.save_now(SAVE).is_empty(), "save via production flow to isolated file")
	inventory.restore_from_snapshot({})
	progression.grant_experience(200)
	check(level.load_now(SAVE) == SaveService.LoadStatus.OK, "load via production flow")
	await frames()
	level = current_scene as LevelFlow
	player = level.get_node("Player") as PlayerController
	inventory = player.get_node("ActorInventory") as ActorInventory
	progression = player.get_node("ActorProgression") as ActorProgression
	check(inventory.get_snapshot() == before_inventory and progression.get_snapshot() == rewarded, "loaded village restores equipment and growth")
	check(GameSession.current.reward_paid, "loaded completed quest stays paid")
	# Full-bag failure must leave the ground drop intact.
	var catalog := ItemCatalog.build()
	for i in 20:
		inventory.try_add(catalog.roll(&"leather_cap", "fill-%d" % i))
	var extra := catalog.roll(&"worn_ring", "extra-full")
	pickup = load("res://scenes/item_pickup.tscn").instantiate() as ItemPickup
	level.add_child(pickup)
	pickup.global_position = player.global_position
	pickup.setup(extra, inventory)
	await frames(8)
	check(is_instance_valid(pickup) and not inventory.has_instance(extra.instance_id), "full bag leaves dropped item in world")
	if DisplayServer.get_name() != "headless":
		await key(KEY_I)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://work/v02_inventory.png")
	paused = false
	level.queue_free()
	await frames()
	print("V02_GAMEPLAY: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
