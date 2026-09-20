extends "res://scripts/world/level.gd"
## 环境构件独立预览，不接敌人/任务/存档；资源直接来自游戏使用的同一预制件。
func _ready() -> void:
	encounter_enabled=false
	mission_enabled=false
	progress_enabled=false
	results_enabled=false
	super._ready()
	camera.size=21
	hud.notice.text="WASD 查看构件 · Shift 疾跑 · 空格跳跃 · F1 名称 · F2 环境精度 · Esc 退出"
	last_feedback="环境资产库 / 编辑 assets/environment/prefabs 或材质 PNG 后重开查看"
func spawn_point() -> Vector3: return Vector3(0,.1,6)
func level_title() -> String: return "环境资产库 / 中世纪边境驿站"
func _build_environment() -> void:
	box("Floor",Vector3(0,-.25,0),Vector3(32,.5,28),"grass")
	var specs: Array=[["building",Vector3(-7,1.5,0)],["wall",Vector3(-1,1.2,0)],["tower",Vector3(6,2.2,0)],["crate",Vector3(-6,.7,6)],["wagon",Vector3(-2,.65,6)],["bridge",Vector3(5,0,7)]]
	for spec in specs:
		var piece: Node3D=load("res://assets/environment/prefabs/"+spec[0]+".tscn").instantiate()
		piece.position=spec[1]
		add_child(piece)
		_label(spec[0],spec[1]+Vector3.UP*2.8)
