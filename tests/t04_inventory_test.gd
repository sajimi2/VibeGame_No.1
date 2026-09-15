extends SceneTree
## T04 acceptance tests: inventory capacity, atomic swaps, equipment stats without drift,
## seeded quality rolls, and drop/full-bag behaviour.
##
## Runnable with:
##   godot --headless --path <project> --script res://tests/t05_inventory_test.gd
## Exits 0 when every case passes, 1 otherwise.

const ARENA_SCENE := "res://scenes/arena.tscn"

var _failures: Array[String] = []
var _checks := 0
var _catalog: ItemCatalog
var _sequence := 0

func _initialize() -> void:
	_run()

func _run() -> void:
	print("=== T04 inventory/equipment tests ===")
	await physics_frame
	_catalog = ItemCatalog.build()
	await _test_catalog_completeness()
	await _test_capacity_and_duplicates()
	await _test_slot_mismatch_is_inert()
	await _test_full_bag_swap_is_atomic()
	await _test_equip_unequip_does_not_drift()
	await _test_fine_rolls_are_seeded_and_isolated()
	await _test_full_bag_pickup_leaves_the_drop()
	await _test_equipment_changes_damage_and_armor()
	print("--- checks=%d failures=%d" % [_checks, _failures.size()])
	if _failures.is_empty():
		print("T04_INVENTORY_TESTS: PASS")
		quit(0)
	else:
		for failure in _failures:
			print("T04_INVENTORY_TESTS: FAIL %s" % failure)
		quit(1)

# --- harness -------------------------------------------------------------------------------

func _check(condition: bool, message: String) -> bool:
	_checks += 1
	if not condition:
		_failures.append(message)
		print("  [FAIL] %s" % message)
	return condition

func _check_close(actual: float, expected: float, tolerance: float, message: String) -> bool:
	return _check(absf(actual - expected) <= tolerance, "%s (actual=%.3f expected=%.3f tol=%.3f)" % [message, actual, expected, tolerance])

func _step() -> void:
	await physics_frame

func _steps(count: int) -> void:
	for _i in count:
		await _step()

func _new_inventory() -> ActorInventory:
	var inventory := ActorInventory.new()
	inventory.set_catalog(_catalog)
	return inventory

func _roll(definition_id: StringName) -> ItemInstance:
	_sequence += 1
	return _catalog.roll(definition_id, "test-%d" % _sequence)

func _snapshot_count(inventory: ActorInventory) -> int:
	var snapshot := inventory.get_snapshot()
	var total := 0
	for entry in snapshot.get("bag", []):
		if not (entry as Dictionary).is_empty():
			total += 1
	for slot in (snapshot.get("equipment", {}) as Dictionary).keys():
		var entry: Dictionary = snapshot.get("equipment", {})[slot]
		if not entry.is_empty():
			total += 1
	return total

# --- cases ---------------------------------------------------------------------------------

func _test_catalog_completeness() -> void:
	print("[test] the catalog holds twelve distinct definitions")
	_check(_catalog.ids().size() == 12, "the catalog must hold 12 definitions (got %d)" % _catalog.ids().size())
	var seen := {}
	for id in ItemCatalog.default_ids():
		_check(_catalog.has_definition(id), "definition '%s' must resolve" % id)
		var definition := _catalog.definition(id)
		if definition == null:
			continue
		_check(not definition.display_name.is_empty(), "%s must have a display name" % id)
		_check(not definition.base_modifiers.is_empty(), "%s must modify something" % id)
		seen[id] = true
	_check(seen.size() == 12, "all twelve ids must be distinct (got %d)" % seen.size())

func _test_capacity_and_duplicates() -> void:
	print("[test] bag capacity and unique instance ids")
	var inventory := _new_inventory()
	var accepted := 0
	for index in ActorInventory.BAG_CAPACITY:
		if inventory.try_add(_roll(&"rusty_pick")):
			accepted += 1
	_check(accepted == ActorInventory.BAG_CAPACITY, "the bag must accept exactly %d items (got %d)" % [ActorInventory.BAG_CAPACITY, accepted])
	_check(inventory.is_bag_full(), "the bag must report full")
	_check(inventory.bag_used() == ActorInventory.BAG_CAPACITY, "bag_used must count the filled slots")

	## One more must be refused with no mutation.
	var before := _snapshot_count(inventory)
	var extra := _roll(&"rusty_pick")
	_check(inventory.try_add(extra) == false, "a full bag must refuse an add")
	_check(_snapshot_count(inventory) == before, "a refused add must not change the item count")

	## A duplicate instance id must be refused even with room.
	var roomy := _new_inventory()
	var first := _roll(&"leather_cap")
	_check(roomy.try_add(first), "the first add must succeed")
	var duplicate := _roll(&"leather_cap")
	duplicate.instance_id = first.instance_id
	_check(roomy.try_add(duplicate) == false, "a duplicate instance id must be refused")
	_check(_snapshot_count(roomy) == 1, "a refused duplicate must not be stored")

	## An unknown definition must be refused.
	var unknown := _roll(&"rusty_pick")
	unknown.definition_id = &"not_a_real_item"
	_check(roomy.try_add(unknown) == false, "an unknown definition must be refused")

