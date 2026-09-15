class_name LootSpawner
extends Node2D
signal notice(message: String)
signal item_collected(item: ItemInstance)
## Turns an enemy death into ground drops and experience. One drop and one reward per death: the
## combatant's `died` signal fires exactly once, and the player's ProgressionPort owns the actual
## experience rules, so nothing here can double-pay.
##
## This node awards no experience itself and touches no health: it only creates ItemPickups and
## calls grant_experience for the enemy's configured reward.

const PICKUP_SCENE := "res://scenes/item_pickup.tscn"
## Fallback reward for an enemy that does not declare one.
const DEFAULT_EXPERIENCE_REWARD := 12

@export var player_path: NodePath
@export var encounter_manager_path: NodePath
## Container for spawned pickups; defaults to this node.
@export var loot_container_path: NodePath
## When false, enemy deaths grant no experience (used by tests that only care about loot).
@export var grants_experience := true

var _player: PlayerController
var _inventory: ActorInventory
var _progression: ActorProgression
var _encounters: EncounterManager
var _container: Node
var _catalog := ItemCatalog.build()
var _sequence := 0

func _ready() -> void:
	_player = get_node_or_null(player_path) as PlayerController
	_encounters = get_node_or_null(encounter_manager_path) as EncounterManager
	_container = get_node_or_null(loot_container_path) if loot_container_path != NodePath() else self
	if _container == null:
		_container = self
	if _player == null:
		push_error("LootSpawner: player_path is required")
		return
	_inventory = _find_inventory(_player)
	_progression = _find_progression(_player)
	if _encounters != null:
		_encounters.enemy_spawned.connect(_on_enemy_spawned)

func _find_inventory(actor: Node) -> ActorInventory:
	for child in actor.get_children():
		if child is ActorInventory:
			return child as ActorInventory
	return null

func _find_progression(actor: Node) -> ActorProgression:
	for child in actor.get_children():
		if child is ActorProgression:
			return child as ActorProgression
	return null

## Replaces the RNG so tests can reproduce a loot roll from a seed.
func set_rng(rng: RandomNumberGenerator) -> void:
	_catalog.set_rng(rng)

func catalog() -> ItemCatalog:
	return _catalog

func _on_enemy_spawned(enemy: Node, _id: StringName) -> void:
	var combatant := _find_combatant(enemy)
	if combatant == null:
		return
	## died fires once by contract, so attaching here cannot double-drop.
	combatant.died.connect(_on_enemy_died.bind(enemy))

func _on_enemy_died(_source_id: int, enemy: Node) -> void:
	_grant_experience(enemy)
	if not is_instance_valid(enemy):
		return
	var table := _drop_table_for(enemy)
	if table == null or table.is_empty():
		return
	for definition_id in table.guaranteed_definition_ids:
		_drop(definition_id, enemy.global_position)
	if not table.bonus_definition_ids.is_empty() and _catalog.rng().randf() < table.bonus_chance:
		var index := _catalog.rng().randi_range(0, table.bonus_definition_ids.size() - 1)
		_drop(table.bonus_definition_ids[index], enemy.global_position + Vector2(10, 6))

## One reward per death. The enemy declares its own value; the ProgressionPort owns the level rules.
func _grant_experience(enemy: Node) -> void:
	if not grants_experience or _progression == null:
		return
	var reward := DEFAULT_EXPERIENCE_REWARD
	if enemy.has_method("get_experience_reward"):
		reward = int(enemy.call("get_experience_reward"))
	_progression.grant_experience(reward)

## Drop table comes from the enemy scene's exported DropTable; enemies without one drop nothing.
func _drop_table_for(enemy: Node) -> DropTable:
	return enemy.get("drop_table") as DropTable

func _drop(definition_id: StringName, at: Vector2) -> ItemPickup:
	if _inventory == null:
		return null
	_sequence += 1
	var instance := _catalog.roll(definition_id, "%d-%d" % [Time.get_ticks_usec(), _sequence])
	if instance == null:
		return null
	var scene := load(PICKUP_SCENE) as PackedScene
	if scene == null:
		push_error("LootSpawner: missing %s" % PICKUP_SCENE)
		return null
	var pickup := scene.instantiate() as ItemPickup
	if pickup == null:
		return null
	_container.add_child(pickup)
	pickup.global_position = at
	pickup.setup(instance, _inventory)
	pickup.collected.connect(_on_collected)
	pickup.rejected.connect(func(_item: ItemInstance): notice.emit("背包已满，物品留在地面"))
	return pickup

func _on_collected(item: ItemInstance) -> void:
	var definition := _catalog.definition(item.definition_id)
	notice.emit("获得：%s%s" % ["优质 " if item.rarity == 1 else "", definition.display_name if definition != null else "装备"])
	item_collected.emit(item)

func _find_combatant(actor: Node) -> ActorCombatant:
	for child in actor.get_children():
		if child is ActorCombatant:
			return child as ActorCombatant
	return null
