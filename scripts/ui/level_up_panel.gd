class_name LevelUpPanel
extends PanelContainer
## Level-up UI. It only calls ProgressionPort.spend_point() and renders what the port reports; it
## never applies stats itself and never awards anything, so it cannot duplicate a reward.

@export var progression_path: NodePath

var _progression: ProgressionPort
var _title: Label
var _detail: Label
var _health_button: Button
var _stamina_button: Button

func _ready() -> void:
	_progression = get_node_or_null(progression_path) as ProgressionPort
	_build_layout()
	if _progression != null:
		_progression.experience_changed.connect(_on_experience_changed)
		_progression.points_changed.connect(_on_points_changed)
	_refresh()

func _build_layout() -> void:
	var box := VBoxContainer.new()
	add_child(box)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 12)
	box.add_child(_title)
	_detail = Label.new()
	_detail.add_theme_font_size_override("font_size", 10)
	box.add_child(_detail)
	var row := HBoxContainer.new()
	box.add_child(row)
	_health_button = Button.new()
	_health_button.text = "+5 最大生命"
	_health_button.add_theme_font_size_override("font_size", 10)
	_health_button.pressed.connect(_on_health_pressed)
	row.add_child(_health_button)
	_stamina_button = Button.new()
	_stamina_button.text = "+5 最大体力"
	_stamina_button.add_theme_font_size_override("font_size", 10)
	_stamina_button.pressed.connect(_on_stamina_pressed)
	row.add_child(_stamina_button)

func _on_health_pressed() -> void:
	_spend(ProgressionPort.Attribute.MAX_HEALTH)

func _on_stamina_pressed() -> void:
	_spend(ProgressionPort.Attribute.MAX_STAMINA)

func _spend(attribute: ProgressionPort.Attribute) -> void:
	if _progression == null:
		return
	## A refused spend is simply ignored: the port guarantees no side effects.
	_progression.spend_point(attribute)
	_refresh()

func _on_experience_changed(_level: int, _xp_in_level: int, _xp_to_next: int) -> void:
	_refresh()

func _on_points_changed(_points: int) -> void:
	_refresh()

func _refresh() -> void:
	if _progression == null or _title == null:
		return
	var snapshot := _progression.get_snapshot()
	var level: int = snapshot.get("level", 1)
	var xp: int = snapshot.get("xp_in_level", 0)
	var to_next: int = snapshot.get("xp_to_next", 0)
	var points: int = snapshot.get("unspent_points", 0)
	_title.text = "等级 %d" % level
	if to_next > 0:
		_detail.text = "经验 %d/%d　未分配点 %d" % [xp, to_next, points]
	else:
		_detail.text = "已达等级上限　未分配点 %d" % points
	var can_spend := points > 0
	_health_button.disabled = not can_spend
	_stamina_button.disabled = not can_spend
