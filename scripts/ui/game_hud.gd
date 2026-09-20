extends CanvasLayer
## 只负责显示；状态和反馈文字由调用方传入。
var status: Label
var notice: Label
var feedback: Label

## 创建关卡标题、状态文字和操作提示，标题由地图提供。
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
	notice.text = "WASD 移动 · Shift 疾跑（轻/中型） · 空格跳跃 · C 下蹲稳弓 · 左键挥刀 · 右键射箭 · E 交互 · I 背包\nCtrl 精确射击 · R 重新出发（保留装备） · Esc 退出 · F11 全屏/窗口 · F1 标注 · F2 环境精度 · B 明暗对比"
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



## 根据传入值更新生命、高度、姿态和反馈文字，不修改玩法状态。
func update_status(hp: int, max_hp: int, height: float, crouched: bool, occluded: bool, message: String) -> void:
	feedback.text = message
	status.text = ("斜角正交 · 生命 %d/%d" % [hp, max_hp]) + "  |  高度 %.2f m  ·  %s  ·  %s" % [height, "下蹲" if crouched else "站立", "遮挡轮廓" if occluded else "可见"]
