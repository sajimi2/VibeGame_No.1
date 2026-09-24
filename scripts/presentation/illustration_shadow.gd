@tool
extends MeshInstance3D
## 固定白天的美术投影：按物件体量编排地面轮廓，脱离正面画稿，避免整张树被拉成长条。
const ShaderFile=preload("res://scripts/presentation/illustration_shadow.gdshader")
const PROFILE_PATH="res://assets/environment/painted/courtyard/shadow_profiles.json"
const DEFAULT_STYLE=preload("res://assets/environment/painted/courtyard/shadow_style.tres")
var style=DEFAULT_STYLE
static var profiles: Dictionary={}
var sway_world:=Vector2.ZERO
var anchor: Node3D
@export_storage var footprint:=Rect2()
var ground_height: Callable

## 从场景恢复静态影形；每个实例独享材质，移动一个物件不影响其他影子。
func _ready() -> void:
	if mesh==null or material_override==null: return
	anchor=get_parent()
	material_override=material_override.duplicate()
	sync_transform()

## 入树后装配体量；公共样式持有所有视觉参数，静态物件不订阅逐帧回调。
func setup(id: String,factor: float,fallback_size: Vector3=Vector3.ONE) -> void:
	if profiles.is_empty(): profiles=JSON.parse_string(FileAccess.get_file_as_string(PROFILE_PATH))
	# 新资产尚未编排轮廓时由其深度体量生成默认椭圆，仍遵守同一风格，不会漏影或崩溃。
	var spec: Dictionary=profiles.profiles.get(id,{
		"lobes":[[0,0,maxf(.08,fallback_size.x*.5),maxf(.08,fallback_size.z*.5),fallback_size.y*.65]],
		"contacts":[[0,0,maxf(.08,fallback_size.x*.45),maxf(.08,fallback_size.z*.45)]]})
	var offset: Vector2=style.offset_per_height
	anchor=get_parent()
	top_level=true
	var lobes:=PackedVector4Array()
	var contacts:=PackedVector4Array()
	footprint=Rect2(Vector2.ZERO,Vector2.ZERO)
	for part in spec.lobes:
		var center: Vector2=(Vector2(part[0],part[1])+offset*float(part[4]))*factor
		var radius:=Vector2(part[2],part[3])*factor
		lobes.append(Vector4(center.x,center.y,radius.x,radius.y))
		footprint=footprint.expand(center-radius).expand(center+radius)
	for part in spec.contacts:
		var center:=Vector2(part[0],part[1])*factor
		var radius:=Vector2(part[2],part[3])*factor
		contacts.append(Vector4(center.x,center.y,radius.x,radius.y))
		footprint=footprint.expand(center-radius).expand(center+radius)
	var lobe_count:=lobes.size()
	var contact_count:=contacts.size()
	lobes.resize(16)
	contacts.resize(4)
	var points:=PackedVector2Array()
	for point in spec.get("hull_points",[]):
		points.append((Vector2(point[0],point[1])+offset*float(point[2]))*factor)
	var polygon:=Geometry2D.convex_hull(points) if points.size()>2 else PackedVector2Array()
	# convex_hull 首尾重复；材质自行闭合，避免零长边和多余顶点。
	if polygon.size()>0: polygon.remove_at(polygon.size()-1)
	var polygon_count:=polygon.size()
	for point in polygon: footprint=footprint.expand(point)
	polygon.resize(16)
	footprint=footprint.grow(style.feather+style.max_sway)
	var plane:=PlaneMesh.new()
	plane.size=footprint.size
	mesh=plane

	cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material:=ShaderMaterial.new()
	material.shader=ShaderFile
	material.render_priority=-120
	material.set_shader_parameter("polygon",polygon)
	material.set_shader_parameter("polygon_count",polygon_count)
	material.set_shader_parameter("lobes",lobes)
	material.set_shader_parameter("contacts",contacts)
	material.set_shader_parameter("lobe_count",lobe_count)
	material.set_shader_parameter("contact_count",contact_count)
	material.set_shader_parameter("stem_end",offset*float(spec.get("stem_height",0))*factor)
	material.set_shader_parameter("stem_radius",float(spec.get("stem_radius",0))*factor)
	style.apply(material)
	material_override=material

	sync_transform()

## 物件移动后显式同步地面锚点，保持世界光向；不复制网格，也不改变碰撞。
func sync_transform() -> void:
	if not is_instance_valid(anchor) or material_override==null: return
	var origin:=anchor.global_position
	var factor:=anchor.global_basis.get_scale()
	global_basis=Basis.from_scale(factor)
	global_position=origin+Vector3(footprint.get_center().x*factor.x,.008,footprint.get_center().y*factor.z)
	material_override.set_shader_parameter("foot_scale",Vector2(factor.x,factor.z))
	material_override.set_shader_parameter("foot_origin",Vector2(origin.x,origin.z))
	if ground_height.is_valid(): _fit_mesh()

## 可选坡地接收面，仅装配/移动时重建。颜色、光向和柔边仍由公共样式控制。
func fit_ground(sample: Callable) -> void:
	ground_height=sample
	_fit_mesh()

func _fit_mesh() -> void:
	var builder:=SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count_x:=maxi(1,ceili(footprint.size.x/.25))
	var count_z:=maxi(1,ceili(footprint.size.y/.25))
	for z in count_z+1:
		for x in count_x+1:
			var local:=Vector2(float(x)/count_x-.5,float(z)/count_z-.5)*footprint.size
			var world:=Vector2(global_position.x,global_position.z)+local
			builder.add_vertex(Vector3(local.x,float(ground_height.call(world))+.018-global_position.y,local.y))
	for z in count_z:
		for x in count_x:
			var a:=z*(count_x+1)+x
			for index in [a,a+1,a+count_x+1,a+1,a+count_x+2,a+count_x+1]: builder.add_index(index)
	mesh=builder.commit()

## 晃动只偏移上部投影，接触区留在脚点；限幅与网格留白共用样式，避免切边。
func set_sway_world(value: Vector2) -> void:
	sway_world=value.limit_length(style.max_sway)
	material_override.set_shader_parameter("sway",sway_world)
