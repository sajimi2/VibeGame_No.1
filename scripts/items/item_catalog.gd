class_name ItemCatalog
extends RefCounted
## The immutable item table plus the roll policy. Definitions are loaded once and treated as
## read-only; a random roll produces a fresh ItemInstance whose modifiers are copied out of the
## definition, so rolling can never write back into the shared resource.

const PATH_PATTERN := "res://data/items/%s.tres"
const RARITY_COMMON := 0
const RARITY_FINE := 1
## Chance that a drop is rolled as fine (upgraded) quality.
const FINE_CHANCE := 0.3
## How much of a bonus modifier a fine roll adds.
const FINE_BONUS_AMOUNT := 3.0

var _definitions: Dictionary = {}
var _rng := RandomNumberGenerator.new()

func _init() -> void:
	_rng.randomize()

## Replaces the RNG so a seed reproduces the same drops in tests.
func set_rng(rng: RandomNumberGenerator) -> void:
	_rng = rng

func rng() -> RandomNumberGenerator:
	return _rng

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

## Only the two currently obtainable weapons belong to the active game catalog.
static func default_ids() -> Array[StringName]:
	return [&"hunting_knife", &"great_cleaver"]

## Every definition resolved, for building a catalog in one call.
static func build() -> ItemCatalog:
	var catalog := ItemCatalog.new()
	catalog.load_definitions(default_ids())
	return catalog

## Rolls one drop from a definition id. The instance gets a fresh unique id and its own copy of
## the modifiers; the definition resource is never touched.
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

## Fine quality adds a small extra amount of one of the definition's bonus modifiers.
func apply_fine_bonus(definition: ItemDefinition, modifiers: Dictionary) -> void:
	if definition.bonus_pool.is_empty():
		return
	var key: StringName = definition.bonus_pool[_rng.randi_range(0, definition.bonus_pool.size() - 1)]
	var current := float(modifiers.get(key, 0.0))
	modifiers[key] = current + FINE_BONUS_AMOUNT

## Deep copy, so an instance's modifiers never alias the definition's dictionary.
static func duplicate_modifiers(source: Dictionary) -> Dictionary:
	var copy := {}
	for key in source.keys():
		copy[key] = float(source[key])
	return copy

## Sums the modifiers of several instances (used when recomputing equipped stats).
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
