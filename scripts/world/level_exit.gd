class_name LevelExit
extends Area2D
## A doorway to another level. Walking into it hands control to the LevelFlow, which carries the
## player's state across. Exits are data: which level they lead to lives in the scene.
##
## A locked exit simply refuses until its condition is met, so the outpost boss can sit behind a
## door that only opens once the lower floor is cleared.

@export var destination: StringName = &"village"
@export var flow_path: NodePath
## When true the exit only opens once the quest is deliverable or completed.
@export var requires_quest_progress := false
## When true the exit only opens once nothing hostile is left in this level.
@export var requires_cleared_level := false
## Optional label describing the destination / why it is locked.
@export var prompt_label_path: NodePath

var _flow: LevelFlow
var _prompt_label: Label
var _player_inside := false

func _ready() -> void:
	## A level can be entered while an Area2D signal is still being emitted (walking into an exit
	## instantiates the next level), and Godot forbids changing monitoring/monitorable inside a
	## signal callback. Deferring the assignment avoids that error.
	monitoring = true
	set_deferred("monitorable", false)
	collision_mask = 2
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_prompt_label = get_node_or_null(prompt_label_path) as Label
	_flow = get_node_or_null(flow_path) as LevelFlow
	refresh_prompt()

func _on_body_entered(body: Node2D) -> void:
	if not (body is PlayerController):
		return
	_player_inside = true
	refresh_prompt()
	## Walking through an open door is the whole interaction; a locked one just says why.
	if is_open():
		_flow.go_to_level(destination)

func _on_body_exited(body: Node2D) -> void:
	if body is PlayerController:
		_player_inside = false

func is_open() -> bool:
	if _flow == null:
		return false
	var session := _flow.session()
	if session == null:
		return false
	if requires_quest_progress and session.quest_stage != GameSession.QuestStage.DELIVERABLE and not session.is_quest_completed():
		return false
	if requires_cleared_level:
		var encounters := _find_encounters()
		if encounters != null and encounters.total_alive_enemies() > 0:
			return false
	return true

func lock_reason() -> String:
	if _flow == null:
		return ""
	if is_open():
		return "前往 %s" % destination
	if requires_cleared_level:
		return "先清空此处"
	return "尚未开启"

func refresh_prompt() -> void:
	if _prompt_label != null:
		_prompt_label.text = lock_reason()

func is_player_inside() -> bool:
	return _player_inside

func _find_encounters() -> EncounterManager:
	var parent := get_parent()
	while parent != null:
		for child in parent.get_children():
			if child is EncounterManager:
				return child as EncounterManager
		parent = parent.get_parent()
		if parent is Viewport:
			break
	return null
