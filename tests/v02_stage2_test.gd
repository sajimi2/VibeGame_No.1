extends SceneTree
## v0.2 阶段 2 检查：两种近战（小刀 / 大砍刀）的出招移动规则、武器决定招式、一次性领取（开局小刀、村庄
## 武器架）在换图与存读档后不重复，以及敌人攻击行为未被改动。
##
## 移速与位移只在"该物理步处于对应状态"时断言，不假设"第 N 帧一定是 ACTIVE"。帧率无关，与
## docs/DESIGN.md「所有时间由物理 delta 累积，不依赖帧数」一致。

var checks := 0
var failures := 0
const SAVE := "res://work/v02_stage2_save.json"
const RACK_FLAG := &"village_cleaver"

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

# --- helpers ---------------------------------------------------------------------------------

## Runs one committed attack and returns, for every physics step in which the attack owned the body,
## the state at that step together with the velocity the body actually applied in it.
func sample_attack(port: ActorActionPort, body: CharacterBody2D, action: ActorCommandPort.Action, max_frames := 150) -> Array[Dictionary]:
	var samples: Array[Dictionary] = []
	port.request_action(action)
	for i in max_frames:
		await physics_frame
		var state := port.get_state()
		if state == ActorCommandPort.State.IDLE or state == ActorCommandPort.State.MOVE:
			if not samples.is_empty():
				break
			continue
		samples.append({"state": state, "velocity": body.velocity})
	return samples

static func speeds_for(samples: Array[Dictionary], state: ActorCommandPort.State) -> Array[float]:
	var speeds: Array[float] = []
	for sample in samples:
		if int(sample["state"]) == int(state):
			speeds.append((sample["velocity"] as Vector2).length())
	return speeds

static func all_close(speeds: Array[float], expected: float, tolerance: float) -> bool:
	if speeds.is_empty():
		return false
	for speed in speeds:
		if absf(speed - expected) > tolerance:
			return false
	return true

static func describe(speeds: Array[float]) -> String:
	var parts: Array[String] = []
	for speed in speeds:
		parts.append("%.1f" % speed)
	return "[%s]" % ", ".join(parts)

## Median-ish summary of a state's velocities, for the direction checks.
static func average_for(samples: Array[Dictionary], state: ActorCommandPort.State) -> Vector2:
	var total := Vector2.ZERO
	var count := 0
	for sample in samples:
		if int(sample["state"]) == int(state):
			total += sample["velocity"] as Vector2
			count += 1
	return total / float(count) if count > 0 else Vector2.ZERO

func count_definition(inventory: ActorInventory, definition_id: StringName) -> int:
	var count := 0
	var snapshot := inventory.get_snapshot()
	for entry in snapshot.get("bag", []):
		var bag_entry: Dictionary = entry
		if not bag_entry.is_empty() and String(bag_entry.get("definition_id", "")) == String(definition_id):
			count += 1
	for slot in (snapshot.get("equipment", {}) as Dictionary).keys():
		var equipped: Dictionary = snapshot["equipment"][slot]
		if not equipped.is_empty() and String(equipped.get("definition_id", "")) == String(definition_id):
			count += 1
	return count

func has_label_starting_with(node: Node, prefix: String) -> bool:
	for child in node.get_children():
		if child is Label and (child as Label).text.begins_with(prefix):
			return true
	return false

func first_free_bag_index(inventory: ActorInventory) -> int:
	var bag: Array = inventory.get_snapshot().get("bag", [])
	for index in bag.size():
		if (bag[index] as Dictionary).is_empty():
			return index
	return -1

## Measured attacks must not depend on how much stamina the earlier checks spent. Stamina accounting
## has its own coverage (t02_combat_test); this suite is about where the body goes.
func refill(combatant: ActorCombatant) -> void:
	combatant.set_vitals(combatant.max_health(), combatant.max_stamina())

# --- main ------------------------------------------------------------------------------------

