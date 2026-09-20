extends "res://scripts/world/waystation_blockout.gd"
## 仓库样板复用驿站地图与战斗，只提供本轮站位、出生点和美术装配，不读写正式进度。
var sample_art: Node3D
var combat_active:=true

func spawn_point() -> Vector3: return Vector3(5,.1,8)
func level_title() -> String: return "仓库与门前小院 / 美术样板"
func enemy_layout() -> Array:
	return [
		{"position":Vector3(5,1.8,-6),"tuning":HARD},
		{"position":Vector3(13,1.8,-8),"tuning":HARD},
		{"position":Vector3(19,1.8,-11),"ranged":true,"tuning":HARD}]

func _build_environment() -> void:
	sample_art=preload("res://scripts/presentation/warehouse_art_layer.gd").new()
	sample_art.name="SampleArt"
	add_child(sample_art)
	sample_art.setup(self)

func _ready() -> void:
	super._ready()
	hud.notice.text="WASD 移动 · Shift 疾跑 · 空格跳跃 · C 蹲射 · 左键近战 · 右键射箭 · I 换装\nV 新旧美术 · P 战斗/勘察 · 1 桥前 · 2 仓库内（勘察） · F2 环境精度 · F11 全屏 · R 重开"
	last_feedback="从木桥进入仓库 / V 对比美术 · P 切换勘察"

func start_encounter() -> void:
	await super.start_encounter()
	# 导航装配期间也可以按 P；晚出生的演员必须继承已经选择的勘察状态。
	if not combat_active: set_combat_active(false)

## 样板只覆盖短遭遇，仍由原敌人状态机处理发现、追击与攻击。
func _physics_process(_delta: float) -> void:
	player.safe_zone=not combat_active or player.position.distance_to(spawn_point())<2.1
	if player.safe_zone and player.hp>0: player.hp=player.max_hp
	update_camera_position()
	var alive:=0
	for enemy in get_tree().get_nodes_in_group("tactical_enemies"):
		if enemy.hp>0: alive+=1
	var message: String=("战斗 %d / 3 · "%alive if combat_active else "勘察 · ")+("生成美术" if sample_art.enabled else "原有美术")+" · "+last_feedback
	if player.hp<=0: message="你已倒下 · R 重开"
	hud.update_status(player.hp,player.max_hp,player.position.y,player.crouched,player.occluded,message)

## 勘察只冻结本场敌人行动；返回战斗保留生命与站位，R 才完整重置遭遇。
func set_combat_active(value: bool) -> void:
	combat_active=value
	for enemy in get_tree().get_nodes_in_group("tactical_enemies"):
		enemy.ai_enabled=value
		if enemy.hp<=0: continue
		if not value:
			enemy.velocity=Vector3.ZERO
			enemy.attack_time=0
			enemy.strike_pending=false
			enemy.volley_left=0
			enemy.state="guard"
			enemy.update_visuals(0)
	last_feedback="桥前营地恢复生命" if value else "1 桥前 · 2 仓库内 · 自由查看透视"

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode==KEY_V:
			sample_art.set_enabled(not sample_art.enabled)
			get_viewport().set_input_as_handled()
			return
		if event.physical_keycode==KEY_P:
			set_combat_active(not combat_active)
			get_viewport().set_input_as_handled()
			return
		if not combat_active and event.physical_keycode in [KEY_1,KEY_2]:
			player.position=spawn_point() if event.physical_keycode==KEY_1 else Vector3(13,1.9,-8)
			player.velocity=Vector3.ZERO
			player.reset_physics_interpolation()
			return
	super._unhandled_input(event)
