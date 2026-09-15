extends Node2D
## Arena flow: connects the encounters to the player and owns the death -> retry loop.
##
## Retry resets the participants in place (player, every spawned enemy, every encounter area)
## rather than reloading the scene: T02/T03 only need "die and fight again", and in-place reset
## keeps the retry independent of scene-reload timing. T06/T07 replace this with real level flow.

const RESTART_ACTION := &"restart"
const INVENTORY_ACTION := &"inventory"

@export var player_path: NodePath
@export var encounter_manager_path: NodePath
@export var hud_path: NodePath
## Panel toggled by the inventory action. Opening it pauses the world (DESIGN: menus pause
## simulation and input).
@export var inventory_panel_path: NodePath

var _player: PlayerController
var _encounters: EncounterManager
var _hud: CombatHud
var _inventory_panel: Control
var _awaiting_retry := false

func _ready() -> void:
	## The flow must keep receiving input while a menu pauses the tree, otherwise the inventory
	## could be opened and never closed.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = get_node_or_null(player_path) as PlayerController
	_encounters = get_node_or_null(encounter_manager_path) as EncounterManager
	_hud = get_node_or_null(hud_path) as CombatHud
	_inventory_panel = get_node_or_null(inventory_panel_path) as Control
	_set_inventory_open(false)
	if _player == null:
		push_error("ArenaFlow: player_path is required")
		return
	var player_combatant := _find_combatant(_player)
	if player_combatant != null:
		player_combatant.died.connect(_on_player_died)
	if _encounters != null:
		_encounters.encounter_defeated.connect(_on_encounter_defeated)
		_encounters.encounter_disengaged.connect(_on_encounter_disengaged)

func _find_combatant(actor: Node) -> ActorCombatant:
	for child in actor.get_children():
		if child is ActorCombatant:
			return child as ActorCombatant
	return null

func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if event.is_action_pressed(RESTART_ACTION):
		restart()
		return
	if event.is_action_pressed(INVENTORY_ACTION):
		_set_inventory_open(not is_inventory_open())

func is_inventory_open() -> bool:
	return _inventory_panel != null and _inventory_panel.visible

## DESIGN: opening a menu pauses the world; closing it resumes. The panel itself only renders.
func _set_inventory_open(open: bool) -> void:
	if _inventory_panel == null:
		return
	_inventory_panel.visible = open
	get_tree().paused = open

func _on_player_died(_source_id: int) -> void:
	_awaiting_retry = true

## An encounter is only "won" when nothing of it is left standing.
func _on_encounter_defeated(id: StringName) -> void:
	if _encounters == null or _encounters.total_alive_enemies() > 0:
		return
	if _hud != null:
		_hud.set_status("区域已清空 —— 按 R 再打一次")

## Walking out of an area tears the fight down; say so, so the player can tell it was deliberate.
func _on_encounter_disengaged(_id: StringName) -> void:
	if _encounters == null or _encounters.total_alive_enemies() > 0:
		return
	if _hud != null and not _awaiting_retry:
		_hud.set_status("已脱离战斗")

## Puts the player, every spawned enemy and every encounter back to their starting state.
func restart() -> void:
	_awaiting_retry = false
	_player.reset_for_retry()
	if _encounters != null:
		_encounters.reset_all()
	if _hud != null:
		_hud.clear_death_state()