func run() -> void:
	await frames()
	GameSession.current = null
	var level := load("res://scenes/level_village.tscn").instantiate() as LevelFlow
	root.add_child(level)
	current_scene = level
	await frames()
	var session := GameSession.current
	var player := level.get_node("Player") as PlayerController
	var inventory := player.get_node("ActorInventory") as ActorInventory
	var combatant := player.get_node("ActorCombatant") as ActorCombatant
	var port := player.get_node("ActorActionPort") as ActorActionPort
	var tuning := load("res://data/player_tuning.tres") as ActorTuning
	var knife_profile := load("res://data/weapons/knife.tres") as WeaponProfile
	var cleaver_profile := load("res://data/weapons/cleaver.tres") as WeaponProfile
	var rack := level.get_node("WeaponRack") as WeaponRack

	_check_data(knife_profile, cleaver_profile, tuning)
	_check_starting_kit(session, inventory, level)

	# --- knife: full locomotion through the whole attack --------------------------------------
	player.test_intent_override = true
	player.test_intent_move = Vector2.RIGHT
	player.test_intent_aim = Vector2.RIGHT
	await frames(2)
	var samples := await sample_attack(port, player, ActorCommandPort.Action.LIGHT_ATTACK)
	var windup := speeds_for(samples, ActorCommandPort.State.WINDUP)
	var active := speeds_for(samples, ActorCommandPort.State.ACTIVE)
	var recovery := speeds_for(samples, ActorCommandPort.State.RECOVERY)
	check(not windup.is_empty() and not active.is_empty() and not recovery.is_empty(),
		"knife light attack was observed in all three phases %s %s %s" % [describe(windup), describe(active), describe(recovery)])
	check(all_close(windup, tuning.move_speed, 1.0), "knife keeps full speed in WINDUP %s" % describe(windup))
	check(all_close(active, tuning.move_speed, 1.0), "knife keeps full speed in ACTIVE %s" % describe(active))
	check(all_close(recovery, tuning.move_speed, 1.0), "knife keeps full speed in RECOVERY %s" % describe(recovery))

	# --- cleaver: 60% locomotion, no forward slide before the damage window -------------------
	check(inventory.try_equip_direct(ItemCatalog.build().roll(&"great_cleaver", "test-cleaver"), ActorInventory.SLOT_WEAPON),
		"great cleaver equips directly into the weapon slot")
	var cleaver_speed := tuning.move_speed + combatant.equipment_modifier(ActorCombatant.STAT_MOVE_SPEED)
	check(absf(cleaver_speed - (tuning.move_speed - 6.0)) < 0.01,
		"the cleaver's own move penalty is applied once (%.1f)" % cleaver_speed)
	refill(combatant)
	samples = await sample_attack(port, player, ActorCommandPort.Action.LIGHT_ATTACK)
	windup = speeds_for(samples, ActorCommandPort.State.WINDUP)
	active = speeds_for(samples, ActorCommandPort.State.ACTIVE)
	recovery = speeds_for(samples, ActorCommandPort.State.RECOVERY)
	var expected_scale := cleaver_profile.light_attack.move_speed_scale
	var light_strike_speed := cleaver_profile.light_attack.strike_advance_pixels / cleaver_profile.light_attack.active_seconds
	check(all_close(windup, cleaver_speed * expected_scale, 1.0), "cleaver WINDUP runs at %.0f%% speed %s" % [expected_scale * 100.0, describe(windup)])
	check(all_close(active, cleaver_speed * expected_scale + light_strike_speed, 1.0),
		"cleaver ACTIVE adds the strike step on top of the %.0f%% walk (expected %.1f) %s" % [expected_scale * 100.0, cleaver_speed * expected_scale + light_strike_speed, describe(active)])
	check(all_close(recovery, cleaver_speed * expected_scale, 1.0), "cleaver RECOVERY runs at %.0f%% speed %s" % [expected_scale * 100.0, describe(recovery)])

	# --- cleaver: the strike step is ACTIVE-only and direction-locked -------------------------
	player.test_intent_move = Vector2.ZERO
	player.test_intent_aim = Vector2.RIGHT
	await frames(2)
	refill(combatant)
	samples = await sample_attack(port, player, ActorCommandPort.Action.LIGHT_ATTACK)
	windup = speeds_for(samples, ActorCommandPort.State.WINDUP)
	recovery = speeds_for(samples, ActorCommandPort.State.RECOVERY)
	var strike_velocity := average_for(samples, ActorCommandPort.State.ACTIVE)
	var expected_strike := cleaver_profile.light_attack.strike_advance_pixels / cleaver_profile.light_attack.active_seconds
	check(all_close(windup, 0.0, 1.0), "no movement at all during a standing cleaver windup %s" % describe(windup))
	check(all_close(recovery, 0.0, 1.0), "the strike step has ended by RECOVERY %s" % describe(recovery))
	check(absf(strike_velocity.x - expected_strike) <= 1.0, "light cleaver steps forward %.0f px/s on the locked axis (got %.1f)" % [expected_strike, strike_velocity.x])
	check(absf(strike_velocity.y) <= 0.5, "the strike step adds nothing sideways (%.1f)" % strike_velocity.y)

	refill(combatant)
	samples = await sample_attack(port, player, ActorCommandPort.Action.HEAVY_ATTACK)
	var heavy_strike := average_for(samples, ActorCommandPort.State.ACTIVE)
	var expected_heavy_strike := cleaver_profile.heavy_attack.strike_advance_pixels / cleaver_profile.heavy_attack.active_seconds
	check(absf(heavy_strike.x - expected_heavy_strike) <= 1.0,
		"heavy cleaver steps forward %.0f px/s, further than light (got %.1f)" % [expected_heavy_strike, heavy_strike.x])
	check(cleaver_profile.heavy_attack.strike_advance_pixels > cleaver_profile.light_attack.strike_advance_pixels,
		"the heavy strike covers more ground than the light one")

	# --- the weapon decides the moves ----------------------------------------------------------
	var started: Array[AttackSpec] = []
	port.attack_started.connect(func(spec: AttackSpec) -> void: started.append(spec))
	var light_id := ActorCommandPort.Action.LIGHT_ATTACK
	var heavy_id := ActorCommandPort.Action.HEAVY_ATTACK
	refill(combatant)
	await sample_attack(port, player, light_id)
	refill(combatant)
	await sample_attack(port, player, heavy_id)
	check(started.size() == 2 and started[0] == cleaver_profile.light_attack and started[1] == cleaver_profile.heavy_attack,
		"an equipped cleaver swaps in its own light and heavy moves (%d started)" % started.size())

	# --- unarmed falls back to the tuning's fist moves ------------------------------------------
	refill(combatant)
	var equipped_weapon := inventory.get_equipped(ActorInventory.SLOT_WEAPON)
	var free_index := first_free_bag_index(inventory)
	check(equipped_weapon != null and free_index >= 0, "there is an equipped weapon and a free bag slot")
	check(inventory.try_unequip_to_slot(equipped_weapon.instance_id, free_index), "the weapon slot can be emptied")
	check(inventory.get_equipped(ActorInventory.SLOT_WEAPON) == null, "nothing is equipped after unequipping")
	check(combatant.equipped_weapon_profile() == null, "an empty weapon slot reports no weapon profile")
	started.clear()
	var swing_started := port.request_action(light_id)
	await frames(1)
	check(swing_started and started.size() == 1 and started[0] == tuning.light_attack,
		"unarmed light attack falls back to the tuning's fist move (damage %.0f)" % tuning.light_attack.damage)
	await frames(90)
	check(inventory.try_equip_direct(ItemCatalog.build().roll(&"great_cleaver", "test-cleaver-2"), ActorInventory.SLOT_WEAPON),
		"cleaver re-equipped for the remaining checks")

	# --- the strike step still respects walls --------------------------------------------------
	player.test_intent_move = Vector2.ZERO
	player.test_intent_aim = Vector2.LEFT
	player.global_position = Vector2(44, 270)
	await frames(3)
	refill(combatant)
	var before_x := player.global_position.x
	samples = await sample_attack(port, player, ActorCommandPort.Action.HEAVY_ATTACK)
	var after_x := player.global_position.x
	check(before_x > 43.0 and before_x < 45.0, "player staged next to the left wall (x=%.1f)" % before_x)
	check(not samples.is_empty(), "the wall-probing heavy attack actually ran")
	check(after_x >= 39.0 and after_x <= 41.5,
		"the heavy strike stops against the wall (x=%.1f, wall face 32 + body radius 8)" % after_x)
	check(after_x > 32.0, "the strike step did not push the body into the wall")
	player.global_position = Vector2(200, 270)
	player.test_intent_move = Vector2.ZERO
	player.test_intent_aim = Vector2.RIGHT
	await frames(3)

	# --- a real hit uses the weapon's damage ---------------------------------------------------
	var dummy := load("res://scenes/training_dummy.tscn").instantiate() as CharacterBody2D
	level.add_child(dummy)
	dummy.global_position = player.global_position + Vector2(26, 0)
	await frames(2)
	var dummy_combatant := dummy.get_node("ActorCombatant") as ActorCombatant
	var dummy_before := dummy_combatant.get_health()
	samples = await sample_attack(port, player, ActorCommandPort.Action.HEAVY_ATTACK)
	var dealt := dummy_before - dummy_combatant.get_health()
	var expected_damage := cleaver_profile.heavy_attack.damage + combatant.attack_bonus()
	check(absf(dealt - expected_damage) <= 0.01,
		"heavy cleaver lands its own damage plus equipment bonus (%.0f dealt, %.0f expected)" % [dealt, expected_damage])
	check(dealt > cleaver_profile.light_attack.damage, "a landed cleaver heavy hits harder than the light move")
	dummy.queue_free()
	await frames(2)

	# --- enemies are untouched ------------------------------------------------------------------
	await _check_enemy_behaviour(level, port, player)

	# --- the village rack hands the cleaver over exactly once -----------------------------------
	level.restart()
	await frames(2)
	player.test_intent_override = false
	player.global_position = rack.global_position + Vector2(20, 0)
	await frames(2)
	check(rack.is_player_inside(), "standing next to the rack is detected by distance")
	check(rack.prompt_text().begins_with("E 领取大砍刀"), "the rack prompts for the cleaver (%s)" % rack.prompt_text())
	check(not session.has_claimed(RACK_FLAG), "the rack starts unclaimed on a new run")
	await key(KEY_E)
	check(session.has_claimed(RACK_FLAG), "pressing E records the claim in the session")
	check(String(inventory.get_equipped(ActorInventory.SLOT_WEAPON).definition_id) == "great_cleaver",
		"the claimed cleaver goes straight into the weapon slot")
	check(count_definition(inventory, &"hunting_knife") == 1, "the displaced knife is kept, not deleted")
	check(not rack.prompt_text().begins_with("E 领取"), "the rack stops offering the weapon once taken (%s)" % rack.prompt_text())
	var count_before := count_definition(inventory, &"great_cleaver")
	await key(KEY_E)
	check(count_definition(inventory, &"great_cleaver") == count_before, "a second press hands out no second cleaver")
	check(not rack.claim(), "claim() is a no-op once the flag is set")
	check(level.equipped_weapon_label().begins_with("武器：大砍刀"), "the HUD line names the equipped weapon (%s)" % level.equipped_weapon_label())
	check(has_label_starting_with(level.get_node("HintLayer"), "武器："), "the HUD actually renders a weapon line")

	# --- claims survive a level change ----------------------------------------------------------
	var before_snapshot := inventory.get_snapshot()
	check(level.go_to_level(&"forest"), "transition to the forest")
	await frames(2)
	level = current_scene as LevelFlow
	player = level.get_node("Player") as PlayerController
	inventory = player.get_node("ActorInventory") as ActorInventory
	check(inventory.get_snapshot() == before_snapshot, "the claimed cleaver crosses the level boundary")
	check(GameSession.current.has_claimed(RACK_FLAG), "the claim flag crosses the level boundary")
	check(level.go_to_level(&"village"), "return to the village")
	await frames(2)
	level = current_scene as LevelFlow
	player = level.get_node("Player") as PlayerController
	inventory = player.get_node("ActorInventory") as ActorInventory
	rack = level.get_node("WeaponRack") as WeaponRack
	check(rack.is_claimed(), "the rack is still empty after leaving and returning")
	check(String(inventory.get_equipped(ActorInventory.SLOT_WEAPON).definition_id) == "great_cleaver",
		"the cleaver is still equipped in the village")

	# --- claims survive a save/load round -------------------------------------------------------
	## The count is compared against the pre-save state rather than a fixed number: the checks above
	## deliberately rolled extra cleavers, and this section is about nothing being duplicated.
	var cleavers_before := count_definition(inventory, &"great_cleaver")
	check(level.save_now(SAVE).is_empty(), "save now writes the run to an isolated file")
	inventory.restore_from_snapshot({})
	GameSession.current.claimed.clear()
	check(count_definition(inventory, &"great_cleaver") == 0, "the inventory really was emptied before loading")
	check(level.load_now(SAVE) == SaveService.LoadStatus.OK, "load via the production flow")
	await frames(2)
	level = current_scene as LevelFlow
	player = level.get_node("Player") as PlayerController
	inventory = player.get_node("ActorInventory") as ActorInventory
	rack = level.get_node("WeaponRack") as WeaponRack
	check(GameSession.current.has_claimed(RACK_FLAG), "the claim flag is restored from the save")
	check(count_definition(inventory, &"great_cleaver") == cleavers_before,
		"loading restores the same number of cleavers with none added (%d -> %d)" % [cleavers_before, count_definition(inventory, &"great_cleaver")])
	check(count_definition(inventory, &"hunting_knife") == 1, "loading does not hand out the starting knife again")
	check(inventory.get_equipped(ActorInventory.SLOT_WEAPON) != null
		and String(inventory.get_equipped(ActorInventory.SLOT_WEAPON).definition_id) == "great_cleaver",
		"the loaded village still has the cleaver equipped")
	check(rack.is_claimed() and rack.prompt_text().contains("已取走"), "the loaded rack knows it was emptied")

	# --- equipment cannot change mid-swing ------------------------------------------------------
	var panel := level.get_node("HintLayer/InventoryPanel") as InventoryPanel
	player = level.get_node("Player") as PlayerController
	inventory = player.get_node("ActorInventory") as ActorInventory
	port = player.get_node("ActorActionPort") as ActorActionPort
	var knife_bag: Array = inventory.get_snapshot().get("bag", [])
	var knife_caption := ""
	for index in knife_bag.size():
		var entry: Dictionary = knife_bag[index]
		if not entry.is_empty() and String(entry.get("definition_id", "")) == "hunting_knife":
			knife_caption = ("★" if int(entry.get("rarity", 0)) == 1 else "") + "猎刀"
	check(not knife_caption.is_empty(), "the knife is in the bag with a caption the UI can show (%s)" % knife_caption)
	port.request_action(ActorCommandPort.Action.HEAVY_ATTACK)
	check(port.is_action_in_progress(), "a swing really is in progress")
	await key(KEY_I)
	check(level.is_inventory_open(), "the bag opens mid-swing")
	check(click(panel, knife_caption), "the knife can be selected mid-swing")
	check(click(panel, "装备"), "the equip button is pressed mid-swing")
	check(String(inventory.get_equipped(ActorInventory.SLOT_WEAPON).definition_id) == "great_cleaver",
		"a mid-swing equip is refused, the cleaver stays equipped")
	await key(KEY_I)
	paused = false
	await frames(2)

	level.queue_free()
	await frames()
	print("V02_STAGE2: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

# --- sections ---------------------------------------------------------------------------------

## The data layer: the two weapons really are different, and nothing else changed.
func _check_data(knife: WeaponProfile, cleaver: WeaponProfile, tuning: ActorTuning) -> void:
	check(knife.light_attack != null and knife.heavy_attack != null, "the knife profile carries both moves")
	check(cleaver.light_attack != null and cleaver.heavy_attack != null, "the cleaver profile carries both moves")
	check(knife.light_attack.move_mode == AttackSpec.MoveMode.FULL_SPEED
		and knife.heavy_attack.move_mode == AttackSpec.MoveMode.FULL_SPEED,
		"every knife move keeps full locomotion")
	check(cleaver.light_attack.move_mode == AttackSpec.MoveMode.SCALED
		and cleaver.heavy_attack.move_mode == AttackSpec.MoveMode.SCALED,
		"every cleaver move is a committed walk")
	check(absf(cleaver.light_attack.move_speed_scale - 0.6) < 0.001 and absf(cleaver.heavy_attack.move_speed_scale - 0.6) < 0.001,
		"the cleaver walks at 60% speed")
	check(knife.light_attack.strike_advance_pixels == 0.0 and knife.heavy_attack.strike_advance_pixels == 0.0,
		"the knife never slides forward during its strike")
	check(cleaver.heavy_attack.damage > knife.heavy_attack.damage, "the cleaver's heavy hit is the harder one")
	check(tuning.light_attack.move_mode == AttackSpec.MoveMode.STATIONARY
		and tuning.heavy_attack.move_mode == AttackSpec.MoveMode.STATIONARY,
		"the unarmed fallback stays planted")
	var catalog := ItemCatalog.build()
	check(catalog.ids().size() == 14, "the catalog now holds 14 definitions (got %d)" % catalog.ids().size())
	for definition_id in [&"hunting_knife", &"great_cleaver", &"bandit_cleaver", &"woodcutter_axe", &"rusty_pick"]:
		var definition := catalog.definition(definition_id)
		check(definition != null and definition.weapon_profile != null,
			"weapon '%s' references a weapon profile" % definition_id)
	for definition_id in [&"leather_cap", &"iron_helm", &"chainmail", &"worn_ring"]:
		check(catalog.definition(definition_id).weapon_profile == null,
			"non-weapon '%s' has no weapon profile" % definition_id)
	check(knife.spec_for(true, tuning.heavy_attack) == knife.heavy_attack, "spec_for picks the weapon's own move")
	var empty := WeaponProfile.new()
	check(empty.spec_for(false, tuning.light_attack) == tuning.light_attack, "a profile without a move keeps the fallback")
	## Enemy specs must keep their pre-stage-2 defaults, or every enemy's attack would start moving.
	for path in ["res://data/bandit_attack.tres", "res://data/archer_shot.tres", "res://data/beast_lunge.tres", "res://data/boss_attack.tres"]:
		var spec := load(path) as AttackSpec
		check(spec.move_mode == AttackSpec.MoveMode.STATIONARY and spec.strike_advance_pixels == 0.0 and spec.move_speed_scale == 1.0,
			"%s keeps the stationary defaults" % path.get_file())
	var lunge := load("res://data/beast_lunge.tres") as AttackSpec
	check(lunge.charge_distance_pixels > 0.0, "the beast lunge still carries its charge distance")

func _check_starting_kit(session: GameSession, inventory: ActorInventory, level: LevelFlow) -> void:
	var equipped := inventory.get_equipped(ActorInventory.SLOT_WEAPON)
	check(equipped != null and String(equipped.definition_id) == "hunting_knife",
		"a new run starts with the hunting knife equipped")
	check(session.has_claimed(LevelFlow.CLAIM_STARTING_KIT), "the starting kit is recorded in the session")
	check(count_definition(inventory, &"hunting_knife") == 1, "the starting knife exists exactly once")
	check(level.equipped_weapon_label().contains("猎刀"), "the HUD line starts on the knife (%s)" % level.equipped_weapon_label())
	level.restart()
	check(count_definition(inventory, &"hunting_knife") == 1, "retrying the level does not hand out a second knife")

## Enemy attacks must behave exactly as before stage 2: a committed attack pins the body in place.
func _check_enemy_behaviour(level: LevelFlow, _port: ActorActionPort, _player: PlayerController) -> void:
	var bandit := load("res://scenes/bandit.tscn").instantiate() as CharacterBody2D
	## The AI is switched off so only the action port is under test.
	bandit.set_physics_process(false)
	level.add_child(bandit)
	bandit.global_position = Vector2(760, 200)
	await frames(2)
	var bandit_port := bandit.get_node("ActorActionPort") as ActorActionPort
	bandit_port.set_intent(Vector2.RIGHT, Vector2.RIGHT, false)
	check(bandit_port.request_action(ActorCommandPort.Action.LIGHT_ATTACK), "the bandit's attack starts")
	var moved := false
	var saw_attack := false
	for i in 90:
		await physics_frame
		var state := bandit_port.get_state()
		if state in [ActorCommandPort.State.WINDUP, ActorCommandPort.State.ACTIVE, ActorCommandPort.State.RECOVERY]:
			saw_attack = true
			if bandit_port.get_velocity() != Vector2.ZERO:
				moved = true
		elif saw_attack:
			break
	check(saw_attack, "the bandit attack was observed")
	check(not moved, "an enemy attack still keeps the body planted (unchanged behaviour)")
	bandit.queue_free()
	await frames(2)
