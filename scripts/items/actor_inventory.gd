class_name ActorInventory
extends InventoryPort
## Concrete InventoryPort: a fixed-size bag of 20 slots plus four equipment slots.
##
## Invariants this class is responsible for (TASKS.md T04 acceptance):
##   - a failed operation changes NOTHING (no partial mutation on any rejection path);
##   - an instance id is unique across bag and equipment;
##   - equipping swaps atomically, including when the bag is completely full;
##   - the inventory owns its ItemInstances, so a caller cannot mutate stored state afterwards;
##   - get_snapshot() returns deep copies, never live instances.
##
## The shield is deliberately not an item (DESIGN: it is a fixed starting tool and does not drop
## in v0.1), so it is not one of the equipment slots handled here.

const BAG_CAPACITY := 20
const SLOT_WEAPON := &"weapon"
const SLOT_HEAD := &"head"
const SLOT_BODY := &"body"
const SLOT_ACCESSORY := &"accessory"

static func legal_slots() -> Array[StringName]:
	return [SLOT_WEAPON, SLOT_HEAD, SLOT_BODY, SLOT_ACCESSORY]

## Maps an item category to the slot it may occupy.
static func slot_for_category(category: int) -> StringName:
	match category:
		ItemDefinition.Category.WEAPON: return SLOT_WEAPON
		ItemDefinition.Category.HEAD: return SLOT_HEAD
		ItemDefinition.Category.BODY: return SLOT_BODY
		_ : return SLOT_ACCESSORY

var _catalog: ItemCatalog
## Empty slots hold null so bag positions stay stable (an index is a position, not a list cursor).
var _bag: Array[ItemInstance] = []
var _equipment: Dictionary = {}

func _init() -> void:
	for _i in BAG_CAPACITY:
		_bag.append(null)
	for slot in legal_slots():
		_equipment[slot] = null

func set_catalog(catalog: ItemCatalog) -> void:
	_catalog = catalog

func _ready() -> void:
	if _catalog == null:
		_catalog = ItemCatalog.build()

func get_catalog() -> ItemCatalog:
	return _catalog

# --- InventoryPort -------------------------------------------------------------------------

func try_add(item: ItemInstance) -> bool:
	if not _is_acceptable(item):
		return false
	var index := _first_free_index()
	if index < 0:
		return false
	## The inventory owns its copy; the caller keeps no mutable authority.
	_bag[index] = _copy_instance(item)
	inventory_changed.emit()
	return true

## Equip by instance id. Works from the bag or as a direct swap between slots, and always keeps
## the item count constant by putting whatever was displaced back where the incoming item was.
func try_equip(instance_id: String, slot: StringName) -> bool:
	if instance_id.is_empty() or not _equipment.has(slot):
		return false

	var bag_index := _find_in_bag(instance_id)
	var source_slot := _find_equipped_slot(instance_id)
	if bag_index < 0 and source_slot == &"":
		return false

	var incoming: ItemInstance = _bag[bag_index] if bag_index >= 0 else _equipment[source_slot]
	if incoming == null:
		return false
	var definition := _definition_for(incoming)
	if definition == null:
		return false
	if slot_for_category(definition.category) != slot:
		return false

	var displaced: ItemInstance = _equipment[slot]
	if source_slot == slot:
		return true

	## Commit phase. Every rejection was handled above, so nothing can fail from here.
	if bag_index >= 0:
		_bag[bag_index] = displaced
		_equipment[slot] = incoming
	else:
		_equipment[source_slot] = displaced
		_equipment[slot] = incoming
	equipment_changed.emit(slot, instance_id)
	inventory_changed.emit()
	return true

## Adds an item straight into its legal slot, e.g. quest rewards. Uses the same atomic swap path.
func try_equip_direct(item: ItemInstance, slot: StringName) -> bool:
	if not _is_acceptable(item) or not _equipment.has(slot):
		return false
	var definition := _definition_for(item)
	if definition == null or slot_for_category(definition.category) != slot:
		return false
	var displaced: ItemInstance = _equipment[slot]
	if displaced == null:
		_equipment[slot] = _copy_instance(item)
	else:
		var index := _first_free_index()
		if index < 0:
			return false
		_bag[index] = displaced
		_equipment[slot] = _copy_instance(item)
	equipment_changed.emit(slot, item.instance_id)
	inventory_changed.emit()
	return true

## Replaces the whole inventory from a snapshot (see get_snapshot). Invalid entries are skipped
## rather than aborting, so a partially damaged save still restores what it can; the caller is
## responsible for having validated the file's schema version first.
func restore_from_snapshot(snapshot: Dictionary) -> void:
	for index in _bag.size():
		_bag[index] = null
	for slot in _equipment.keys():
		_equipment[slot] = null
	var bag: Array = snapshot.get("bag", [])
	for index in mini(bag.size(), _bag.size()):
		_bag[index] = _instance_from_dictionary(bag[index])
	var equipment: Dictionary = snapshot.get("equipment", {})
	for slot in _equipment.keys():
		if equipment.has(slot):
			_equipment[slot] = _instance_from_dictionary(equipment[slot])
	equipment_changed.emit(&"", "")
	inventory_changed.emit()

