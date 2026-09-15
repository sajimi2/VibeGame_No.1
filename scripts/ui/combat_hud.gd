class_name CombatHud
extends CanvasLayer
## Shows what the combatant ports report and nothing else. It never computes damage, never awards
## anything, and never writes to a port: it only observes signals and re-renders.
##
## The enemy bar follows a FOCUS enemy (the nearest living enemy to the player) rather than one
## hard-wired node. A fixed node was the bug that made the bar useless once enemies became
## encounter-spawned: the wired node no longer existed, so the bar sat at its initial value and a
## dying enemy still read as full health.

const REFRESH_INTERVAL := 0.15

@export var player_path: NodePath
@export var encounter_manager_path: NodePath
@export var health_bar_path: NodePath
@export var stamina_bar_path: NodePath
@export var enemy_bar_path: NodePath
@export var status_label_path: NodePath
@export var hint_label_path: NodePath
@export var enemy_name_label_path: NodePath
## Optional label showing the contract's stage and progress.
@export var quest_status_label_path: NodePath
## Optional label for the equipped weapon. Every level's HUD gets one; when a scene does not name a
## node for it the HUD builds the label itself, so no level has to be edited to show it.
@export var weapon_status_label_path: NodePath

var _health_bar: ProgressBar
var _stamina_bar: ProgressBar
var _enemy_bar: ProgressBar
var _status_label: Label
var _hint_label: Label
var _enemy_name_label: Label
var _quest_status_label: Label
var _weapon_status_label: Label
var _player: PlayerController
var _encounters: EncounterManager
var _focus: ActorCombatant = null
var _refresh_timer := 0.0
var _status_override := ""
var _notice_label: Label
var _notice_seconds := 0.0

func show_notice(message: String) -> void:
	if _notice_label == null:
		_notice_label = Label.new()
		_notice_label.position = Vector2(16, 166)
		_notice_label.add_theme_font_size_override("font_size", 12)
		_notice_label.modulate = Color(1.0, 0.88, 0.6)
		add_child(_notice_label)
	_notice_label.text = message
	_notice_label.show()
	_notice_seconds = 3.0

func _ready() -> void:
	_health_bar = get_node_or_null(health_bar_path) as ProgressBar
	_stamina_bar = get_node_or_null(stamina_bar_path) as ProgressBar
	_enemy_bar = get_node_or_null(enemy_bar_path) as ProgressBar
	_status_label = get_node_or_null(status_label_path) as Label
	_hint_label = get_node_or_null(hint_label_path) as Label
	_enemy_name_label = get_node_or_null(enemy_name_label_path) as Label
	_quest_status_label = get_node_or_null(quest_status_label_path) as Label
	_build_weapon_status_label()
	_player = get_node_or_null(player_path) as PlayerController
	_encounters = get_node_or_null(encounter_manager_path) as EncounterManager
	if _hint_label != null:
		_hint_label.text = "WASD 移动 | 左键/Q 攻击 | 空格 闪避 | 右键 格挡 | E 交互 | I 背包 | F5/F9 存读档"
		_hint_label.add_theme_font_size_override("font_size", 10)
	if _player != null:
		var combatant := _find_combatant(_player)
		if combatant != null:
			combatant.health_changed.connect(_on_player_health)
			combatant.stamina_changed.connect(_on_player_stamina)
			_on_player_health(combatant.get_health(), combatant.max_health())
			_on_player_stamina(combatant.get_stamina(), combatant.max_stamina())
	_show_no_focus()

func _process(delta: float) -> void:
	if _notice_seconds > 0.0:
		_notice_seconds -= delta
		if _notice_seconds <= 0.0 and _notice_label != null:
			_notice_label.hide()
	_refresh_timer -= delta
	if _refresh_timer > 0.0:
		return
	_refresh_timer = REFRESH_INTERVAL
	_refresh_focus()

## Picks the nearest living enemy and follows it. Losing the focus (killed, despawned, or a closer
## enemy appearing) is re-evaluated every refresh, so the bar can never describe a stale actor.
func _refresh_focus() -> void:
	if _encounters == null or _player == null:
		return
	if _focus != null and is_instance_valid(_focus) and _focus.is_alive():
		_apply_bar(_enemy_bar, _focus.get_health(), _focus.max_health())
		return
	var nearest: ActorCombatant = null
	var best := INF
	for enemy in _encounters.all_enemy_nodes():
		var combatant := _find_combatant(enemy)
		if combatant == null or not combatant.is_alive():
			continue
		var distance := enemy.global_position.distance_to(_player.global_position)
		if distance < best:
			best = distance
			nearest = combatant
	_set_focus(nearest)

func _set_focus(combatant: ActorCombatant) -> void:
	if _focus == combatant:
		return
	if _focus != null and is_instance_valid(_focus) and _focus.health_changed.is_connected(_on_enemy_health):
		_focus.health_changed.disconnect(_on_enemy_health)
	_focus = combatant
	if _focus == null:
		_show_no_focus()
		return
	_focus.health_changed.connect(_on_enemy_health)
	_apply_bar(_enemy_bar, _focus.get_health(), _focus.max_health())
	if _enemy_name_label != null:
		_enemy_name_label.text = display_name_for(_focus.get_parent().name)

## Placeholder naming until the item/enemy catalogs exist (T04+).
static func display_name_for(node_name: String) -> String:
	match node_name:
		"Bandit": return "盗匪"
		"Archer": return "弓箭手"
		"Beast": return "野兽"
		"TrainingDummy": return "木桩"
		_: return node_name

func _show_no_focus() -> void:
	_apply_bar(_enemy_bar, 0.0, 1.0)
	if _enemy_name_label != null:
		_enemy_name_label.text = "（附近无敌人）"

func set_status(text: String) -> void:
	_status_override = text
	if _status_label != null:
		_status_label.text = text

func set_quest_status(text: String) -> void:
	if _quest_status_label != null:
		_quest_status_label.text = text

## The weapon line: what is in hand and how it moves while attacking. The level flow owns the text
## (it is the only place that knows the run's inventory and catalog); the HUD only displays it.
func set_weapon_status(text: String) -> void:
	if _weapon_status_label == null:
		return
	_weapon_status_label.text = text

## Built in code when the scene does not provide a node: four levels share this script and none of
## them should need a scene edit just to gain a HUD line.
func _build_weapon_status_label() -> void:
	_weapon_status_label = get_node_or_null(weapon_status_label_path) as Label
	if _weapon_status_label != null:
		return
	_weapon_status_label = Label.new()
	_weapon_status_label.position = Vector2(12, 109)
	_weapon_status_label.add_theme_font_size_override("font_size", 11)
	_weapon_status_label.modulate = Color(0.82, 0.86, 0.72)
	_weapon_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_weapon_status_label.text = "武器：赤手（拳击）"
	add_child(_weapon_status_label)

func clear_death_state() -> void:
	_status_override = ""
	set_status("")

func _apply_bar(bar: ProgressBar, current: float, maximum: float) -> void:
	if bar == null:
		return
	bar.max_value = maxf(1.0, maximum)
	bar.value = current

func _on_player_health(current: float, maximum: float) -> void:
	_apply_bar(_health_bar, current, maximum)

func _on_player_stamina(current: float, maximum: float) -> void:
	_apply_bar(_stamina_bar, current, maximum)

func _on_enemy_health(current: float, maximum: float) -> void:
	_apply_bar(_enemy_bar, current, maximum)

func _find_combatant(actor: Node) -> ActorCombatant:
	for child in actor.get_children():
		if child is ActorCombatant:
			return child as ActorCombatant
	return null
