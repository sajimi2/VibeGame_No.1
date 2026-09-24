extends TextureRect
## 生成的人体示意原画仅用于装备方位，不参与点击、人物换装或身体伤害判定。
func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	texture=load("res://assets/ui/woodpath_v3/equipment_anatomy.png")
	expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	position=Vector2(92,96)
	size=Vector2(112,208)
	modulate=Color(.78,.80,.83,.87)
