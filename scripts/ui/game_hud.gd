extends CanvasLayer
## Presentation only: callers supply current status and feedback.
var status: Label
var notice: Label
var feedback: Label

func setup(caption: String) -> void:
	var panel := ColorRect.new()
	panel.color = Color(0.05, 0.08, 0.10, 0.88)
	panel.position = Vector2(10, 10)
	panel.size = Vector2(700, 94)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	var title := Label.new()
	title.text = caption
	title.position = Vector2(18, 14)
	title.add_theme_font_size_override("font_size", 20)
	title.modulate = Color("eddbac")
	add_child(title)
	status = Label.new()
	status.position = Vector2(18, 40)
	status.add_theme_font_size_override("font_size", 16)
	add_child(status)
	notice = Label.new()
	notice.text = "WASD 移动 · 空格短跳 · C 下蹲 · 左键挥刀 · 右键射箭 · E 交互 · I 背包\nShift 精确射击 · R 重新出发（保留装备） · Esc 退出 · F1 标注 · B 明暗对比"
	notice.position = Vector2(16, 662)
	notice.add_theme_font_size_override("font_size", 14)
	notice.add_theme_color_override("font_shadow_color", Color.BLACK)
	notice.add_theme_constant_override("shadow_offset_x", 1)
	notice.add_theme_constant_override("shadow_offset_y", 1)
	add_child(notice)

	feedback = Label.new()
	feedback.position = Vector2(18, 70)
	feedback.add_theme_font_size_override("font_size", 14)
	feedback.modulate = Color("ebcd84")
	add_child(feedback)



func update_status(hp: int, max_hp: int, height: float, crouched: bool, occluded: bool, message: String) -> void:
	feedback.text = message
	status.text = ("斜角正交 · 生命 %d/%d" % [hp, max_hp]) + "  |  高度 %.2f m  ·  %s  ·  %s" % [height, "下蹲" if crouched else "站立", "遮挡轮廓" if occluded else "可见"]
