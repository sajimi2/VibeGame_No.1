extends "res://scripts/world/level.gd"
## 已确认绘画路线的可运行基准；复用移动/相机/遮挡，当前只编排院子与查看快捷键。
@export var combat_mode := false
@export var meadow_seed := 240920
@export_enum("分层平台","旧连续缓坡","平地探索") var outskirts_mode:=0
@export var terrace_seed:=0
var cottage: Node3D
var painting: Node3D
var courtyard: Node3D
var guides:=false
var artwork:=true
var ready_to_test:=false
var courtyard_overview:=false
var rolling_meadow: StaticBody3D
var terrace_ground: StaticBody3D
const DEFAULT_CAMERA_SIZE:=17.0/VIEW_ZOOM
const ZOOM_DAMPING:=12.0
var camera_size_target:=DEFAULT_CAMERA_SIZE

func _ready() -> void:
	encounter_enabled=combat_mode
	mission_enabled=combat_mode
	progress_enabled=combat_mode
	results_enabled=combat_mode
	super._ready()
	cottage.roof.observer=player
	_finish.call_deferred()

func _build_environment() -> void:
	# 实战小院东侧由地形模块接替原平板；纯美术基准保持原始院景。
	var ground:=box("Meadow",Vector3(-8 if combat_mode else 0,-.27,4),Vector3(32 if combat_mode else 48,.5,48),"grass")
	var ground_material:=ShaderMaterial.new()
	ground_material.shader=preload("res://scripts/presentation/courtyard_ground.gdshader")
	ground_material.set_shader_parameter("meadow",load("res://assets/environment/painted/courtyard/textures/meadow.png"))
	ground_material.set_shader_parameter("earth",load("res://assets/environment/painted/courtyard/textures/earth.png"))
	ground_material.set_shader_parameter("meadow_extension",combat_mode)
	ground_material.set_shader_parameter("woodpath_region",combat_mode and outskirts_mode==2)
	if combat_mode and outskirts_mode==2:
		ground_material.set_shader_parameter("woodpath_segments",preload("res://scripts/world/woodpath_region.gd").road_segments())
		ground_material.set_shader_parameter("meadow",load("res://assets/environment/painted/woodpath/unified/source/grass.png"))
	for child in ground.get_children():
		if child is MeshInstance3D: child.material_override=ground_material
	if combat_mode:
		if outskirts_mode==1:
			rolling_meadow=preload("res://scripts/world/rolling_meadow.gd").new()
			rolling_meadow.terrain_seed=meadow_seed
			rolling_meadow.name="RollingMeadow"
			add_child(rolling_meadow)
			rolling_meadow.surface.material_override=ground_material
			ground_material.set_shader_parameter("climb_path",rolling_meadow.climb_path())
		elif outskirts_mode==0:
			ground_material.set_shader_parameter("relief_strength",0.0)
			terrace_ground=preload("res://scripts/world/terrace_ground.gd").new()
			terrace_ground.name="TerraceGround"
			terrace_ground.terrain_seed=terrace_seed
			add_child(terrace_ground)
		else:
			# 当前探索篇章停用已否定的粗格实验，保留代码供回归；不恢复旧缓坡。
			ground_material.set_shader_parameter("relief_strength",0.0)
			var flat:=box("ExplorationMeadow",Vector3(28,-.27,4),Vector3(40,.5,48),"grass")
			for child in flat.get_children():
				if child is MeshInstance3D: child.material_override=ground_material
		# 相机仍按原倍率跟随，外围留足地面背景，避免站上丘顶便看到地表截断。
		for area in [Rect2(-64,-60,72,40),Rect2(-64,28,72,40),Rect2(-64,-20,40,48),Rect2(8,-60,72,40),Rect2(8,28,72,40),Rect2(48,-20,32,48)]:
			var center: Vector2=area.get_center()
			var margin:=box("MeadowMargin",Vector3(center.x,-.27,center.y),Vector3(area.size.x,.5,area.size.y),"grass")
			for child in margin.get_children():
				if child is MeshInstance3D: child.material_override=ground_material
	cottage=load("res://assets/environment/painted/cottage/structure/cottage.tscn").instantiate()
	cottage.name="Cottage"
	add_child(cottage)
	courtyard=preload("res://scripts/presentation/painted_courtyard.gd").new()
	courtyard.name="Courtyard"
	add_child(courtyard)
	if rolling_meadow!=null: courtyard.extend_meadow(rolling_meadow)
	if terrace_ground!=null: courtyard.extend_terraces(terrace_ground)

