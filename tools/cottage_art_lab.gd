extends "res://scripts/world/level.gd"
## 小屋实验沿用正式移动、相机和遮挡装配，只关闭遭遇/任务/进度；不写玩家存档。
var cottage: Node3D
var second_cottage: Node3D

func _ready() -> void:
	encounter_enabled=false
	mission_enabled=false
	progress_enabled=false
	results_enabled=false
	super._ready()
	cottage.roof.observer=player
	second_cottage.roof.observer=player
	hud.notice.text="WASD 移动 · Shift 疾跑 · 空格跳跃 · C 下蹲 · F2 环境精度\nV 灰模/美术 · 1/2 两栋门前 · R 重开 · F11 全屏/窗口 · Esc 退出"
	last_feedback="生成美术已贴到简模 / V 对比 · 1/2 查看同一预制件复用"

func _build_environment() -> void:
	box("Ground",Vector3(4,-.26,0),Vector3(32,.48,24),"grass")
	cottage=load("res://assets/environment/experiments/cottage/cottage.tscn").instantiate()
	add_child(cottage)
	second_cottage=load("res://assets/environment/experiments/cottage/cottage.tscn").instantiate()
	second_cottage.position=Vector3(9,0,0)
	add_child(second_cottage)
	# 地板比外地面高 2cm，避免共面闪烁；中性底色便于看轮廓和保留接地阴影。
	var ground:=get_node("Ground")
	var ground_color:=Image.create(1,1,false,Image.FORMAT_RGB8)
	ground_color.fill(Color("667475"))
	var ground_material: ShaderMaterial=cottage.gray_material.duplicate()
	ground_material.set_shader_parameter("surface_texture",ImageTexture.create_from_image(ground_color))
	for node in ground.get_children():
		if node is MeshInstance3D: node.material_override=ground_material

func spawn_point() -> Vector3: return Vector3(0,.1,5.2)
func level_title() -> String: return "小屋实验 / 简模空间与生成美术"

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode==KEY_V:
			var enabled: bool=not cottage.art_enabled
			cottage.set_art_enabled(enabled)
			second_cottage.set_art_enabled(enabled)
			last_feedback="生成美术" if enabled else "原始简模 / 碰撞和透视分组不变"
		if event.physical_keycode in [KEY_1,KEY_2]:
			player.position=spawn_point()+Vector3(9 if event.physical_keycode==KEY_2 else 0,0,0)
			player.velocity=Vector3.ZERO
	super._unhandled_input(event)
