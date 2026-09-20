extends Node3D
## 独立绘画层：完整插画经少量配准点拆成墙/屋顶纸片，原小屋仍持有物理与遮挡状态。
## 不修改 Blender 网格，也不重新实现战斗/透视算法；只订阅对应墙组和屋顶的材质参数。
const ASSET="res://assets/environment/painted/cottage/"
const SHADER=preload("res://scripts/presentation/painted_environment.gdshader")
const Style=preload("res://scripts/presentation/occlusion_style.gd")
var cottage: Node3D
var enabled:=true
var ready_for_comparison:=false
var cards: Array[MeshInstance3D]=[]
var bindings: Array[Dictionary]=[]
var roof_layers: Dictionary={}
var original_layers: Dictionary={}
var registration: Dictionary
var ground_shadow: MeshInstance3D
var original_casters: Dictionary={}

## 关卡的原墙遮挡注册结束后调用一次；绑定的是显示副本，绝不隐藏阴影代理的原材质。
func setup(source: Node3D) -> void:
	cottage=source
	registration=JSON.parse_string(FileAccess.get_file_as_string(ASSET+"registration.json"))
	process_physics_priority=30
	var front: MeshInstance3D=cottage.get_node("FrontWall/WallFrontLeft")
	var side: MeshInstance3D=cottage.get_node("WallEast/Visual")
	_front(front.get_active_material(0))
	_side(side.get_active_material(0))
	_roof(-1)
	_roof(1)
	_interior()
	# 显示与空间代理完全分离：包括内侧和墙厚端面，原墙网格只留给几何采样与碰撞。
	for path in ["FrontWall","WallEast","WallWest","WallBack","SupportFloor"]:
		for visual in cottage.get_node(path).get_children():
			if visual is MeshInstance3D: original_layers[visual]=visual.layers
	for piece in cottage.roof.pieces: roof_layers[piece.get_instance_id()]=piece.layers
	# 仅在新绘画路线接管投影；不隐藏网格，不干扰屋顶/墙的视线采样与碰撞。
	for visual in cottage.find_children("*","MeshInstance3D",true,false):
		if visual.cast_shadow!=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			original_casters[visual]={"casting":visual.cast_shadow,"layers":visual.layers}
	ground_shadow=preload("res://scripts/presentation/illustration_shadow.gd").new()
	ground_shadow.name="PaintedHouseShadow"
	add_child(ground_shadow)
	ground_shadow.setup("cottage",1.0)
	set_notify_transform(true)
	ready_for_comparison=true
	set_enabled(true)

func _notification(what: int) -> void:
	if what==NOTIFICATION_TRANSFORM_CHANGED and is_instance_valid(ground_shadow):
		ground_shadow.sync_transform()

func point(key: String) -> Vector2:
	var value: Array=registration[key]
	return Vector2(value[0],value[1])

## 配准点先锁门洞与墙脚，再容纳绘画轮廓；每片纸只需少量三角面，不制作瓦片/木纹几何。
func _front(source: ShaderMaterial) -> void:
	var vertices:=PackedVector3Array()
	var uv:=PackedVector2Array()
	var columns: Array=registration.front_columns
	var rows: Array=registration.front_rows
	for row in rows:
		for column in columns:
			vertices.append(Vector3(column[0],row[0],3.025))
			uv.append(Vector2(column[1],column[2]-row[1])/float(registration.coordinate_canvas))
	_card("PaintedFront",vertices,uv,_indices(columns.size(),rows.size()),"walls",source,false)

func _side(source: ShaderMaterial) -> void:
	var vertices:=PackedVector3Array()
	var uv:=PackedVector2Array()
	for height in [-.06,2.8,3.1]:
		for depth in [3.025,-3.2]:
			var t: float=(3.0-depth)/6.0
			var bottom:=point("side_front_bottom").lerp(point("side_back_bottom"),t)
			var top:=point("side_front_top").lerp(point("side_back_top"),t)
			vertices.append(Vector3(2.505,height,depth))
			uv.append(bottom.lerp(top,height/2.8)/float(registration.coordinate_canvas))
	_card("PaintedEast",vertices,uv,_indices(2,3),"walls",source,false)

