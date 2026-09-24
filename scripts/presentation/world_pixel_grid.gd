extends CanvasLayer
## 已停用的整屏采样实验：用户反馈损伤人物和场景小字，正式场景禁止装配。
const Standard=preload("res://scripts/presentation/pixel_standard.gd")
func _ready() -> void:
	layer=-100
	var screen:=ColorRect.new()
	screen.name="RetiredWorldPixelExperiment"
	screen.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var material:=ShaderMaterial.new()
	material.shader=preload("res://scripts/presentation/world_pixel_grid.gdshader")
	material.set_shader_parameter("logical_size",Vector2(Standard.WORLD_SIZE))
	screen.material=material
	add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
