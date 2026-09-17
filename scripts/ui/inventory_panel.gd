extends CanvasLayer
## Presentation and pause/input only. Equipment rules and persistence belong to progression.
signal equip_requested(instance_id: String)
signal refresh_requested
var panel: PanelContainer
var content: VBoxContainer
var open := false

func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel=PanelContainer.new()
	panel.position=Vector2(330,180)
	panel.custom_minimum_size=Vector2(620,360)
	var style := StyleBoxFlat.new()
	style.bg_color=Color("17232a")
	style.border_color=Color("b5a574")
	style.set_border_width_all(2)
	style.content_margin_left=20
	style.content_margin_right=20
	style.content_margin_top=16
	style.content_margin_bottom=16
	panel.add_theme_stylebox_override("panel",style)
	add_child(panel)
	content=VBoxContainer.new()
	content.add_theme_constant_override("separation",12)
	panel.add_child(content)
	panel.hide()

func refresh(model: Dictionary) -> void:
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	var title := Label.new()
	title.text = "背包 / 等级 %d · 累计经验 %d    [I / Esc 关闭]" % [model.level, model.xp]
	title.add_theme_font_size_override("font_size", 22)
	content.add_child(title)
	var current := Label.new()
	current.text = "当前武器：" + model.equipped_name
	content.add_child(current)
	var detail := Label.new()
	detail.text = model.weapon_summary + "\n任意地点点击物品换装；攻击结束后可换。旧武器返回背包。"
	content.add_child(detail)
	var grid := GridContainer.new()
	grid.columns = 5
	content.add_child(grid)
	for entry in model.slots:
		var button := Button.new()
		button.custom_minimum_size = Vector2(108, 36)
		button.text = entry.label
		button.disabled = entry.id.is_empty() or not model.can_equip
		if model.attacking:
			button.tooltip_text = "请先关闭背包，待攻击结束后换装"
		if not entry.id.is_empty():
			button.pressed.connect(func(): equip_requested.emit(entry.id))
		grid.add_child(button)

func toggle() -> void:
	open = not open
	panel.visible = open
	get_tree().paused = open
	if open:
		refresh_requested.emit()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_I or (open and event.physical_keycode == KEY_ESCAPE):
			toggle()
			get_viewport().set_input_as_handled()
