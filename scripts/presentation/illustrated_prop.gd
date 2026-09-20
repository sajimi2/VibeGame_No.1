extends Node3D
## 单视角画稿负责轮廓；独立盒/柱负责物理。近似深度体积和碰撞体积分别配置，避免树冠堵路。
const FOLDER="res://assets/environment/painted/courtyard/"
const PAINT=preload("res://scripts/presentation/illustrated_prop.gdshader")
const PARAMETERS=preload("res://scripts/presentation/occlusion_style.gd").WALL_PARAMETERS
var asset_id: String
var spec: Dictionary
var art: MeshInstance3D
var shadow: MeshInstance3D
var proxy: MeshInstance3D
var body: StaticBody3D
var guide: MeshInstance3D
var art_material: ShaderMaterial
var source_material: ShaderMaterial
var artwork:=true
var collision_guides:=false
var visual_sway:=Vector3.ZERO

## 调用者先入树再装配。尺寸与摆放从资产目录读入，同一图片可以实例化为多个物件。
func setup(id: String,definition: Dictionary,baked: Dictionary,scale_factor: float=1.0) -> void:
	asset_id=id
	spec=definition
	process_physics_priority=30
	var size:=Vector2(float(spec.width),float(spec.width)*float(baked.aspect))*scale_factor
	var basis:=Basis.from_euler(Vector3(deg_to_rad(-35),deg_to_rad(25),0))
	var anchor:=Vector2(spec.anchor[0],spec.anchor[1])
	var texture: Texture2D=load(FOLDER+"textures/"+id+".png")
	art=MeshInstance3D.new()
	art.name="Illustration"
	var quad:=QuadMesh.new()
	quad.size=size
	quad.subdivide_depth=12
	art.mesh=quad
	art.basis=basis
	art.position=basis*Vector3((.5-anchor.x)*size.x,(anchor.y-.5)*size.y,0)
	art.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	art_material=ShaderMaterial.new()
	art_material.shader=PAINT
	if spec.shape=="none":
		art_material.shader=preload("res://scripts/presentation/ground_decoration.gdshader")
		art_material.render_priority=-110
	art_material.set_shader_parameter("illustration",texture)
	art_material.set_shader_parameter("prop_origin",global_position)
	art_material.set_shader_parameter("foot_uv",anchor.y)
	art_material.set_shader_parameter("to_camera",basis.z)
	art_material.set_shader_parameter("depth_size",vector(spec.depth_box)*scale_factor)
	# 树冠外扩只影响轮廓，不能把树前人物判到巨大盒子的内部；花草只占地表深度。
	if spec.shape!="none": art_material.set_shader_parameter("depth_mode",1 if id=="oak" else 0)
	art.material_override=art_material
	add_child(art)
	if spec.shape!="none":
		_make_body(scale_factor)
		# 阴影独立按体量编排，不再拉伸整张正面画稿；纯装饰草丛不投影。
		shadow=preload("res://scripts/presentation/illustration_shadow.gd").new()
		shadow.name="PaintedShadow"
		add_child(shadow)
		shadow.setup(id,scale_factor,vector(spec.depth_box))
	set_notify_transform(true)

## 轻微视觉晃动的单一入口：画稿与上部影形同步，脚底接触影和碰撞代理保持原位。
## 输入世界 XZ 偏移（米），调用者拥有动画时钟；默认不启用任何自动摆动。
func set_visual_sway(offset: Vector2) -> void:
	var style=preload("res://assets/environment/painted/courtyard/shadow_style.tres")
	var limited:=offset.limit_length(style.max_sway)
	visual_sway=Vector3(limited.x,0,limited.y)
	art_material.set_shader_parameter("sway_world",visual_sway)
	if is_instance_valid(shadow): shadow.set_sway_world(limited)

## 固定视角资产允许平移；位置改动时同步深度锚点和影子，不给静态物件增加轮询。
func _notification(what: int) -> void:
	if what!=NOTIFICATION_TRANSFORM_CHANGED or art_material==null: return
	art_material.set_shader_parameter("prop_origin",global_position)
	if is_instance_valid(shadow): shadow.sync_transform()

static func vector(values: Array) -> Vector3: return Vector3(values[0],values[1],values[2])

func _make_body(factor: float) -> void:
	body=StaticBody3D.new()
	body.name="SimpleBody"
	body.collision_layer=13
	body.collision_mask=0
	add_child(body)
	var shape:=CollisionShape3D.new()
	var proxy_mesh: Mesh
	var height: float
	if spec.shape=="box":
		var dimensions:=vector(spec.size)*factor
		var box:=BoxShape3D.new()
		box.size=dimensions
		shape.shape=box
		var mesh:=BoxMesh.new()
		mesh.size=dimensions
		proxy_mesh=mesh
		height=dimensions.y
	else:
		var cylinder:=CylinderShape3D.new()
		cylinder.radius=float(spec.radius)*factor
		cylinder.height=float(spec.height)*factor
		shape.shape=cylinder
		var mesh:=CylinderMesh.new()
		mesh.top_radius=cylinder.radius
		mesh.bottom_radius=cylinder.radius
		mesh.height=cylinder.height
		mesh.radial_segments=12
		proxy_mesh=mesh
		height=cylinder.height
	shape.position.y=height*.5
	body.add_child(shape)
	# 参考网格只参与原墙遮挡采样；layers=0 不绘制，但保持 visible 供采样器读取。
	proxy=MeshInstance3D.new()
	proxy.name="OcclusionProxy"
	proxy.mesh=proxy_mesh
	proxy.position=shape.position
	proxy.layers=0
	proxy.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	proxy.material_override=preload("res://scripts/presentation/environment_library.gd").material("masonry").duplicate()
	body.add_child(proxy)
	guide=MeshInstance3D.new()
	guide.name="CollisionGuide"
	guide.mesh=proxy_mesh
	guide.position=shape.position
	guide.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material:=StandardMaterial3D.new()
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color=Color(.25,.8,.85,.32)
	guide.material_override=material
	guide.visible=false
	body.add_child(guide)

## 原遮挡注册完成后取得最终显示副本，复用 90% 触发/退出缓冲，不增加第二套状态机。
func bind_occlusion() -> void:
	if proxy!=null: source_material=proxy.get_active_material(0)

func _physics_process(_delta: float) -> void:
	if source_material==null: return
	for parameter in PARAMETERS:
		var value: Variant=source_material.get_shader_parameter(parameter)
		if value!=null: art_material.set_shader_parameter(parameter,value)

func set_artwork(value: bool) -> void:
	artwork=value
	art.visible=value
	if shadow!=null: shadow.visible=value
	_refresh_guide()

func show_collision(value: bool) -> void:
	collision_guides=value
	_refresh_guide()

func _refresh_guide() -> void:
	if guide!=null: guide.visible=collision_guides or not artwork
