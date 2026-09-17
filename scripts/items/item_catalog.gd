class_name ItemCatalog
extends RefCounted
## 物品定义表及随机品质规则。定义资源约定只读；生成实例时复制属性，不回写定义。

const PATH_PATTERN := "res://data/items/%s.tres"
const RARITY_COMMON := 0
const RARITY_FINE := 1
## 随机生成优质物品的概率。
const FINE_CHANCE := 0.3
## 优质物品随机增加的一项属性值。
const FINE_BONUS_AMOUNT := 3.0

var _definitions: Dictionary = {}
var _rng := RandomNumberGenerator.new()

func _init() -> void:
	_rng.randomize()

## 替换随机数生成器，供测试用固定种子复现结果。
func set_rng(rng: RandomNumberGenerator) -> void:
	_rng = rng

func rng() -> RandomNumberGenerator:
	return _rng

## 按定义 ID 加载资源并建立查询表；缺失资源报错后跳过。
func load_definitions(ids: Array[StringName]) -> void:
	_definitions.clear()
	for id in ids:
		var definition := load(PATH_PATTERN % id) as ItemDefinition
		if definition == null:
			push_error("ItemCatalog: missing definition for '%s'" % id)
			continue
		_definitions[id] = definition

func has_definition(id: StringName) -> bool:
	return _definitions.has(id)

func definition(id: StringName) -> ItemDefinition:
	return _definitions.get(id)

func ids() -> Array:
	return _definitions.keys()

## 当前玩法目录只收录可获得的猎刀和大砍刀。
static func default_ids() -> Array[StringName]:
	return [&"hunting_knife", &"great_cleaver"]

## 一次创建并加载当前物品目录。
static func build() -> ItemCatalog:
	var catalog := ItemCatalog.new()
	catalog.load_definitions(default_ids())
	return catalog

## 按定义 ID 生成物品，使用调用方提供的实例 ID，并复制属性字典。
## 实例 ID 的唯一性由调用方及库存校验保证。
func roll(definition_id: StringName, instance_id: String) -> ItemInstance:
	var definition := definition(definition_id)
	if definition == null:
		push_error("ItemCatalog: cannot roll unknown definition '%s'" % definition_id)
		return null
	var instance := ItemInstance.new()
	instance.instance_id = instance_id
	instance.definition_id = definition_id
	var modifiers := duplicate_modifiers(definition.base_modifiers)
	var rarity := RARITY_COMMON
	if _rng.randf() < FINE_CHANCE:
		rarity = RARITY_FINE
		apply_fine_bonus(definition, modifiers)
	instance.rarity = rarity
	instance.modifiers = modifiers
	return instance

## 从定义的候选属性中随机挑一项，为优质物品增加固定加成。
func apply_fine_bonus(definition: ItemDefinition, modifiers: Dictionary) -> void:
	if definition.bonus_pool.is_empty():
		return
	var key: StringName = definition.bonus_pool[_rng.randi_range(0, definition.bonus_pool.size() - 1)]
	var current := float(modifiers.get(key, 0.0))
	modifiers[key] = current + FINE_BONUS_AMOUNT

## 复制属性字典并统一为浮点值，避免实例和共享定义互相影响。
static func duplicate_modifiers(source: Dictionary) -> Dictionary:
	var copy := {}
	for key in source.keys():
		copy[key] = float(source[key])
	return copy

## 汇总多件物品的属性加成，供装备属性重新计算使用。
static func sum_modifiers(instances: Array) -> Dictionary:
	var total := {}
	for entry in instances:
		if entry == null:
			continue
		var instance := entry as ItemInstance
		if instance == null:
			continue
		for key in instance.modifiers.keys():
			total[key] = float(total.get(key, 0.0)) + float(instance.modifiers[key])
	return total
