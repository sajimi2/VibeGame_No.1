extends "res://scripts/world/level.gd"
## 扩充后的同一美术实验；复用正式移动/相机/遮挡，仅编排院子和查看快捷键。
var cottage: Node3D
var painting: Node3D
var courtyard: Node3D
var guides:=false
var artwork:=true
var ready_to_test:=false
var courtyard_overview:=false

func _ready() -> void:
	encounter_enabled=false
	mission_enabled=false
	progress_enabled=false
	results_enabled=false
	super._ready()
	cottage.roof.observer=player
	_finish.call_deferred()

func _build_environment() -> void:
	var ground:=box("Meadow",Vector3(0,-.27,4),Vector3(48,.5,48),"grass")
	var ground_material:=ShaderMaterial.new()
	ground_material.shader=preload("res://scripts/presentation/courtyard_ground.gdshader")
	ground_material.set_shader_parameter("meadow",load("res://assets/environment/experiments/painted_courtyard/textures/meadow.png"))
	ground_material.set_shader_parameter("earth",load("res://assets/environment/warehouse_slice/textures/earth.png"))
	for child in ground.get_children():
		if child is MeshInstance3D: child.material_override=ground_material
	cottage=load("res://assets/environment/experiments/cottage/cottage.tscn").instantiate()
	cottage.name="Cottage"
	add_child(cottage)
	courtyard=preload("res://scripts/presentation/painted_courtyard.gd").new()
	courtyard.name="Courtyard"
	add_child(courtyard)

## 延迟到原墙注册之后绑定，绘画层不取代控制器的状态所有权。
func _finish() -> void:
	painting=preload("res://scripts/presentation/painted_cottage.gd").new()
	cottage.add_child(painting)
	painting.setup(cottage,true)
	# 环境美术投影与人物实时投影共用白天光向；不再保留第二个时间推算方向。
	var shadow_style=preload("res://assets/environment/experiments/painted_courtyard/shadow_style.tres")
	shadow_style.apply_sun(lighting.sun)
	var contact_material: StandardMaterial3D=player.shadow.patch.material_override
	contact_material.albedo_color=Color(shadow_style.tint,shadow_style.opacity/.8)
	courtyard.bind_occlusion()
	# 用户确认生成资产直接按 1280×720 显示更合适；F2 仍可对比粗环境。
	environment_pixels.set_enabled(false,false)
	hud.notice.text="WASD 移动 · Shift 疾跑 · 空格跳跃 · C 下蹲 · F11 全屏 · F2 环境精度\nV 插画/简体 · F3 碰撞范围 · F4 蝴蝶落叶 · M 全院取景 · 1 院门 / 2 室内 / 3 树井 / 4 推车 · R 重开"
	last_feedback="小院美术实验 / 自由绕行观察 · 水桶与宝箱暂为场景物件"
	ready_to_test=true

func spawn_point() -> Vector3: return Vector3(.8,.1,13.6)
func level_title() -> String: return "林间小院 / 单视角绘画资产实验"
func update_camera_position() -> void:
	# 全院查看只平移相机、不缩小人物；移动时默认仍跟随玩家。
	var focus: Vector3=Vector3(0,2,5) if courtyard_overview else player.position+Vector3(0,1.8,-4.5)
	camera.position=snapped_camera_position(focus+camera.global_basis.z*26)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and ready_to_test:
		if event.physical_keycode==KEY_V:
			artwork=not artwork
			painting.set_enabled(artwork)
			courtyard.set_artwork(artwork)
			last_feedback="绘画外观" if artwork else "简单空间体积 / 碰撞保持不变"
		elif event.physical_keycode==KEY_F3:
			guides=not guides
			courtyard.show_collisions(guides)
		elif event.physical_keycode==KEY_F4:
			courtyard.ambience.visible=not courtyard.ambience.visible
			courtyard.ambience.animated=courtyard.ambience.visible
		elif event.physical_keycode==KEY_M:
			courtyard_overview=not courtyard_overview
		elif event.physical_keycode in [KEY_1,KEY_2,KEY_3,KEY_4]:
			courtyard_overview=false
			var stops: Array[Vector3]=[spawn_point(),Vector3(0,.1,0),Vector3(-3.0,.1,5.0),Vector3(3,.1,6.5)]
			player.position=stops[event.physical_keycode-KEY_1]
			player.velocity=Vector3.ZERO
	super._unhandled_input(event)
