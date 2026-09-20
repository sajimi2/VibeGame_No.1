extends "res://scripts/world/level.gd"
## 驿站战斗试玩：沿用已验收碰撞与混合敌人；可关闭战斗回到空间勘察，不读写真实成长。
@export var combat_enabled := true
const HARD = preload("res://data/encounters/waystation_hard.tres")
var battle_ready := false
var overview := false
var review_labels: Array[Label3D] = []
const STOPS := [Vector3(0,0.1,32), Vector3(0,0.1,10), Vector3(5,1.9,-9), Vector3(0,0.1,-27), Vector3(-40,0.1,25)]

func spawn_point() -> Vector3: return STOPS[0]
func navigation_bounds() -> Rect2: return Rect2(-50,-38,76,76)
func level_title() -> String: return "废弃边境驿站 / 强化遭遇" if combat_enabled else "废弃边境驿站 / 空间勘察 · 无战斗"

## 四组混合驻军，地图只提供站位、物种和难度，不复制各敌人的 AI。
func enemy_layout() -> Array:
	if not combat_enabled: return []
	var layout := [
		{"position":Vector3(-40,0,15),"creature":"slime"},
		{"position":Vector3(-43,0,7),"creature":"goblin"},
		{"position":Vector3(0,0,12)},
		{"position":Vector3(7,0,8),"creature":"goblin"},
		{"position":Vector3(12,0,4),"ranged":true},
		{"position":Vector3(13,1.8,-9)},
		{"position":Vector3(18,1.8,-7),"ranged":true},
		{"position":Vector3(0,0,-25),"creature":"golem"},
		{"position":Vector3(6,0,-28),"creature":"slime"},
		{"position":Vector3(5,0,-31),"ranged":true}]
	for spec in layout: spec.tuning=HARD
	return layout

## 关闭任务装配，使 F6 勘察与正式 F5 关卡、玩家真实存档完全独立。
func _ready() -> void:
	encounter_enabled = combat_enabled
	mission_enabled = false
	progress_enabled = false
	results_enabled = false
	super._ready()
	camera.far = 240
	hud.notice.text = "WASD 移动 · Shift 疾跑 · 空格跳跃 · C 下蹲 · M 全图/步行\n1 入口 · 2 外院 · 3 高台 · 4 内院 · 5 野地 · F1 标注 · F2 环境精度 · R 返回起点 · F11 全屏/窗口 · Esc 退出"
	last_feedback = "土路 / 木架桥 / 石木驿站；被屋檐遮挡时局部透视。M 看全图，1—5 跳转（5 野地）。"
	for marker in $ReviewMarkers.get_children():
		_label(str(marker.get_meta("caption",marker.name)),marker.position)
		review_labels.append(get_child(get_child_count()-1))
	for label in review_labels:
		label.visible = true
		label.font_size = 20
		label.pixel_size = 0.016
		label.set_meta("full_caption",label.text)
	player.safe_zone = true
	for roof in $Roofs.get_children(): roof.observer = player
	if combat_enabled:
		hud.notice.text="WASD 移动 · Shift 疾跑 · 空格跳跃 · C 蹲射 · 左键近战 · 右键射箭\nI 背包换装 · Ctrl 辅瞄 · R 重新挑战 · F1 标注 · F2 环境精度 · F11 全屏/窗口 · Esc 退出"
		last_feedback="I 换装 · 营地恢复生命"
		for label in review_labels: label.hide()
		for child in $Cover.get_children():
			if str(child.name).begins_with("EncounterDummy") or str(child.name).begins_with("DummyFoot"): child.hide()
		_label("营地 / 靠近恢复生命 · I 换装",spawn_point()+Vector3.UP)
		var camp_label: Label3D=get_child(get_child_count()-1)
		camp_label.pixel_size=0.012
		camp_label.show()

## 公共装配负责导航和演员；本关只补临时装备，任务与真实进度仍不接入。
func start_encounter() -> void:
	await super.start_encounter()
	progression=preload("res://scripts/progression/camp_progress.gd").new()
	progression.setup(player,combat)
	progression.persist=false
	add_child(progression)
	var cleaver := ItemInstance.new()
	cleaver.instance_id="waystation_trial_cleaver"
	cleaver.definition_id=&"great_cleaver"
	progression.inventory.try_add(cleaver)
	battle_ready=true

## 全图仍保持固定俯角，避免改变十二朝向角色的烘焙投影基准。
func update_camera_position() -> void:
	if overview:
		camera.position = Vector3(-12,0,-1) + camera.global_basis.z * 110
	else:
		super.update_camera_position()

## 战斗时更新安全营地与剩余人数；勘察时沿用普通 HUD 和区域标注。
func _physics_process(delta: float) -> void:
	if combat_enabled:
		player.safe_zone=player.position.distance_to(spawn_point())<2.1
		if player.safe_zone and player.hp>0: player.hp=player.max_hp
		update_camera_position()
		var alive := 0
		for enemy in get_tree().get_nodes_in_group("tactical_enemies"):
			if enemy.hp>0: alive+=1
		var message := "正在布置遭遇…"
		if battle_ready:
			message="剩余 %d / 10 · "%alive+last_feedback
			if alive==0: message="10 名敌人已击败 · R 重开"
		if player.hp<=0: message="你已倒下 · R 重新挑战"
		hud.update_status(player.hp,player.max_hp,player.position.y,player.crouched,player.occluded,message)
		return
	if player.position.y < -4: move_to_stop(0)
	super._physics_process(delta)
	for label in review_labels:
		label.modulate.a = 1.0 if overview or player.position.distance_to(label.position)<19 else 0.0

## 全图期间停止角色输入，防止观察地图时在画面外移动；回到步行恢复原有视野大小。
func set_overview(value: bool) -> void:
	overview = value
	camera.size = 92.0 if overview else 17.0 / VIEW_ZOOM
	player.velocity = Vector3.ZERO
	player.set_physics_process(not overview)
	player.set_process_unhandled_input(not overview)
	combat.set_physics_process(not overview)
	combat.set_process_unhandled_input(not overview)
	# 全图用短标签补偿远距离字号；步行保留尺寸说明，避免大字盖住人物。
	for label in review_labels:
		label.pixel_size = 0.09 if overview else 0.016
		var full: String = label.get_meta("full_caption")
		label.text = full.split(" / ")[0] if overview else full
	update_camera_position()
	last_feedback = "全图：土路连接主路与侧路，西侧为林间野地。M 返回步行。" if overview else "土路 / 木架桥 / 石木驿站；被屋檐遮挡时局部透视。M 看全图，1—5 跳转（5 野地）。"

## 只供空间勘察跳转；先退出全图，再清空速度，目标均为已验证的可站立面。
func move_to_stop(index: int) -> void:
	set_overview(false)
	player.position = STOPS[index]
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	update_camera_position()

func _unhandled_input(event: InputEvent) -> void:
	if combat_enabled:
		super._unhandled_input(event)
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_M:
			set_overview(not overview)
			get_viewport().set_input_as_handled()
			return
		if event.physical_keycode >= KEY_1 and event.physical_keycode <= KEY_5:
			move_to_stop(event.physical_keycode-KEY_1)
			get_viewport().set_input_as_handled()
			return
	super._unhandled_input(event)