func _test_slot_mismatch_is_inert() -> void:
	print("[test] a slot/type mismatch changes nothing")
	var inventory := _new_inventory()
	var helm := _roll(&"iron_helm")
	inventory.try_add(helm)
	var before := inventory.get_snapshot()
	var count_before := _snapshot_count(inventory)

	_check(inventory.try_equip(helm.instance_id, ActorInventory.SLOT_BODY) == false, "a head item must not fit the body slot")
	_check(inventory.try_equip(helm.instance_id, &"not_a_slot") == false, "an unknown slot must be refused")
	_check(inventory.try_equip("no-such-instance", ActorInventory.SLOT_HEAD) == false, "an unknown instance must be refused")
	_check(_snapshot_count(inventory) == count_before, "a refused equip must not change the item count")
	_check(inventory.get_equipped(ActorInventory.SLOT_BODY) == null, "the wrong slot must stay empty")
	_check(JSON.stringify(before) == JSON.stringify(inventory.get_snapshot()), "a refused equip must leave the snapshot identical")

	## The correct slot must work.
	_check(inventory.try_equip(helm.instance_id, ActorInventory.SLOT_HEAD), "a head item must fit the head slot")
	_check(inventory.get_equipped(ActorInventory.SLOT_HEAD) != null, "the head slot must now hold the item")
	_check(inventory.bag_used() == 0, "equipping from the bag must free the bag slot")

func _test_full_bag_swap_is_atomic() -> void:
	print("[test] swapping equipment while the bag is completely full")
	var inventory := _new_inventory()
	## Equip a helm, then fill the bag to capacity.
	var first_helm := _roll(&"iron_helm")
	inventory.try_add(first_helm)
	inventory.try_equip(first_helm.instance_id, ActorInventory.SLOT_HEAD)
	for _i in ActorInventory.BAG_CAPACITY:
		inventory.try_add(_roll(&"rusty_pick"))
	_check(inventory.is_bag_full(), "the bag must be full before the swap")
	_check(inventory.get_equipped(ActorInventory.SLOT_HEAD) != null, "the helm must be equipped")

	## The tight case: a bag item moves into the occupied equipment slot while the bag is full. The
	## displaced helm must land in that bag position, so the count cannot change.
	var cap := _roll(&"leather_cap")
	inventory.try_add(cap)
	## The bag is full, so the cap cannot be added at all - that must be refused cleanly.
	_check(not inventory.has_instance(cap.instance_id), "a full bag must refuse the cap")

	var before_count := _snapshot_count(inventory)
	var bag_before := inventory.bag_used()
	## Now swap using an item that IS in the bag.
	var pick_id := ""
	var bag: Array = inventory.get_snapshot().get("bag", [])
	for entry in bag:
		var dictionary := entry as Dictionary
		if String(dictionary.get("definition_id", "")) == "rusty_pick":
			pick_id = String(dictionary.get("instance_id", ""))
			break
	## A pick is a weapon, so it must go to the weapon slot rather than the head slot.
	var helm_id := inventory.get_equipped(ActorInventory.SLOT_HEAD).instance_id
	_check(inventory.try_equip(pick_id, ActorInventory.SLOT_HEAD) == false, "a weapon must not fit the head slot")
	_check(_snapshot_count(inventory) == before_count, "a refused swap must not change the count")

	## The head slot is occupied, so re-equipping the helm from its own slot is a no-op swap.
	_check(inventory.try_equip(helm_id, ActorInventory.SLOT_HEAD), "re-equipping from the slot must succeed")
	_check(_snapshot_count(inventory) == before_count, "a self-swap must keep the count constant")
	_check(inventory.bag_used() == bag_before, "a self-swap must keep the bag usage constant")

	## Freeing one bag slot, then swapping, must still be atomic.
	var weapon_id := ""
	for entry in inventory.get_snapshot().get("bag", []):
		var dictionary := entry as Dictionary
		if String(dictionary.get("definition_id", "")) == "rusty_pick":
			weapon_id = String(dictionary.get("instance_id", ""))
			break
	var weapon := _roll(&"bandit_cleaver")
	## Replace a pick with the cleaver by equipping the pick first is a weapon-to-weapon swap.
	_check(inventory.try_equip(weapon_id, ActorInventory.SLOT_WEAPON), "the pick must equip to the weapon slot")
	_check(_snapshot_count(inventory) == before_count, "equipping from a full bag must keep the count constant")
	_check(inventory.bag_used() == bag_before - 1, "equipping from the bag must free exactly one slot")

