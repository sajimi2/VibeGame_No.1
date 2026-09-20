extends "res://scripts/world/level.gd"
## 双屋回归夹具：验证共享绘画资源下的独立透视与物理，不作为第二条美术路线。
var cottage: Node3D
var second_cottage: Node3D
var painting: Node3D
var second_painting: Node3D

func _ready() -> void:
	encounter_enabled=false
	mission_enabled=false
	progress_enabled=false
	results_enabled=false
	super._ready()
	cottage.roof.observer=player
	second_cottage.roof.observer=player
	# 父类的延迟注册先完成，绘画层随后绑定最终墙材质副本。
	_install.call_deferred()

func _build_environment() -> void:
	box("Ground",Vector3(4,-.26,0),Vector3(32,.48,24),"grass")
	cottage=load("res://assets/environment/painted/cottage/structure/cottage.tscn").instantiate()
	add_child(cottage)
	second_cottage=load("res://assets/environment/painted/cottage/structure/cottage.tscn").instantiate()
	second_cottage.position=Vector3(9,0,0)
	add_child(second_cottage)

func spawn_point() -> Vector3: return Vector3(0,.1,5.2)

func _install() -> void:
	preload("res://assets/environment/painted/courtyard/shadow_style.tres").apply_sun(lighting.sun)
	painting=preload("res://scripts/presentation/painted_cottage.gd").new()
	cottage.add_child(painting)
	painting.setup(cottage)
	second_painting=preload("res://scripts/presentation/painted_cottage.gd").new()
	second_cottage.add_child(second_painting)
	second_painting.setup(second_cottage)
	hud.notice.text="WASD 移动 · Shift 疾跑 · 空格跳跃 · C 下蹲 · F2 环境精度\nV 插画/空间代理 · 1 门前 / 2 室内 / 3 屋后 / 4 第二栋 · F11 全屏 · R 重开"
	last_feedback="完整插画分层实验 / V 对比空间代理 · 门洞和碰撞保持原样"

func level_title() -> String: return "小屋实验 / 固定视角分层插画"

## 仅向房屋方向平移取景，避免出生时屋脊被窗口裁掉；角度、倍率与人物尺寸保持基准。
func update_camera_position() -> void:
	camera.position=snapped_camera_position(player.position+Vector3(0,1.8,-2.5)+camera.global_basis.z*26)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode==KEY_V and is_instance_valid(painting):
			painting.set_enabled(not painting.enabled)
			second_painting.set_enabled(painting.enabled)
			last_feedback="完整插画分层" if painting.enabled else "空间代理 / 不改变碰撞和透视"
			get_viewport().set_input_as_handled()
			return
		if event.physical_keycode in [KEY_1,KEY_2,KEY_3,KEY_4]:
			var stops: Array[Vector3]=[Vector3(0,.1,5.2),Vector3(0,.1,0),Vector3(0,.1,-3.9),Vector3(9,.1,5.2)]
			player.position=stops[event.physical_keycode-KEY_1]
			player.velocity=Vector3.ZERO
			get_viewport().set_input_as_handled()
			return
	# 测试定位与对比在本夹具处理，其余沿用正式输入。
	super._unhandled_input(event)
