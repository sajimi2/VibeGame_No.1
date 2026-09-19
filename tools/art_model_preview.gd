extends SubViewportContainer
## 工作台专用的三维观察窗；只读取源场景与姿态，不写资产、不参与游戏或离线出图。
var viewport: SubViewport
var world: Node3D
var camera: Camera3D
var rig: Node3D
var scene_path := ""
var active := false
var orbit := Vector2(0,deg_to_rad(-35))
var distance_scale := 3.0
var last_descriptor: Dictionary = {}

func _ready() -> void:
	stretch=true
	custom_minimum_size=Vector2(320,280)
	size_flags_horizontal=Control.SIZE_EXPAND_FILL
	size_flags_vertical=Control.SIZE_EXPAND_FILL
	mouse_default_cursor_shape=Control.CURSOR_DRAG
	viewport=SubViewport.new()
	viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	add_child(viewport)
	world=Node3D.new()
	viewport.add_child(world)
	var environment:=WorldEnvironment.new()
	environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR
	environment.environment.background_color=Color("202b36")
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color("b7c9dc")
	environment.environment.ambient_light_energy=.65
	world.add_child(environment)
	var sun:=DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-48,-32,0)
	sun.light_energy=1.1
	sun.shadow_enabled=true
	world.add_child(sun)
	var ground:=MeshInstance3D.new()
	var plane:=PlaneMesh.new()
	plane.size=Vector2(12,12)
	ground.mesh=plane
	ground.position.y=-.035
	var material:=StandardMaterial3D.new()
	material.albedo_color=Color("35454f")
	material.roughness=1
	ground.material_override=material
	world.add_child(ground)
	camera=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.current=true
	world.add_child(camera)
	resized.connect(_redraw)
	reset_camera()

## 关闭预览时停止子视口绘制；静止帧只在姿态、相机或尺寸变化时刷新。
func set_active(enabled: bool) -> void:
	active=enabled
	visible=enabled
	viewport.render_target_update_mode=SubViewport.UPDATE_ONCE if enabled else SubViewport.UPDATE_DISABLED

## 场景仅在切换来源时实例化；帧切换只采样已保存的骨骼动画，与左侧像素帧共用状态。
func show_frame(descriptor: Dictionary) -> String:
	if descriptor.is_empty():
		clear_model()
		return "该资产没有三维源模型。"
	var path: String=descriptor.scene
	if path!=scene_path or not is_instance_valid(rig):
		clear_model()
		var packed:=load(path) as PackedScene
		if packed==null: return "无法读取源模型："+path
		rig=packed.instantiate() as Node3D
		if rig==null or not rig.has_method("apply_state"):
			clear_model()
			return "源模型未提供姿态预览接口："+path
		world.add_child(rig)
		scene_path=path
	rig.apply_state(descriptor.state)
	rig.rotation.y=int(descriptor.state.get("direction",0))*PI/6
	var part: String=descriptor.get("part","full")
	# 分层可见性按源骨骼的元数据判断，不在查看器里硬编码玩家或敌人的节点名。
	for bone in rig.bones: bone.attachment.visible=part=="full" or bone.part==part
	last_descriptor=descriptor.duplicate(true)
	_redraw()
	return ""

func clear_model() -> void:
	if is_instance_valid(rig): rig.free()
	rig=null
	scene_path=""
	last_descriptor={}
	_redraw()

## 恢复为烘焙使用的观察方向；自由旋转只影响三维观察窗，不改变选中的图集朝向列。
func reset_camera() -> void:
	orbit=Vector2(0,deg_to_rad(-35))
	distance_scale=3.0
	_update_camera()

func _update_camera() -> void:
	camera.rotation=Vector3(orbit.y,orbit.x,0)
	camera.position=Vector3(0,.85,0)+camera.basis.z*6
	camera.size=distance_scale
	_redraw()

func _redraw() -> void:
	if active and is_instance_valid(viewport): viewport.render_target_update_mode=SubViewport.UPDATE_ONCE

## 鼠标输入限制在观察窗中，避免拖图集或修改握点时误转相机。
func _gui_input(event: InputEvent) -> void:
	if not active: return
	if event is InputEventMouseMotion and event.button_mask&MOUSE_BUTTON_MASK_LEFT:
		orbit.x-=event.relative.x*.008
		orbit.y=clampf(orbit.y-event.relative.y*.008,deg_to_rad(-85),deg_to_rad(20))
		_update_camera()
		accept_event()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			distance_scale=clampf(distance_scale*(.9 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1.1),1.0,6.0)
			_update_camera()
			accept_event()