func _test_equip_unequip_does_not_drift() -> void:
	print("[test] ten equip/unequip cycles leave the stats identical")
	var inventory := _new_inventory()
	var body := _roll(&"chainmail")
	var officer := _roll(&"veteran_medal")
	inventory.try_add(body)
	inventory.try_add(officer)
	inventory.try_equip(body.instance_id, ActorInventory.SLOT_BODY)
	inventory.try_equip(officer.instance_id, ActorInventory.SLOT_ACCESSORY)
	var baseline := inventory.equipped_modifiers()

	for cycle in 10:
		var body_id := inventory.get_equipped(ActorInventory.SLOT_BODY).instance_id
		var officer_id := inventory.get_equipped(ActorInventory.SLOT_ACCESSORY).instance_id
		_check(inventory.try_unequip_to_slot(body_id, 5), "cycle %d: unequip body must succeed" % cycle)
		_check(inventory.try_unequip_to_slot(officer_id, 6), "cycle %d: unequip accessory must succeed" % cycle)
		_check(inventory.try_equip(body_id, ActorInventory.SLOT_BODY), "cycle %d: re-equip body must succeed" % cycle)
		_check(inventory.try_equip(officer_id, ActorInventory.SLOT_ACCESSORY), "cycle %d: re-equip accessory must succeed" % cycle)

	var after := inventory.equipped_modifiers()
	for key in baseline.keys():
		_check_close(float(after.get(key, 0.0)), float(baseline[key]), 0.0001, "modifier '%s' must not drift over ten cycles" % key)
	_check(after.size() == baseline.size(), "the modifier set must not grow over ten cycles")

func _test_fine_rolls_are_seeded_and_isolated() -> void:
	print("[test] quality rolls are reproducible and never touch the definition")
	var definition_before := _catalog.definition(&"iron_helm").base_modifiers.duplicate()
	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = 12345
	_catalog.set_rng(rng_a)
	var rolls_a: Array[String] = []
	for _i in 12:
		var instance := _roll(&"iron_helm")
		rolls_a.append("%d:%s" % [instance.rarity, JSON.stringify(instance.modifiers)])

	## Same seed must reproduce the same sequence.
	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 12345
	_catalog.set_rng(rng_b)
	var rolls_b: Array[String] = []
	for _i in 12:
		var instance := _roll(&"iron_helm")
		rolls_b.append("%d:%s" % [instance.rarity, JSON.stringify(instance.modifiers)])
	_check(rolls_a == rolls_b, "the same seed must reproduce the same rolls")

	## Different seed must produce at least one different roll (otherwise the seed is ignored).
	var rng_c := RandomNumberGenerator.new()
	rng_c.seed = 999
	_catalog.set_rng(rng_c)
	var rolls_c: Array[String] = []
	for _i in 12:
		rolls_c.append("%d" % _roll(&"iron_helm").rarity)
	var saw_common := rolls_c.has("0")
	var saw_fine := rolls_c.has("1")
	_check(saw_common and saw_fine, "a different seed must produce both qualities over 12 rolls (got %s)" % str(rolls_c))

	## The shared definition must be untouched, and a rolled instance must not alias it.
	var definition_after := _catalog.definition(&"iron_helm").base_modifiers
	_check(JSON.stringify(definition_before) == JSON.stringify(definition_after), "rolling must never modify the shared definition")
	var sample := _roll(&"iron_helm")
	sample.modifiers["armor"] = 999.0
	_check(float(_catalog.definition(&"iron_helm").base_modifiers.get("armor", 0.0)) != 999.0, "an instance's modifiers must not alias the definition's dictionary")

