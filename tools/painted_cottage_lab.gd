extends "res://tools/cottage_art_lab.gd"
## 继承原小屋实验的物理与相机；只加插画表现及测试跳转，不替换正式关卡。
var painting: Node3D
var second_painting: Node3D

func _ready() -> void:
	super._ready()
	# 父类的延迟注册先完成，绘画层随后绑定最终墙材质副本。
	_install.call_deferred()

func _install() -> void:
	painting=preload("res://scripts/presentation/painted_cottage.gd").new()
	cottage.add_child(painting)
	painting.setup(cottage)
	second_painting=preload("res://scripts/presentation/painted_cottage.gd").new()
	second_cottage.add_child(second_painting)
	second_painting.setup(second_cottage)
	hud.notice.text="WASD 移动 · Shift 疾跑 · 空格跳跃 · C 下蹲 · F2 环境精度\nV 分层插画/旧贴面 · 1 门前 / 2 室内 / 3 屋后 / 4 第二栋 · F11 全屏 · R 重开"
	last_feedback="完整插画分层实验 / V 对比旧贴面 · 门洞和碰撞保持原样"

func level_title() -> String: return "小屋实验 / 固定视角分层插画"

## 仅向房屋方向平移取景，避免出生时屋脊被窗口裁掉；角度、倍率与人物尺寸保持基准。
func update_camera_position() -> void:
	camera.position=snapped_camera_position(player.position+Vector3(0,1.8,-2.5)+camera.global_basis.z*26)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode==KEY_V and is_instance_valid(painting):
			painting.set_enabled(not painting.enabled)
			second_painting.set_enabled(painting.enabled)
			last_feedback="完整插画分层" if painting.enabled else "旧方案：生成表面纹理贴在简模上"
			get_viewport().set_input_as_handled()
			return
		if event.physical_keycode in [KEY_1,KEY_2,KEY_3,KEY_4]:
			var stops: Array[Vector3]=[Vector3(0,.1,5.2),Vector3(0,.1,0),Vector3(0,.1,-3.9),Vector3(9,.1,5.2)]
			player.position=stops[event.physical_keycode-KEY_1]
			player.velocity=Vector3.ZERO
			get_viewport().set_input_as_handled()
			return
	# 父实验的 V/1/2 已在上方处理，其余沿用正式移动/窗口输入。
	super._unhandled_input(event)
