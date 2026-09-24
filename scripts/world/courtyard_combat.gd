extends "res://scripts/world/painted_courtyard.gd"
@export var story_mode := true
var region: Node3D
const Region=preload("res://scripts/world/woodpath_region.gd")
## 正式战斗复用已验收的小院装配；美术实验入口仍保持无敌人的观察模式。
func _ready() -> void:
	combat_mode=true
	if story_mode: outskirts_mode=2
	super._ready()
func level_title() -> String: return "林间小院 / 失踪信使" if story_mode else "林间小院 / 剑与弓"
func create_objective() -> Node3D:
	return preload("res://scripts/world/woodpath_story.gd").new() if story_mode else super.create_objective()
func _build_environment() -> void:
	super._build_environment()
	if story_mode:
		region=Region.new()
		region.name="WoodpathRegion"
		add_child(region)
		# 已有小院的三个树位换新画稿，井、房屋与碰撞规则继续沿用。
		for old in courtyard.props.duplicate():
			if old.asset_id=="oak":
				region.place("tree_a" if old.name=="WestOak" else "tree_b" if old.name=="BackOak" else "tree_c",old.position,.95)
				courtyard.props.erase(old)
				old.queue_free()
			elif old.name=="OpenChest":
				courtyard.props.erase(old)
				old.queue_free()
func _finish() -> void:
	super._finish()
	if story_mode:
		region.bind_occlusion()
		# 像素密度由资产自身控制；整屏二次缩小会损伤人物与场景文字，因此不再装配。
		environment_pixels.unified_world=true
		last_feedback="小院是安全营地；沿东面林路调查失踪信使。"
		hud.notice.text="WASD 移动 · Shift 疾跑 · Alt 翻滚 · 左键攻击 · 右键格挡\n1–5 换武器 · I 行囊 / 日志 · E 交谈 / 搜查 · 滚轮缩放 · F11 全屏"
		var music := preload("res://scripts/presentation/woodpath_music.gd").new()
		add_child(music)
func objective_point() -> Vector3: return Region.SPOTS.satchel if story_mode else Vector3(.5,0,-1.0)
func navigation_bounds() -> Rect2: return Rect2(-10,-27,87,54) if story_mode else Rect2(-10,-12,52,36)
func enemy_layout() -> Array:
	if story_mode:
		var tuning:=preload("res://scripts/combat/enemy_tuning.gd").new()
		tuning.leash_distance=14.0
		return [{"position":Vector3(33,0,10),"tuning":tuning},{"position":Vector3(54,0,-2),"tuning":tuning},{"position":Vector3(65,0,-10),"ranged":true,"tuning":tuning}]
	return [{"position":Vector3(-1.0,0,7.0)}, {"position":Vector3(2.3,0,3.2)}, {"position":Vector3(3.6,0,-1.2),"ranged":true}]
func combat_hint() -> String: return " "

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if story_mode and is_instance_valid(hud):
		var area:="林间小院" if player.position.x<10 else "灰榆驿站" if player.position.x>50 and player.position.z<1 else "北侧林径" if player.position.z<0 else "南侧归途" if player.position.x>45 and player.position.z>10 else "旧林路"
		hud.title.text=area+" / 失踪信使"
