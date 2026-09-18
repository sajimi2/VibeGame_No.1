class_name PixelWeaponVisual
extends Node3D
## 可拆卸的显示适配器：读取最终武器变换，把原模型换成像素纸片；不推进动作或伤害。
const Baker = preload("res://scripts/art/weapon_sprite_baker.gd")
const PixelShader = preload("res://scripts/presentation/pixel_weapon.gdshader")
const GpuFrame = preload("res://scripts/presentation/pixel_frame_gpu.gd")
const CACHE_LIMIT := 128
var source: MeshInstance3D
var camera: Camera3D
var light: DirectionalLight3D
var card: MeshInstance3D
var material: ShaderMaterial
var triangles: Array = []
static var cache: Dictionary = {}
var gpu_frame: Node
var original_shadows: Dictionary = {}
var enabled := true
var last_key := ""
var bake_usec := 0
var geometry_key := 0
var geometry_revision := -1
var frame_dirty := true

## 由武器拥有者创建，随源模型一起释放；相同模型只绑定一次，太阳由关卡显式传入。
static func attach(model: MeshInstance3D, view: Camera3D, sun: DirectionalLight3D=null) -> PixelWeaponVisual:
	var existing := model.get_node_or_null("PixelPresentation")
	if existing is PixelWeaponVisual: return existing
	var visual := PixelWeaponVisual.new()
	visual.name = "PixelPresentation"
	visual.set_meta("pixel_bake_ignore",true)
	model.add_child(visual)
	visual.setup(model,view,sun)
	return visual

## source 仍由战斗控制器持有；只改投影模式，关闭适配器或释放时可完整还原。
func setup(model: MeshInstance3D, view: Camera3D, sun: DirectionalLight3D) -> void:
	source = model
	camera = view
	light = sun
	refresh_geometry()
	for node in Baker.meshes(source):
		if node is GeometryInstance3D: original_shadows[node] = node.cast_shadow
	card = MeshInstance3D.new()
	card.name = "PixelWeaponCard"
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE*Baker.SIZE*Baker.PIXEL_SIZE
	card.mesh = quad
	material = ShaderMaterial.new()
	material.shader = PixelShader
	card.material_override = material
	card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(card)
	if DisplayServer.get_name()!="headless":
		gpu_frame = GpuFrame.new()
		add_child(gpu_frame)
		gpu_frame.set_triangles(triangles)
		gpu_frame.bind(material)
	set_enabled(true)
	process_priority = 30
	sync(1.0)

## 拉弓的弦形有离散版本；版本变化才重建 GPU 网格，并更新离线导出的几何键。
func refresh_geometry() -> void:
	geometry_revision = int(source.get_meta("pixel_revision",0))
	triangles = Baker.geometry(source)
	geometry_key = hash(triangles)
	if is_instance_valid(gpu_frame): gpu_frame.set_triangles(triangles)

func set_enabled(value: bool) -> void:
	enabled = value
	if enabled: last_key = ""
	elif is_instance_valid(gpu_frame): gpu_frame.suspend()
	for node in original_shadows:
		if is_instance_valid(node): node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if enabled else original_shadows[node]
	if is_instance_valid(card): card.visible = enabled

func _process(delta: float) -> void:
	sync(delta)

## 只向 GPU 提交最终姿态；平移每帧跟手，相同姿态和屏外武器不重复出图。
func sync(_delta: float) -> void:
	if not is_instance_valid(source) or not is_instance_valid(camera):
		if is_instance_valid(card): card.hide()
		return
	card.visible = enabled and source.is_visible_in_tree()
	if not card.visible:
		frame_dirty = true
		if is_instance_valid(gpu_frame): gpu_frame.suspend()
		return
	card.global_transform = Transform3D(camera.global_basis,source.global_position)
	# 留出整张武器图的边缘余量；屏外敌人继续模拟，只暂停看不见的烘焙工作。
	var viewport_size := get_viewport().get_visible_rect().size
	var margin := Baker.SIZE*Baker.PIXEL_SIZE/camera.size*viewport_size.y
	if camera.is_position_behind(source.global_position) or not Rect2(-Vector2.ONE*margin,viewport_size+Vector2.ONE*margin*2).has_point(camera.unproject_position(source.global_position)):
		frame_dirty = true
		if is_instance_valid(gpu_frame): gpu_frame.suspend()
		return
	if int(source.get_meta("pixel_revision",0))!=geometry_revision: refresh_geometry()
	var view := camera.global_basis.inverse()*source.global_basis
	var light_direction := camera.global_basis.inverse()*light.global_basis.z if is_instance_valid(light) else Vector3(0.3,0.8,0.5).normalized()
	var key := str(geometry_key,view.x.snapped(Vector3.ONE*0.002),view.y.snapped(Vector3.ONE*0.002),view.z.snapped(Vector3.ONE*0.002),light_direction.snapped(Vector3.ONE*0.01))
	if key==last_key and not frame_dirty: return
	last_key = key
	frame_dirty = false
	if is_instance_valid(gpu_frame): gpu_frame.draw(view,light_direction)

## CPU 烘焙仅供图集导出与离线验证，绝不由 _process 调用；同姿态仍共享有界缓存。
func capture_frame() -> Dictionary:
	if not is_instance_valid(source) or not is_instance_valid(camera): return {}
	if int(source.get_meta("pixel_revision",0))!=geometry_revision: refresh_geometry()
	var view := camera.global_basis.inverse()*source.global_basis
	var light_direction := camera.global_basis.inverse()*light.global_basis.z if is_instance_valid(light) else Vector3(0.3,0.8,0.5).normalized()
	var key := str(geometry_key,view.x.snapped(Vector3.ONE*0.002),view.y.snapped(Vector3.ONE*0.002),view.z.snapped(Vector3.ONE*0.002),light_direction.snapped(Vector3.ONE*0.01))
	if not cache.has(key):
		var start := Time.get_ticks_usec()
		var frame := Baker.bake(triangles,view,light_direction)
		bake_usec = Time.get_ticks_usec()-start
		if cache.size()>=CACHE_LIMIT: cache.erase(cache.keys()[0])
		cache[key] = frame
	return cache[key]

func _exit_tree() -> void:
	set_enabled(false)
