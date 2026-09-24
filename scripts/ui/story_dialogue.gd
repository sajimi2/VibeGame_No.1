extends CanvasLayer
## 对话界面只发选项ID；篇章控制器验证距离与条件后修改状态。
signal chosen(id: String)
var open := false
var shade: ColorRect
var panel: PanelContainer
var content: VBoxContainer
func _ready() -> void:
	layer = 25
	process_mode = Node.PROCESS_MODE_ALWAYS
	shade = ColorRect.new()
	shade.size = Vector2(1280,720)
	shade.color = Color(0.01,.025,.03,.55)
	add_child(shade)
	panel = PanelContainer.new()
	panel.theme=preload("res://scripts/ui/pixel_style.gd").theme()
	panel.position = Vector2(274,130)
	panel.custom_minimum_size = Vector2(732,430)
	panel.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	var style := preload("res://scripts/ui/pixel_style.gd").box(true).duplicate()
	style.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel",style)
	add_child(panel)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation",12)
	panel.add_child(content)
	panel.hide()
	shade.hide()

func display(speaker: String, text: String, options: Array) -> void:
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	var title := Label.new()
	title.text = speaker
	title.add_theme_font_size_override("font_size",25)
	title.modulate = Color("d9bc82")
	content.add_child(title)
	var body := Label.new()
	body.text = text
	body.custom_minimum_size = Vector2(680,120)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size",19)
	content.add_child(body)
	# 交易/证据选项增多时只滚动选项区，标题与正文始终可见。
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size=Vector2(680,208)
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	var choices := VBoxContainer.new()
	choices.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	choices.add_theme_constant_override("separation",8)
	scroll.add_child(choices)
	for option in options:
		var button := Button.new()
		for style_name in ["normal","hover","pressed","focus"]:
			button.add_theme_stylebox_override(style_name,preload("res://scripts/ui/pixel_style.gd").box(style_name=="pressed",style_name=="hover"))
		button.text = option[1]
		button.custom_minimum_size.y = 36
		button.pressed.connect(func(): chosen.emit(option[0]))
		choices.add_child(button)
	open = true
	panel.show()
	shade.show()
	get_tree().paused = true

func close() -> void:
	if not open: return
	open = false
	panel.hide()
	shade.hide()
	get_tree().paused = false

func _input(event: InputEvent) -> void:
	if not open: return
	if event is InputEventKey and event.pressed:
		get_viewport().set_input_as_handled()
		if event.physical_keycode==KEY_ESCAPE: close()