func _roof(side: int) -> void:
	var vertices:=PackedVector3Array()
	var uv:=PackedVector2Array()
	var eave: String="west_eave_" if side<0 else "east_eave_"
	for depth in [3.8,-3.65]:
		for width in [0.0,3.35]:
			var t: float=(3.35-depth)/6.7
			var ridge:=point("ridge_front").lerp(point("ridge_back"),t)
			var edge:=point(eave+"front").lerp(point(eave+"back"),t)
			vertices.append(Vector3(side*width,4.13-width*.52,depth))
			uv.append(ridge.lerp(edge,width/2.9)/float(registration.coordinate_canvas))
	_card("PaintedRoofWest" if side<0 else "PaintedRoofEast",vertices,uv,_indices(2,2),"roof",cottage.roof.roof_material,true)

func _indices(columns: int,rows: int) -> PackedInt32Array:
	var result:=PackedInt32Array()
	for y in rows-1:
		for x in columns-1:
			var a:=y*columns+x
			result.append_array(PackedInt32Array([a,a+1,a+columns,a+1,a+columns+1,a+columns]))
	return result

## 一张完整内景画分配给后墙、左墙和承托地板；只配准结构面，不建木纹/石缝等细节模型。
func _interior() -> void:
	var config: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(ASSET+"interior_registration.json"))
	for part in ["west","back","floor"]:
		var spec: Dictionary=config.planes[part]
		var vertices:=PackedVector3Array()
		var uv:=PackedVector2Array()
		for point in spec.vertices: vertices.append(Vector3(point[0],point[1],point[2]))
		for point in spec.paint_uv: uv.append(Vector2(point[0],point[1]))
		var path: String="WallWest/Visual" if part=="west" else "WallBack/Visual" if part=="back" else "SupportFloor/Visual"
		var source: ShaderMaterial=cottage.get_node(path).get_active_material(0)
		_card("PaintedInterior_"+part,vertices,uv,PackedInt32Array([0,1,2,0,2,3]),"interior",source,false)
		if part=="floor":
			cards.back().material_override.set_shader_parameter("is_support",true)
			bindings.back().parameters=[]

func _card(label: String,vertices: PackedVector3Array,uv: PackedVector2Array,indices: PackedInt32Array,image: String,source: ShaderMaterial,roof: bool) -> void:
	var arrays:=[]
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	arrays[Mesh.ARRAY_TEX_UV]=uv
	arrays[Mesh.ARRAY_INDEX]=indices
	var normals:=PackedVector3Array()
	for vertex in vertices: normals.append(Vector3.UP)
	arrays[Mesh.ARRAY_NORMAL]=normals
	var mesh:=ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var material:=ShaderMaterial.new()
	material.shader=SHADER
	material.set_shader_parameter("painting",load(ASSET+image+".png"))
	material.set_shader_parameter("is_roof",roof)
	var card:=MeshInstance3D.new()
	card.name=label
	card.mesh=mesh
	card.material_override=material
	card.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(card)
	cards.append(card)
	bindings.append({"material":material,"source":source,"parameters":Style.ROOF_PARAMETERS if roof else Style.WALL_PARAMETERS})

func _physics_process(_delta: float) -> void:
	if not ready_for_comparison: return
	for binding in bindings:
		for parameter in binding.parameters:
			var value: Variant=binding.source.get_shader_parameter(parameter)
			if value!=null: binding.material.set_shader_parameter(parameter,value)

## V 仅切可见外观。原墙保持可见以供三角面采样，屋顶保留完整影子和室内状态。
func set_enabled(value: bool) -> void:
	enabled=value
	if is_instance_valid(ground_shadow): ground_shadow.visible=value
	for visual in original_casters:
		var previous: Dictionary=original_casters[visual]
		visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if value else previous.casting
		# SHADOWS_ONLY 改成 OFF 会恢复实体绘制，必须一并退出颜色层，防止旧瓦顶重新露出。
		if previous.casting==GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			visual.layers=0 if value else previous.layers
	for card in cards: card.visible=value
	for visual in original_layers: visual.layers=0 if value else original_layers[visual]
	for piece in cottage.roof.pieces:
		# 只退出颜色绘制，保留 visible 供原屋顶视线采样；原独立阴影代理继续投影。
		piece.layers=0 if value else roof_layers[piece.get_instance_id()]
	_physics_process(0)
