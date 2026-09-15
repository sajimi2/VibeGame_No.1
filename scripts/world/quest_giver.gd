class_name QuestGiver
extends Area2D
## The village contract board. Standing in range lets the player press the interact key to accept
## the contract or hand it in. It reads and writes the session's quest stage only; it never
## awards anything itself, and hand-in can only pay once because GameSession enforces that.
##
## TASKS.md T06 states: 任务使用未接/进行中/可交付/已完成状态，完成奖只发一次.

signal quest_prompt_changed(prompt: String)

const INTERACT_ACTION := &"interact"

@export var session_source_path: NodePath
## Label shown above the giver; updated as the stage changes.
@export var prompt_label_path: NodePath

## How close the player must stand for the prompt to become actionable.
const ACTION_RADIUS := 72.0

var _session: GameSession
var _prompt_label: Label
var _player_inside := false
var _player: PlayerController
var _visual: Polygon2D
var _base_color := Color(0.917647, 0.803922, 0.454902, 1)
var _in_range_color := Color(1.0, 0.98, 0.75, 1)

func _ready() -> void:
	## Proximity is measured every physics step rather than read from Area2D's body_entered:
	## that signal can be missed when a body is teleported or moves quickly, which showed up as
	## "I am standing right next to it and E does nothing". A distance test cannot miss.
	monitorable = false
	monitoring = false
	_prompt_label = get_node_or_null(prompt_label_path) as Label
	_visual = get_node_or_null("Visual") as Polygon2D
	_session = _resolve_session()
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

## The level hands the player over explicitly; the fallback lookups only cover odd setups.
func bind_session(session: GameSession) -> void:
	_session = session
	refresh_prompt()

func set_player(player: PlayerController) -> void:
	_player = player
	if _player != null:
		_player_inside = global_position.distance_to(_player.global_position) <= ACTION_RADIUS
		_apply_highlight(_player_inside)
	refresh_prompt()

func _find_player() -> PlayerController:
	if is_inside_tree():
		var node := get_tree().get_first_node_in_group(&"player")
		if node is PlayerController:
			return node as PlayerController
	## Fallback: the level root's Player child.
	var parent := get_parent()
	if parent != null:
		var candidate := parent.get_node_or_null("Player")
		if candidate is PlayerController:
			return candidate as PlayerController
	return null

func _resolve_session() -> GameSession:
	if session_source_path != NodePath():
		var source := get_node_or_null(session_source_path)
		if source != null and source.has_method("session"):
			return source.call("session") as GameSession
	return GameSession.current

## Placeholder range feedback: the marker brightens when the player can actually interact.
func _apply_highlight(in_range: bool) -> void:
	if _visual == null:
		return
	_visual.color = _in_range_color if in_range else _base_color

func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or not _player_inside:
		return
	if event.is_action_pressed(INTERACT_ACTION):
		interact()

## Accepts the contract, or hands it in when it is deliverable. Returns true when something
## changed, so callers (and tests) can tell a no-op apart from a real interaction.
func interact() -> bool:
	if _session == null:
		return false
	if _session.is_quest_deliverable():
		var paid := _session.complete_quest()
		refresh_prompt()
		return paid
	if _session.quest_stage == GameSession.QuestStage.NOT_STARTED:
		var accepted := _session.accept_quest()
		refresh_prompt()
		return accepted
	return false

func refresh_prompt() -> void:
	if _prompt_label == null or _session == null:
		return
	_prompt_label.text = prompt_text()
	quest_prompt_changed.emit(_prompt_label.text)

func prompt_text() -> String:
	if _session == null:
		return ""
	var suffix := "" if _player_inside else "（走近按 E）"
	match _session.quest_stage:
		GameSession.QuestStage.NOT_STARTED:
			return "E 接契约：击杀 3 敌，奖励 50 经验 %s" % suffix
		GameSession.QuestStage.IN_PROGRESS:
			return "契约进行中 %d/%d" % [_session.kills, _session.kills_required]
		GameSession.QuestStage.DELIVERABLE:
			return "交付契约 %s" % suffix
		_:
			return "契约已完成"

func is_player_inside() -> bool:
	return _player_inside