func _test_full_bag_pickup_leaves_the_drop() -> void:
	print("[test] a pickup refused by a full bag stays in the world")
	var arena := (load(ARENA_SCENE) as PackedScene).instantiate()
	root.add_child(arena)
	await _steps(2)
	var player := arena.get_node("Player") as PlayerController
	var inventory := player.get_node("ActorInventory") as ActorInventory
	var loot := arena.get_node("Loot") as LootSpawner
	_check(inventory != null and loot != null, "the arena must provide an inventory and a loot spawner")
	if inventory == null or loot == null:
		arena.queue_free()
		return
	## Use the catalog the arena already resolved, so names and rolls come from the same table.
	if inventory.get_catalog() == null:
		inventory.set_catalog(loot.catalog())

	for _i in ActorInventory.BAG_CAPACITY:
		inventory.try_add(_roll(&"rusty_pick"))
	_check(inventory.is_bag_full(), "the bag must be full for this case (used=%d)" % inventory.bag_used())

	var scene := load("res://scenes/item_pickup.tscn") as PackedScene
	var pickup := scene.instantiate() as ItemPickup
	loot.add_child(pickup)
	pickup.global_position = player.global_position
	pickup.setup(_roll(&"leather_cap"), inventory)
	await _steps(10)
	_check(is_instance_valid(pickup), "a pickup refused by a full bag must remain in the world")
	_check(_snapshot_count(inventory) == ActorInventory.BAG_CAPACITY, "the refused pickup must not enter the bag")

	## Free one bag slot by equipping something out of it: the pickup must then be collectible.
	var bag: Array = inventory.get_snapshot().get("bag", [])
	var weapon_id := ""
	for entry in bag:
		var dictionary := entry as Dictionary
		if dictionary.is_empty():
			continue
		var definition := _catalog.definition(StringName(String(dictionary.get("definition_id", ""))))
		if definition != null and definition.category == ItemDefinition.Category.ACCESSORY:
			weapon_id = String(dictionary.get("instance_id", ""))
			break
	## Every filled slot is a rusty_pick here, so free a slot through the equip path instead:
	var head_free := inventory.get_equipped(ActorInventory.SLOT_HEAD) == null
	if head_free and not bag.is_empty():
		var first_id := String((bag[0] as Dictionary).get("instance_id", ""))
		if inventory.try_equip(first_id, ActorInventory.SLOT_HEAD):
			await _steps(10)
			_check(not is_instance_valid(pickup), "with a free slot the pickup must be collected")
	_check(inventory.bag_used() <= ActorInventory.BAG_CAPACITY, "the bag must stay within capacity")
	arena.queue_free()
	await _steps(2)

func _test_equipment_changes_damage_and_armor() -> void:
	print("[test] equipment actually changes damage taken and dealt")
	var arena := (load(ARENA_SCENE) as PackedScene).instantiate()
	root.add_child(arena)
	await _steps(2)
	var player := arena.get_node("Player") as PlayerController
	var inventory := player.get_node("ActorInventory") as ActorInventory
	var loot := arena.get_node("Loot") as LootSpawner
	if inventory.get_catalog() == null:
		inventory.set_catalog(loot.catalog())
	var combatant := player.get_node("ActorCombatant") as ActorCombatant
	await _steps(2)

	var base_armor_damage := combatant.physical_damage(20.0)
	_check_close(base_armor_damage, 20.0, 0.001, "with no armour a 20 damage hit must land for 20")

	## Equip armour and confirm incoming damage drops.
	var vest := _roll(&"chainmail")
	inventory.try_add(vest)
	_check(inventory.try_equip(vest.instance_id, ActorInventory.SLOT_BODY), "the chainmail must equip")
	await _steps(2)
	_check_close(combatant.physical_damage(20.0), 15.0, 0.001, "5 armour must reduce a 20 damage hit to 15")

	## The accessory must change maximum health.
	var charm := _roll(&"traveler_charm")
	inventory.try_add(charm)
	var max_before := combatant.max_health()
	_check(inventory.try_equip(charm.instance_id, ActorInventory.SLOT_ACCESSORY), "the charm must equip")
	await _steps(2)
	_check_close(combatant.max_health(), max_before + 10.0, 0.001, "the charm must raise maximum health by 10")
	_check(combatant.get_health() <= combatant.max_health(), "current health must never exceed the maximum")

	## A weapon must add to attack. The charm from the previous step adds +3 attack, so the axe's
	## +10 must stack on top of it rather than replace it.
	var weapon := _roll(&"woodcutter_axe")
	inventory.try_add(weapon)
	_check(inventory.try_equip(weapon.instance_id, ActorInventory.SLOT_WEAPON), "the axe must equip")
	await _steps(2)
	_check_close(combatant.attack_bonus(), 13.0, 0.001, "the axe's +10 must stack with the charm's +3 attack")

	## Clearing everything must return to the base values exactly.
	for slot in ActorInventory.legal_slots():
		var equipped := inventory.get_equipped(slot)
		if equipped == null:
			continue
		var free_index := -1
		var bag: Array = inventory.get_snapshot().get("bag", [])
		for index in bag.size():
			if (bag[index] as Dictionary).is_empty():
				free_index = index
				break
		if free_index >= 0:
			inventory.try_unequip_to_slot(equipped.instance_id, free_index)
	await _steps(2)
	_check_close(combatant.attack_bonus(), 0.0, 0.001, "removing the weapon must clear the attack bonus")
	_check_close(combatant.physical_damage(20.0), 20.0, 0.001, "removing all armour must restore the base damage")
	arena.queue_free()
	await _steps(2)
