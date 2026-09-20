extends Node3D
## 关卡装配入口：创建各系统，并把它们需要的依赖传入。
## 子类提供地图几何、出生点和敌人布局，公共流程由本类执行。
const Actor = preload("res://scripts/actors/player.gd")
const Art = preload("res://scripts/presentation/tree_art.gd")
## 统一放大世界画面，便于看清角色细节；不改变模型尺寸、碰撞和攻击距离。
const VIEW_ZOOM := 1.2
var player: CharacterBody3D
var camera: Camera3D
var terrain: RefCounted
var hud: CanvasLayer
var stylized := true
var combat: Node3D
var last_feedback := "Shift 疾跑 · 空格跳跃 · E 取得密函 · 留意弓箭手的瞄准动作"
var encounter_enabled := true
var progression: Node
var progress_enabled := true
var mission_enabled := true
var archer: CharacterBody3D
var objective: Node3D
var guard: CharacterBody3D
var effects: Node3D
var routes: Node
var results_enabled := true
var run_flow: CanvasLayer
var lighting: Node3D
var environment_pixels: MeshInstance3D
var wall_occlusion: Node
const Lighting = preload("res://scripts/presentation/world_lighting.gd")

## Godot 在节点入树并就绪后调用此函数，依次装配地图、玩家、相机、界面与战斗。
## 先把依赖传给子系统，再安排延迟创建遭遇，避免初始化顺序错误。
func _ready() -> void:
	terrain = preload("res://scripts/world/terrain_builder.gd").new(self)
	if ProjectSettings.get_setting("tactical/testing",false): progress_enabled=false
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	get_window().content_scale_size = Vector2i(1280, 720)
	get_window().min_size = Vector2i(1280, 720)
	# 先让窗口/全屏等比例铺满；1280×720 到 1080p 需要 1.5 倍，整数取整会留下四周黑框。
	get_window().content_scale_stretch = Window.CONTENT_SCALE_STRETCH_FRACTIONAL
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	# 窗口控制独立于关卡生命周期，R 重开不丢失全屏前的窗口尺寸；不新增游戏全局状态。
	if not get_window().has_node("GameWindowMode"):
		var window_mode := preload("res://scripts/ui/window_mode.gd").new()
		window_mode.name = "GameWindowMode"
		get_window().add_child.call_deferred(window_mode)
	RenderingServer.set_default_clear_color(Color("202e36"))
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("202e36")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b9cbd4")
	environment.ambient_light_energy = 0.48
	environment_node.environment = environment
	add_child(environment_node)
	var sunlight := DirectionalLight3D.new()
	sunlight.rotation_degrees = Vector3(-55, -30, 0)
	sunlight.light_color = Color("ffe4b5")
	sunlight.light_energy = 0.8
	sunlight.shadow_enabled = true
	add_child(sunlight)
	lighting = Lighting.new()
	add_child(lighting)
	lighting.pixel_material=Lighting.pixel_pass(self)
	lighting.setup(sunlight,environment)
	_build_environment()
	effects = preload("res://scripts/presentation/encounter_effects.gd").new()
	add_child(effects)
	player = Actor.new()
	player.effects = effects
	player.name = "Explorer"
	player.spawn = spawn_point()
	add_child(player)
	player.reset_position()
	camera = Camera3D.new()
	camera.name = "FixedAngleCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 17.0 / VIEW_ZOOM
	camera.far = 160
	process_physics_priority = 10
	add_child(camera)
	camera.rotation_degrees = Vector3(-35,25,0)
	update_camera_position()
	camera.current = true
	player.camera = camera
	environment_pixels = preload("res://scripts/presentation/environment_pixel_pass.gd").new()
	environment_pixels.name = "EnvironmentPixelPass"
	camera.add_child(environment_pixels)
	wall_occlusion=preload("res://scripts/presentation/wall_occlusion.gd").new()
	wall_occlusion.name="WallOcclusion"
	wall_occlusion.observer=player
	wall_occlusion.camera=camera
	add_child(wall_occlusion)
	# 等待场景构件完成生成；关卡只注入依赖，不持有遮挡采样或材质渐变逻辑。
	wall_occlusion.register_branch.call_deferred(self)
	hud = preload("res://scripts/ui/game_hud.gd").new()
	add_child(hud)
	hud.setup(level_title())
	_build_targets()
	combat = preload("res://scripts/combat/player_combat.gd").new()
	add_child(combat)
	combat.sunlight = sunlight
	combat.setup(player, func(message: String): last_feedback = message)
	# 延迟调用让当前装配先结束，随后再等待物理世界同步。
	if encounter_enabled: start_encounter.call_deferred()

## 玩家移动后更新跟随相机，并把本帧状态传给 HUD。
func _physics_process(_delta: float) -> void:
	update_camera_position()
	var message := "你已倒下 · 按 R 重置" if player.hp <= 0 else "守卫已击败 · 按 R 重置遭遇" if not mission_enabled and is_instance_valid(guard) and guard.hp <= 0 else last_feedback
	hud.update_status(player.hp, player.max_hp, player.position.y, player.crouched, player.occluded, message)

