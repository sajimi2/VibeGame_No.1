class_name ActorInventory
extends InventoryPort
## 库存实现：20 格背包及武器、头部、身体、饰品四类装备槽。
## 写入时复制物品，快照返回数据副本；外部不应直接修改查询到的物品。
## 添加与换装先校验后修改，拒绝时保持原状；同一实例 ID 不应重复出现。
const BAG_CAPACITY := 20
const SLOT_WEAPON := &"weapon"
const SLOT_HEAD := &"head"
const SLOT_BODY := &"body"
const SLOT_ACCESSORY := &"accessory"

static func legal_slots() -> Array[StringName]:
	return [SLOT_WEAPON, SLOT_HEAD, SLOT_BODY, SLOT_ACCESSORY]

## 把物品类别映射到对应装备槽。
static func slot_for_category(category: int) -> StringName:
	match category:
		ItemDefinition.Category.WEAPON: return SLOT_WEAPON
		ItemDefinition.Category.HEAD: return SLOT_HEAD
		ItemDefinition.Category.BODY: return SLOT_BODY
		_ : return SLOT_ACCESSORY

var _catalog: ItemCatalog
## 空格保留 null，使背包格子的下标稳定。
var _bag: Array[ItemInstance] = []
var _equipment: Dictionary = {}

## 提前固定背包格数和装备槽键，保证快照与界面下标一致。
func _init() -> void:
	for _i in BAG_CAPACITY:
		_bag.append(null)
	for slot in legal_slots():
		_equipment[slot] = null

func set_catalog(catalog: ItemCatalog) -> void:
	_catalog = catalog

## 未注入目录时使用默认物品目录，支持独立实例化库存。
func _ready() -> void:
	if _catalog == null:
		_catalog = ItemCatalog.build()

func get_catalog() -> ItemCatalog:
	return _catalog

# 库存修改接口。

## 校验物品并找到空格后保存副本，成功时发出库存变化信号。
func try_add(item: ItemInstance) -> bool:
	if not _is_acceptable(item):
		return false
	var index := _first_free_index()
	if index < 0:
		return false
	## 保存物品副本，防止调用者通过原始引用改写库存。
	_bag[index] = _copy_instance(item)
	inventory_changed.emit()
	return true

## 按实例 ID 换装；把旧装备放回来源位置，保持物品总数不变。
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

	## 所有拒绝条件已检查完，再一起交换两处引用，避免只改到一半。
	if bag_index >= 0:
		_bag[bag_index] = displaced
		_equipment[slot] = incoming
	else:
		_equipment[source_slot] = displaced
		_equipment[slot] = incoming
	equipment_changed.emit(slot, instance_id)
	inventory_changed.emit()
	return true

## 直接装备外部物品，供初始装备使用；原槽位非空时需有空背包格接收旧装备。
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

## 先清空再从快照恢复；跳过空条目及缺少 ID 的条目，文件版本由调用方检查。
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

## 由字典重建独立物品实例；空条目或缺少 ID 时返回 null。
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

## 把装备移到指定背包格；该格非空时交换两件物品，物品总数不变。
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

## 导出独立的普通字典和数组，用于存档或界面读取。
func get_snapshot() -> Dictionary:
	var bag_copy: Array[Dictionary] = []
	for entry in _bag:
		bag_copy.append(instance_to_dictionary(entry))
	var equipment_copy := {}
	for slot in _equipment.keys():
		equipment_copy[slot] = instance_to_dictionary(_equipment[slot])
	return {"bag": bag_copy, "equipment": equipment_copy}

# 供玩法和界面使用的查询。

func bag_used() -> int:
	var used := 0
	for entry in _bag:
		if entry != null:
			used += 1
	return used

func is_bag_full() -> bool:
	return _first_free_index() < 0

## 返回库存内部实例供读取；更换装备应使用换装接口。
func get_equipped(slot: StringName) -> ItemInstance:
	return _equipment.get(slot)

## 返回已装备武器的参数；为空时由战斗控制器选择默认配置。
func equipped_weapon_profile() -> TacticalWeaponData:
	return weapon_profile_of(get_equipped(SLOT_WEAPON))

## 按物品定义查找武器参数；空物品、未知定义或未配置武器参数时返回 null。
func weapon_profile_of(item: ItemInstance) -> TacticalWeaponData:
	if item == null:
		return null
	var definition := _definition_for(item)
	return definition.weapon_profile if definition != null else null

## 按实例 ID 返回背包内物品供读取，未找到时返回 null。
func get_in_bag(instance_id: String) -> ItemInstance:
	var index := _find_in_bag(instance_id)
	return _bag[index] if index >= 0 else null

## 移除背包物品并返回其副本，随后通知库存变化。
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

## 从当前装备重新汇总属性加成，避免反复换装时在旧结果上累加。
func equipped_modifiers() -> Dictionary:
	var equipped: Array[ItemInstance] = []
	for slot in legal_slots():
		var entry: ItemInstance = _equipment[slot]
		if entry != null:
			equipped.append(entry)
	return ItemCatalog.sum_modifiers(equipped)

## 读取单件物品的指定属性加成；空物品或缺少该属性时返回 0。
static func modifier_total(item: ItemInstance, key: StringName) -> float:
	if item == null:
		return 0.0
	return float(item.modifiers.get(key, 0.0))

# 内部校验、查找与复制。

## 添加前检查非空 ID、已知定义和全库存唯一性。
func _is_acceptable(item: ItemInstance) -> bool:
	if item == null or item.instance_id.is_empty():
		return false
	if _definition_for(item) == null:
		return false
	## 实例 ID 必须在整个背包和装备区内唯一。
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

## 复制实例及其属性字典，避免新旧对象共享可变数据。
func _copy_instance(item: ItemInstance) -> ItemInstance:
	var copy := ItemInstance.new()
	copy.instance_id = item.instance_id
	copy.definition_id = item.definition_id
	copy.rarity = item.rarity
	copy.modifiers = ItemCatalog.duplicate_modifiers(item.modifiers)
	return copy

## 把物品转换为可保存的字典；空槽位用空字典表示。
static func instance_to_dictionary(item: ItemInstance) -> Dictionary:
	if item == null:
		return {}
	return {
		"instance_id": item.instance_id,
		"definition_id": String(item.definition_id),
		"rarity": item.rarity,
		"modifiers": ItemCatalog.duplicate_modifiers(item.modifiers),
	}