## 延迟到原墙注册之后绑定，绘画层不取代控制器的状态所有权。
func _finish() -> void:
	painting=preload("res://scripts/presentation/painted_cottage.gd").new()
	cottage.add_child(painting)
	painting.setup(cottage)
	# 环境美术投影与人物实时投影共用白天光向；不再保留第二个时间推算方向。
	var shadow_style=preload("res://assets/environment/painted/courtyard/shadow_style.tres")
	shadow_style.apply_sun(lighting.sun)
	if terrace_ground!=null: terrace_ground.set_light_direction(lighting.sun.global_basis.z)
	if rolling_meadow!=null:
		# 坡面明暗沿用统一光向；只增强地表转折，不改人物和物件投影。
		rolling_meadow.surface.material_override.set_shader_parameter("terrain_light",lighting.sun.global_basis.z)
	var contact_material: StandardMaterial3D=player.shadow.patch.material_override
	contact_material.albedo_color=Color(shadow_style.tint,shadow_style.opacity/.8)
	courtyard.bind_occlusion()
	# 用户确认生成资产直接按 1280×720 显示更合适；F2 仍可对比粗环境。
	environment_pixels.set_enabled(false,false)
	hud.notice.text="WASD 移动 · Shift 疾跑 · 空格跳跃 · C 下蹲 · F11 全屏 · F2 环境精度\nV 插画/简体 · F3 碰撞范围 · F4 蝴蝶落叶 · M 全院取景 · 1 院门 / 2 室内 / 3 树井 / 4 推车 · R 重开"
	last_feedback="小院美术实验 / 自由绕行观察 · 水桶与宝箱暂为场景物件"
	if combat_mode:
		hud.notice.text="WASD 移动 · Shift 疾跑 · Alt 翻滚 · 空格跳跃 · 左键攻击 · 按住右键格挡\n1–5 换武器 · I 背包 · E 接取/取信/交付 · 滚轮缩放 · R 重开 · F11 全屏"
		last_feedback="院门外沿土路向右 · 分层平台与凹坑 / V 灰模 · F3 网格" if terrace_ground!=null else "院门外沿土路向右 · 旧缓坡对照"
	ready_to_test=true

func spawn_point() -> Vector3: return Vector3(.8,.1,13.6)
func level_title() -> String: return "林间小院 / 单视角绘画资产实验"

## 滚轮只设目标视野，按时间指数收敛；在跟随和遮挡采样前更新，不改角色世界尺寸。
func _physics_process(delta: float) -> void:
	camera.size=lerpf(camera.size,camera_size_target,1.0-exp(-ZOOM_DAMPING*delta))
	if absf(camera.size-camera_size_target)<.001: camera.size=camera_size_target
	super._physics_process(delta)

func update_camera_position() -> void:
	# 正常跟随对准身体中部；全院查看保留独立焦点，蹲下时不引入镜头上下跳动。
	var focus: Vector3=Vector3(0,2,5) if courtyard_overview else player.position+Vector3.UP*(Actor.STAND_HEIGHT*.5)
	camera.position=snapped_camera_position(focus+camera.global_basis.z*26)

func _unhandled_input(event: InputEvent) -> void:
	# 走未处理输入，让背包和按钮先消费滚轮；暂停时不积累缩放目标。
	if event is InputEventMouseButton and event.pressed and ready_to_test and not get_tree().paused:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			var steps: float=event.factor if event.factor>0 else 1.0
			var direction: float=-1.0 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1.0
			camera_size_target=clampf(camera_size_target*pow(1.12,direction*steps),DEFAULT_CAMERA_SIZE*.5,DEFAULT_CAMERA_SIZE*2.0)
			get_viewport().set_input_as_handled()
			return
	if event is InputEventKey and event.pressed and not event.echo and ready_to_test:
		if event.physical_keycode==KEY_V:
			artwork=not artwork
			painting.set_enabled(artwork)
			courtyard.set_artwork(artwork)
			if terrace_ground!=null: terrace_ground.set_artwork(artwork)
			last_feedback="绘画外观" if artwork else "简单空间体积 / 碰撞保持不变"
		elif event.physical_keycode==KEY_F3:
			guides=not guides
			courtyard.show_collisions(guides)
			if rolling_meadow!=null: rolling_meadow.surface.material_override.set_shader_parameter("terrain_guides",guides)
			if terrace_ground!=null: terrace_ground.set_guides(guides)
		elif event.physical_keycode==KEY_F4:
			courtyard.ambience.visible=not courtyard.ambience.visible
			courtyard.ambience.animated=courtyard.ambience.visible
		elif event.physical_keycode==KEY_M:
			courtyard_overview=not courtyard_overview
		elif not combat_mode and event.physical_keycode in [KEY_1,KEY_2,KEY_3,KEY_4]:
			courtyard_overview=false
			var stops: Array[Vector3]=[spawn_point(),Vector3(0,.1,0),Vector3(-3.0,.1,5.0),Vector3(3,.1,6.5)]
			player.position=stops[event.physical_keycode-KEY_1]
			player.velocity=Vector3.ZERO
	super._unhandled_input(event)