## 处理关卡级快捷键：重开、标注开关、明暗对比与退出。
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_R: get_tree().reload_current_scene()
		if event.physical_keycode == KEY_F1:
			for label in get_tree().get_nodes_in_group("sample_annotations"): label.visible = not label.visible
		if event.physical_keycode == KEY_B: toggle_shading()
		if event.physical_keycode == KEY_ESCAPE: get_tree().quit()

## 保持固定俯仰与距离跟随玩家，只对相机位置做像素对齐。
func update_camera_position() -> void:
	camera.position = snapped_camera_position(player.position + camera.global_basis.z * 26.0)

## 将世界位置转到相机坐标系，对齐屏幕像素网格后再转回世界。
func snapped_camera_position(desired: Vector3) -> Vector3:
	# 只将渲染相机对齐到像素步长；物理位置和瞄准坐标保持连续。
	var pixel := camera.size / float(get_window().content_scale_size.y)
	var local := camera.global_basis.inverse() * desired
	local.x = snappedf(local.x, pixel)
	local.y = snappedf(local.y, pixel)
	return camera.global_basis * local

## 切换地形材质的分段明暗，便于对比视觉效果。
func toggle_shading() -> void:
	stylized = not stylized
	for material_value in terrain.materials.values():
		material_value.set_shader_parameter("banded",stylized)
	last_feedback = "分段明暗" if stylized else "连续明暗 · 对比模式"

## 等待地形进入物理世界后建立导航、敌人、任务、成长与结算，并连接依赖。
func start_encounter() -> void:
	await get_tree().physics_frame
	await get_tree().process_frame
	routes = preload("res://scripts/world/terrain_routes.gd").new()
	add_child(routes)
	routes.build(get_world_3d(),navigation_bounds())
	for spec in enemy_layout():
		var enemy=preload("res://scripts/actors/creature.gd").new() if spec.has("creature") else preload("res://scripts/actors/enemy.gd").new()
		if spec.has("creature"): enemy.profile=load("res://data/enemies/"+str(spec.creature)+".tres")
		enemy.art_id=spec.get("art_id","")
		enemy.ranged=spec.get("ranged",false)
		enemy.tuning=spec.get("tuning",enemy.tuning)
		enemy.max_hp=enemy.tuning.archer_health if enemy.ranged else enemy.tuning.guard_health
		enemy.hp=enemy.max_hp
		enemy.home=spec.position
		enemy.position=enemy.home+Vector3.UP*0.05
		enemy.player=player
		enemy.camera=camera
		enemy.sunlight=lighting.sun
		enemy.routes=routes
		enemy.effects=effects
		add_child(enemy)
		if enemy.ranged and not is_instance_valid(archer):
			archer=enemy
			enemy.name="OutpostArcher"
		elif not enemy.ranged and not is_instance_valid(guard): guard=enemy
	# 静态寻路排除所有敌人，避免将队友身体采样为路线端点；实际移动仍保留碰撞。
	for enemy in get_tree().get_nodes_in_group("tactical_enemies"):
		for teammate in get_tree().get_nodes_in_group("tactical_enemies"):
			if not enemy.navigation_excluded.has(teammate.get_rid()): enemy.navigation_excluded.append(teammate.get_rid())
	if mission_enabled:
		objective=preload("res://scripts/world/objective.gd").new()
		objective.player=player
		objective.exit_point=spawn_point()*Vector3(1,0,1)
		objective.pickup_point=objective_point()
		add_child(objective)
		progression=preload("res://scripts/progression/camp_progress.gd").new()
		progression.setup(player, combat)
		progression.persist=progress_enabled
		add_child(progression)
		objective.progress=progression
		if results_enabled:
			run_flow=preload("res://scripts/ui/run_screen.gd").new()
			run_flow.setup(player, objective, progression, combat_hint)
			add_child(run_flow)

## 地图子类覆盖这些配置接口；坐标均使用当前关卡的三维坐标。
func spawn_point() -> Vector3:
	return Vector3.ZERO

func objective_point() -> Vector3:
	return Vector3.ZERO

func navigation_bounds() -> Rect2:
	return Rect2(-15, -15.6, 30, 31.2)

func level_title() -> String:
	return "Outpost RPG"

func enemy_layout() -> Array:
	return []

func combat_hint() -> String: return ""

## 以下薄接口统一委托给 terrain_builder，供地图脚本复用几何构造。
func material(kind: String) -> ShaderMaterial:
	return terrain.material(kind)

func box(label: String, center: Vector3, size: Vector3, kind: String, layers: int = 13) -> StaticBody3D:
	return terrain.box(label, center, size, kind, layers)

func ramp(label: String, origin: Vector3, width: float, length: float, rise: float) -> void:
	terrain.ramp(label, origin, width, length, rise)

func natural_ledge(label: String, origin: Vector3, outline: PackedVector2Array, height: float) -> void:
	terrain.natural_ledge(label, origin, outline, height)

func _label(text: String, where: Vector3) -> void:
	terrain._label(text, where)

## 地图子类在此生成场景文件之外的地形和装饰。
func _build_environment() -> void:
	pass

## 由试验场按需生成训练靶，正式战场可沿用空实现。
func _build_targets() -> void:
	pass
