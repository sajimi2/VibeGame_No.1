extends StaticBody3D
## 装配单层平台/崖壁/坡道：显示和碰撞共用布局，游戏逻辑继续使用既有演员与寻路。
const Layout=preload("res://scripts/world/terrace_layout.gd")
var terrain_seed:=0
var layout:=Layout.new()
var top: MeshInstance3D
var walls: MeshInstance3D
var faces: Array[Dictionary]=[]
var top_material: ShaderMaterial
var wall_material: ShaderMaterial
var artwork:=true

func _ready() -> void:
	collision_layer=13
	collision_mask=0
	set_meta("occlusion_role","support")
	layout.build(terrain_seed)
	for message in layout.validate(): push_error(message)
	faces=layout.exposed_edges()
	var tops:=SurfaceTool.new()
	var sides:=SurfaceTool.new()
	tops.begin(Mesh.PRIMITIVE_TRIANGLES)
	sides.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in Layout.SIZE.y:
		for x in Layout.SIZE.x:
			var c:=Vector2i(x,z)
			var a:=layout.world(c,Vector2.ZERO)
			var b:=layout.world(c,Vector2.RIGHT)
			var d:=layout.world(c,Vector2.DOWN)
			var e:=layout.world(c,Vector2.ONE)
			var rim:=Color(0,0,0,0)
			for face in faces:
				if face.cell==c: rim[face.side]=1.0
			for v in [a,b,d,b,e,d]:
				tops.set_color(rim)
				tops.set_uv(Vector2(v.x,v.z))
				tops.add_vertex(v)
	for face in faces:
		# 顺时针外边的法线朝外；无内部墙，坑口由周围较高地格自动生成。
		for v in [face.a,face.low_a,face.b,face.b,face.low_a,face.low_b]:
			# UV2 存距崖顶的米数；同高直段共享世界横坐标，不在格缝重新开始贴图。
			var t:=Vector2(v.x-face.a.x,v.z-face.a.z).length()/maxf(.001,Vector2(face.b.x-face.a.x,face.b.z-face.a.z).length())
			var depth: float=lerpf(face.a.y,face.b.y,t)-v.y
			sides.set_uv2(Vector2(depth,0))
			sides.set_uv(Vector2(v.x if face.side%2==0 else v.z,v.y))
			sides.add_vertex(v)
	tops.generate_normals()
	sides.generate_normals()
	top=MeshInstance3D.new()
	top.name="PlatformSurfaces"
	top.mesh=tops.commit()
	add_child(top)
	walls=MeshInstance3D.new()
	walls.name="ExposedCliffs"
	walls.mesh=sides.commit()
	add_child(walls)
	var vertices:=top.mesh.get_faces()
	vertices.append_array(walls.mesh.get_faces())
	var shape:=ConcavePolygonShape3D.new()
	shape.set_faces(vertices)
	var collision:=CollisionShape3D.new()
	collision.name="TerrainCollision"
	collision.shape=shape
	add_child(collision)
	_make_materials()

func height_at(point: Vector2) -> float: return layout.height_at(point)

func _make_materials() -> void:
	top_material=ShaderMaterial.new()
	top_material.shader=preload("res://scripts/presentation/terrace_top.gdshader")
	top_material.set_shader_parameter("meadow",load("res://assets/environment/painted/courtyard/textures/meadow.png"))
	top_material.set_shader_parameter("earth",load("res://assets/environment/painted/courtyard/textures/earth.png"))
	var roads:=PackedVector4Array()
	for path in layout.roads():
		for i in path.size()-1: roads.append(Vector4(path[i].x,path[i].y,path[i+1].x,path[i+1].y))
	top_material.set_shader_parameter("road_count",roads.size())
	roads.resize(16)
	top_material.set_shader_parameter("roads",roads)
	top.material_override=top_material
	wall_material=ShaderMaterial.new()
	wall_material.shader=preload("res://scripts/presentation/terrace_wall.gdshader")
	wall_material.set_shader_parameter("cliff",load("res://assets/environment/painted/terraces/textures/cliff.png"))
	walls.material_override=wall_material

func set_guides(value: bool) -> void:
	top_material.set_shader_parameter("guides",value)
	wall_material.set_shader_parameter("guides",value)

func set_artwork(value: bool) -> void:
	artwork=value
	top_material.set_shader_parameter("artwork",value)
	wall_material.set_shader_parameter("artwork",value)

func set_light_direction(direction: Vector3) -> void:
	wall_material.set_shader_parameter("sun_direction",direction)
