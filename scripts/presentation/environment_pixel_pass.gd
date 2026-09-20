extends MeshInstance3D
## 环境颜色先合成、角色随后按原精度绘制；复用原深度，不复制关卡或增加角色烘焙视口。
var enabled := true
var caption: Label
var caption_timer: Timer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 35
	var quad := QuadMesh.new()
	quad.size = Vector2(2,2)
	mesh = quad
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 16384
	position.z = -1
	var material := ShaderMaterial.new()
	material.shader = preload("res://scripts/presentation/environment_pixel_pass.gdshader")
	material.render_priority = -128
	material_override = material
	var layer := CanvasLayer.new()
	layer.layer = 90
	add_child(layer)
	caption = Label.new()
	caption.position = Vector2(18,106)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.add_theme_font_size_override("font_size",15)
	caption.add_theme_color_override("font_color",Color("ffe2a0"))
	caption.add_theme_color_override("font_outline_color",Color("17232a"))
	caption.add_theme_constant_override("outline_size",4)
	layer.add_child(caption)
	caption_timer = Timer.new()
	caption_timer.one_shot = true
	caption_timer.timeout.connect(caption.hide)
	add_child(caption_timer)
	set_enabled(true,false)

## 网格锚在世界的相机平面；镜头平移一像素时不重新选择另一组地表细节，减少背景跳闪。
func _process(_delta: float) -> void:
	if not enabled: return
	var camera := get_parent() as Camera3D
	var meters_per_pixel := camera.size/get_viewport().get_visible_rect().size.y
	var local := camera.global_basis.inverse()*camera.global_position
	var origin := Vector2(-local.x,local.y)/meters_per_pixel
	material_override.set_shader_parameter("grid_origin",Vector2(posmod(roundi(origin.x),2),posmod(roundi(origin.y),2)))

## 开关只切换环境采样；人物精度、镜头、碰撞和界面均不改动，暂停时也可对比。
func set_enabled(value: bool,notify := true) -> void:
	enabled = value
	visible = value
	if notify:
		caption.text = "F2 环境对比："+("粗像素 640×360" if value else "原始 1280×720")+" · 人物精度不变"
		caption.show()
		caption_timer.start(3)
	else: caption.hide()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==KEY_F2:
		set_enabled(not enabled)
		get_viewport().set_input_as_handled()