## Rebuilds one owned instance from its snapshot form; null for an empty or unusable entry.
func _instance_from_dictionary(entry: Variant) -> ItemInstance:
	if not (entry is Dictionary) or (entry as Dictionary).is_empty():
		return null
	var dictionary := entry as Dictionary
	var instance := ItemInstance.new()
	instance.instance_id = String(dictionary.get("instance_id", ""))
	instance.definition_id = StringName(String(dictionary.get("definition_id", "")))
	instance.rarity = int(dictionary.get("rarity", 0))
	instance.modifiers = ItemCatalog.duplicate_modifiers(dictionary.get("modifiers", {}) as Dictionary)
	if instance.instance_id.is_empty() or instance.definition_id.is_empty():
		return null
	return instance

## Moves an equipped instance into a specific bag slot, swapping if that slot is occupied. Used by
## the UI to unequip; the swap keeps the item count constant, so a full bag is not a problem.
func try_unequip_to_slot(instance_id: String, bag_index: int) -> bool:
	if instance_id.is_empty() or bag_index < 0 or bag_index >= _bag.size():
		return false
	var source_slot := _find_equipped_slot(instance_id)
	if source_slot == &"":
		return false
	var incoming: ItemInstance = _equipment[source_slot]
	var displaced: ItemInstance = _bag[bag_index]
	_bag[bag_index] = incoming
	_equipment[source_slot] = displaced
	equipment_changed.emit(source_slot, instance_id)
	inventory_changed.emit()
	return true

func get_snapshot() -> Dictionary:
	var bag_copy: Array[Dictionary] = []
	for entry in _bag:
		bag_copy.append(instance_to_dictionary(entry))
	var equipment_copy := {}
	for slot in _equipment.keys():
		equipment_copy[slot] = instance_to_dictionary(_equipment[slot])
	return {"bag": bag_copy, "equipment": equipment_copy}

# --- queries used by gameplay and UI -------------------------------------------------------

func bag_used() -> int:
	var used := 0
	for entry in _bag:
		if entry != null:
			used += 1
	return used

func is_bag_full() -> bool:
	return _first_free_index() < 0

func get_equipped(slot: StringName) -> ItemInstance:
	return _equipment.get(slot)

## Behaviour of the weapon currently in the weapon slot, or null when nothing is equipped (the
## wielder then keeps its fallback moves: an unarmed player throws punches).
func equipped_weapon_profile() -> WeaponProfile:
	return weapon_profile_of(get_equipped(SLOT_WEAPON))

## Behaviour a specific instance would provide if equipped. Null for non-weapons, empty slots and
## weapons that have no profile yet.
func weapon_profile_of(item: ItemInstance) -> WeaponProfile:
	if item == null:
		return null
	var definition := _definition_for(item)
	return definition.weapon_profile if definition != null else null

func get_in_bag(instance_id: String) -> ItemInstance:
	var index := _find_in_bag(instance_id)
	return _bag[index] if index >= 0 else null

func take_from_bag(instance_id: String) -> ItemInstance:
	var index := _find_in_bag(instance_id)
	if index < 0:
		return null
	var result := _copy_instance(_bag[index])
	_bag[index] = null
	inventory_changed.emit()
	return result

func has_instance(instance_id: String) -> bool:
	return _find_in_bag(instance_id) >= 0 or _find_equipped_slot(instance_id) != &""

## Total additive modifiers of everything currently equipped. The assembler adds these to the
## actor's base values; it never accumulates on a previous result, so repeat equip/unequip cycles
## cannot drift.
func equipped_modifiers() -> Dictionary:
	var equipped: Array[ItemInstance] = []
	for slot in legal_slots():
		var entry: ItemInstance = _equipment[slot]
		if entry != null:
			equipped.append(entry)
	return ItemCatalog.sum_modifiers(equipped)

## Total value of one modifier key across a set of items; used by the comparison panel.
static func modifier_total(item: ItemInstance, key: StringName) -> float:
	if item == null:
		return 0.0
	return float(item.modifiers.get(key, 0.0))

# --- internals -----------------------------------------------------------------------------

func _is_acceptable(item: ItemInstance) -> bool:
	if item == null or item.instance_id.is_empty():
		return false
	if _definition_for(item) == null:
		return false
	## An instance id must be unique across the whole inventory.
	return not has_instance(item.instance_id)

func _definition_for(item: ItemInstance) -> ItemDefinition:
	if _catalog == null:
		return null
	return _catalog.definition(item.definition_id)

func _first_free_index() -> int:
	for index in _bag.size():
		if _bag[index] == null:
			return index
	return -1

func _find_in_bag(instance_id: String) -> int:
	for index in _bag.size():
		var entry: ItemInstance = _bag[index]
		if entry != null and entry.instance_id == instance_id:
			return index
	return -1

func _find_equipped_slot(instance_id: String) -> StringName:
	for slot in _equipment.keys():
		var entry: ItemInstance = _equipment[slot]
		if entry != null and entry.instance_id == instance_id:
			return slot
	return &""

## Deep copy so stored state cannot be mutated through the caller's reference.
func _copy_instance(item: ItemInstance) -> ItemInstance:
	var copy := ItemInstance.new()
	copy.instance_id = item.instance_id
	copy.definition_id = item.definition_id
	copy.rarity = item.rarity
	copy.modifiers = ItemCatalog.duplicate_modifiers(item.modifiers)
	return copy

## Snapshot form of one instance, or an empty dictionary for an empty slot.
static func instance_to_dictionary(item: ItemInstance) -> Dictionary:
	if item == null:
		return {}
	return {
		"instance_id": item.instance_id,
		"definition_id": String(item.definition_id),
		"rarity": item.rarity,
		"modifiers": ItemCatalog.duplicate_modifiers(item.modifiers),
	}
