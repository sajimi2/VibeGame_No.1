class_name EncounterManager
extends Node2D
## Radius triggers initial spawning. Enemies persist in the level until killed or reset.

signal encounter_engaged(id: StringName)
signal encounter_disengaged(id: StringName)
signal encounter_defeated(id: StringName)
## Emitted for every enemy that enters the field, so other systems (loot) can attach to its death
## without knowing how encounters work.
signal enemy_spawned(enemy: Node, id: StringName)

## How long a defeated enemy stays on the field before being cleared. A corpse that never leaves
## keeps blocking movement and makes the fight read as unfinished.
const CORPSE_LINGER_SECONDS := 1.1

@export var player_path: NodePath
## Directory-free list of encounters, in any order.
@export var groups: Array[EncounterGroup] = []
## Container for spawned enemies. Defaults to this node.
@export var actor_container_path: NodePath

var _player: PlayerController
var _container: Node
## One entry per group index: { group, center, engaged, defeated, spawned }
var _runtime: Array[Dictionary] = []
## Enemies waiting to be cleared after their death animation, with the time left.
var _corpses: Dictionary = {}

func _ready() -> void:
	_player = get_node_or_null(player_path) as PlayerController
	_container = get_node_or_null(actor_container_path) if actor_container_path != NodePath() else self
	if _container == null:
		_container = self
	if _player == null:
		push_error("EncounterManager: player_path is required")
		return
	_build_runtime()

## Each encounter's area is centred on the marker node at the same index under this node, so an
## area can be moved in the scene without touching the resource.
func _build_runtime() -> void:
	var markers := get_children()
	var marker_index := 0
	for group in groups:
		if group == null:
			continue
		var center := global_position
		if marker_index < markers.size() and markers[marker_index] is Node2D:
			center = (markers[marker_index] as Node2D).global_position
		marker_index += 1
		_runtime.append({
			"group": group,
			"center": center,
			"engaged": false,
			"defeated": false,
			"spawned": [],
		})

func _physics_process(delta: float) -> void:
	_update_corpses(delta)
	if _player == null or _runtime.is_empty():
		return
	for state in _runtime:
		_update_group(state)

## Defeated enemies are cleared a moment after dying, so the body is visibly removed.
func _update_corpses(delta: float) -> void:
	if _corpses.is_empty():
		return
	for enemy in _corpses.keys():
		var remaining: float = _corpses[enemy] - delta
		if not is_instance_valid(enemy):
			_corpses.erase(enemy)
			continue
		if remaining <= 0.0:
			_corpses.erase(enemy)
			(enemy as Node).queue_free()
			continue
		_corpses[enemy] = remaining

func _schedule_corpse_removal(enemy: Node) -> void:
	if _corpses.has(enemy):
		return
	_corpses[enemy] = CORPSE_LINGER_SECONDS

func _update_group(state: Dictionary) -> void:
	var group: EncounterGroup = state["group"]
	var center: Vector2 = state["center"]
	var inside := _player.global_position.distance_to(center) <= group.activity_radius
	var engaged: bool = state["engaged"]
	if inside and not engaged:
		if not state["defeated"]:
			_spawn_group(group, center, state)
			state["engaged"] = true
			encounter_engaged.emit(group.id)
		return
	# Radius activates an encounter only. Living enemies persist until death or retry.

func _spawn_group(group: EncounterGroup, center: Vector2, state: Dictionary) -> void:
	var spawned: Array[Node] = []
	var count: int = mini(group.enemy_scenes.size(), group.spawn_offsets.size())
	for index in count:
		var scene := group.enemy_scenes[index]
		if scene == null:
			continue
		var enemy := scene.instantiate() as Node2D
		if enemy == null:
			continue
		_container.add_child(enemy)
		enemy.global_position = center + group.spawn_offsets[index]
		_configure_enemy(enemy)
		var combatant := _find_combatant(enemy)
		if combatant != null:
			combatant.died.connect(_on_enemy_died.bind(group.id, enemy))
		spawned.append(enemy)
		enemy_spawned.emit(enemy, group.id)
	state["spawned"] = spawned
	state["defeated"] = false

## Enemies act through their own port like every other actor; the manager only hands them a target.
func _configure_enemy(enemy: Node2D) -> void:
	if enemy.has_method("set_target_path"):
		enemy.call("set_target_path", _player.get_path())

## Leaving the area removes the whole group, survivors included.
func _despawn_group(state: Dictionary) -> void:
	for enemy in state["spawned"]:
		if is_instance_valid(enemy):
			enemy.queue_free()
	state["spawned"] = []

func _on_enemy_died(_source_id: int, id: StringName, enemy: Node) -> void:
	## The body is cleared shortly after death so the field does not fill with wrecks.
	if enemy != null and is_instance_valid(enemy):
		_schedule_corpse_removal(enemy)
	var state := _find_state(id)
	if state.is_empty():
		return
	var remaining := 0
	for other in state["spawned"]:
		if not is_instance_valid(other):
			continue
		var combatant := _find_combatant(other)
		if combatant != null and combatant.is_alive():
			remaining += 1
	if remaining == 0 and not state["defeated"]:
		state["defeated"] = true
		state["engaged"] = false
		encounter_defeated.emit(id)

## Retry: wipe every spawned enemy and forget the encounter, so walking in starts it fresh.
func reset_all() -> void:
	for enemy in _corpses.keys():
		if is_instance_valid(enemy):
			(enemy as Node).queue_free()
	_corpses.clear()
	for state in _runtime:
		_despawn_group(state)
		state["engaged"] = false
		state["defeated"] = false

func _find_state(id: StringName) -> Dictionary:
	for state in _runtime:
		var group: EncounterGroup = state["group"]
		if group != null and group.id == id:
			return state
	return {}

func is_engaged(id: StringName) -> bool:
	var state := _find_state(id)
	return bool(state.get("engaged", false))

func is_defeated(id: StringName) -> bool:
	var state := _find_state(id)
	return bool(state.get("defeated", false))

func activity_center(id: StringName) -> Vector2:
	var state := _find_state(id)
	return state.get("center", Vector2.ZERO)

func alive_enemy_count(id: StringName) -> int:
	var state := _find_state(id)
	var total := 0
	for enemy in state.get("spawned", []):
		if not is_instance_valid(enemy):
			continue
		var combatant := _find_combatant(enemy)
		if combatant != null and combatant.is_alive():
			total += 1
	return total

## Every enemy node currently tracked, alive or not. Public so tests and UI do not reach into the
## manager's internals.
func all_enemy_nodes() -> Array[Node2D]:
	var nodes: Array[Node2D] = []
	for state in _runtime:
		for enemy in state.get("spawned", []):
			if is_instance_valid(enemy) and enemy is Node2D:
				nodes.append(enemy as Node2D)
	return nodes

## Every enemy currently alive across all encounters; used by tests and by the HUD later.
func total_alive_enemies() -> int:
	var total := 0
	for state in _runtime:
		var group: EncounterGroup = state["group"]
		if group != null:
			total += alive_enemy_count(group.id)
	return total

func _find_combatant(from: Node) -> ActorCombatant:
	for child in from.get_children():
		if child is ActorCombatant:
			return child as ActorCombatant
	return null
