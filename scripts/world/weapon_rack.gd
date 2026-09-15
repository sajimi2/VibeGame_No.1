class_name WeaponRack
extends Area2D
## A one-time world grant claimed with the interact key: the village rack that hands the player the
## great cleaver. Everything about it is data - which definition it gives out and which session flag
## records the claim - so the same node can hand out a later weapon without new code.
##
## Why the flag lives in the session: a claim must not come back. Walking away, leaving the level,
## dying and retrying, or loading a save all have to leave the weapon in the player's hands exactly
## once. The flag is part of the session snapshot, so a reload knows the rack is already empty.
##
## The item is only marked as taken AFTER it has actually been handed over: a full bag refuses the
## claim and leaves the rack stocked rather than silently eating the weapon.

signal claimed(item: ItemInstance)
signal claim_refused(reason: String)

const INTERACT_ACTION := &"interact"
## How close the player must stand; a distance test per physics step, never Area2D body_entered,
## which can miss a fast or teleported body (see QuestGiver for the same reasoning).
const ACTION_RADIUS := 72.0

@export var item_definition_id: StringName = &"great_cleaver"
## Session flag that records the claim. Must be unique per rack.
@export var claim_flag: StringName = &"village_cleaver"
@export var prompt_label_path: NodePath
## When true the weapon goes straight into the weapon slot (the displaced weapon drops into the bag
## if there is room, which is how the starting knife survives the upgrade).
@export var equip_directly := true
## Instance id given to the granted item; deterministic so tests and saves can name it.
@export var instance_id: String = "village-cleaver"

var _session: GameSession
var _prompt_label: Label
var _visual: Polygon2D
var _player: PlayerController
var _player_inside := false
var _base_color := Color(0.478431, 0.529412, 0.588235, 1)
var _in_range_color := Color(0.858824, 0.901961, 0.980392, 1)
var _catalog: ItemCatalog

func _ready() -> void:
	monitorable = false
	monitoring = false
	_prompt_label = get_node_or_null(prompt_label_path) as Label
	_visual = get_node_or_null("Visual") as Polygon2D
	_resolve_catalog()
	_session = GameSession.current
	_player = _find_player()
	refresh_prompt()

func _physics_process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = _find_player()
		if _player == null:
			return
	var in_range := global_position.distance_to(_player.global_position) <= ACTION_RADIUS
	if in_range == _player_inside:
		return
	_player_inside = in_range
	_apply_highlight(in_range)
	refresh_prompt()

# --- wiring --------------------------------------------------------------------------------

## The level hands over both the run's session and the player, so the rack never depends on group
## membership or on being ready after its neighbours.
func bind_session(session: GameSession) -> void:
	_session = session
	refresh_prompt()

func set_player(player: PlayerController) -> void:
	_player = player
	if _player != null:
		_player_inside = global_position.distance_to(_player.global_position) <= ACTION_RADIUS
		_apply_highlight(_player_inside)
	refresh_prompt()

## The catalog is shared with the loot spawner so rolls and grants use the same definitions.
func _resolve_catalog() -> void:
	var spawner := get_parent().get_node_or_null("Loot") if get_parent() != null else null
	if spawner != null and spawner.has_method("catalog"):
		_catalog = spawner.call("catalog") as ItemCatalog
	if _catalog == null:
		_catalog = ItemCatalog.build()

func _find_player() -> PlayerController:
	if is_inside_tree():
		var node := get_tree().get_first_node_in_group(&"player")
		if node is PlayerController:
			return node as PlayerController
	var parent := get_parent()
	if parent != null:
		var candidate := parent.get_node_or_null("Player")
		if candidate is PlayerController:
			return candidate as PlayerController
	return null

func _inventory() -> ActorInventory:
	if _player == null:
		return null
	for child in _player.get_children():
		if child is ActorInventory:
			return child as ActorInventory
	return null

# --- interaction ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or not _player_inside:
		return
	if event.is_action_pressed(INTERACT_ACTION):
		claim()

func is_player_inside() -> bool:
	return _player_inside

func is_claimed() -> bool:
	return _session != null and _session.has_claimed(claim_flag)

## Hands the weapon over exactly once. Returns true only when this call moved the item, so a second
## press (or a press after a reload) is a plain no-op.
func claim() -> bool:
	if _session == null or _catalog == null:
		return false
	if is_claimed():
		claim_refused.emit("已经拿过了")
		return false
	var inventory := _inventory()
	if inventory == null:
		claim_refused.emit("没有可接收的背包")
		return false
	var item := _catalog.roll(item_definition_id, instance_id)
	if item == null:
		claim_refused.emit("武器配置缺失")
		return false
	## Handing the item over first, and only then recording the claim, is what keeps a refused claim
	## from consuming the weapon.
	if not _grant(inventory, item):
		claim_refused.emit("背包已满，无法腾出武器位")
		return false
	_session.claim(claim_flag)
	refresh_prompt()
	claimed.emit(item)
	return true

func _grant(inventory: ActorInventory, item: ItemInstance) -> bool:
	if equip_directly:
		if inventory.try_equip_direct(item, ActorInventory.SLOT_WEAPON):
			return true
		## A full bag with an occupied weapon slot cannot take the swap; fall back to the bag when
		## there is room at all, otherwise refuse.
		return inventory.try_add(item)
	return inventory.try_add(item)

func _apply_highlight(in_range: bool) -> void:
	if _visual == null:
		return
	_visual.color = _in_range_color if in_range else _base_color

func refresh_prompt() -> void:
	if _prompt_label == null:
		return
	_prompt_label.text = prompt_text()

func prompt_text() -> String:
	if is_claimed():
		return "武器架：已取走"
	var definition := _catalog.definition(item_definition_id) if _catalog != null else null
	var name := definition.display_name if definition != null else String(item_definition_id)
	var suffix := "" if _player_inside else "（走近按 E）"
	return "E 领取%s %s" % [name, suffix]

## The instance id the rack will hand out; exposed so tests and saves can address the weapon.
func granted_instance_id() -> String:
	return instance_id
