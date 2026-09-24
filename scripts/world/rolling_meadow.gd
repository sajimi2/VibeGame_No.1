extends StaticBody3D
## 小院外的单层连续地表：同一份采样高度生成显示、碰撞和物件落点，不持有玩法状态。
@export var terrain_seed := 240920
const BOUNDS := Rect2(8,-20,40,48)
const STEP := 0.5
const BASE := -0.02
var heights := PackedFloat32Array()
var columns := int(BOUNDS.size.x/STEP)+1
var rows := int(BOUNDS.size.y/STEP)+1
var noise := FastNoiseLite.new()
var surface: MeshInstance3D

## 固定种子可复现；小院接缝和远端边缘保持平整，大起伏叠加低频随机变化。
func _ready() -> void:
	collision_layer=13
	collision_mask=0
	set_meta("occlusion_role","support")
	noise.seed=terrain_seed
	noise.frequency=0.09
	noise.fractal_octaves=3
	noise.fractal_gain=0.35
	for z in rows:
		for x in columns:
			heights.append(_height(BOUNDS.position+Vector2(x,z)*STEP))
	var vertices:=PackedVector3Array()
	var indices:=PackedInt32Array()
	for z in rows:
		for x in columns:
			var p:=BOUNDS.position+Vector2(x,z)*STEP
			vertices.append(Vector3(p.x,heights[z*columns+x],p.y))
	for z in rows-1:
		for x in columns-1:
			var a:=z*columns+x
			indices.append_array(PackedInt32Array([a,a+1,a+columns,a+1,a+columns+1,a+columns]))
	var builder:=SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	for vertex in vertices: builder.add_vertex(vertex)
	for index in indices: builder.add_index(index)
	builder.generate_normals()
	surface=MeshInstance3D.new()
	surface.name="MeadowSurface"
	surface.mesh=builder.commit()
	add_child(surface)
	var shape:=CollisionShape3D.new()
	shape.name="GroundCollision"
	shape.shape=surface.mesh.create_trimesh_shape()
	add_child(shape)

func path_z(x: float) -> float: return 13.0+3.0*sin((x-8.0)*0.17)

## 上丘支路只用于画面和装饰避让，沿现有坡面行走，不修改高度与碰撞。
func climb_path() -> PackedVector2Array:
	var points:=PackedVector2Array()
	for i in 17:
		var t:=float(i)/16.0
		points.append(Vector2(23,15).bezier_interpolate(Vector2(15,11),Vector2(19,5),Vector2(23,1),t))
	return points

func distance_to_climb_path(point: Vector2) -> float:
	var path:=climb_path()
	var distance:=1000.0
	for i in path.size()-1:
		distance=minf(distance,point.distance_to(Geometry2D.get_closest_point_to_segment(point,path[i],path[i+1])))
	return distance

func _hill(p: Vector2,center: Vector2,radius: Vector2) -> float:
	return exp(-((p-center)/radius).length_squared())

func _height(p: Vector2) -> float:
	var fade:=smoothstep(8.0,14.0,p.x)*(1.0-smoothstep(40.0,48.0,p.x))
	fade*=smoothstep(-20.0,-12.0,p.y)*(1.0-smoothstep(22.0,28.0,p.y))
	var shape:=2.8*_hill(p,Vector2(23,1),Vector2(8,9))
	shape+=2.1*_hill(p,Vector2(33,20),Vector2(8,7))
	shape-=0.65*_hill(p,Vector2(24,12),Vector2(7,5))
	shape+=noise.get_noise_2d(p.x,p.y)*0.65
	# 道路只削弱细碎起伏，仍保留沿浅谷升降；不会把道路切成突兀的平板。
	var road:=1.0-smoothstep(1.0,3.0,absf(p.y-path_z(p.x)))
	shape=lerpf(shape,shape*0.65,road)
	return BASE+shape*fade

## 按实际三角形插值，而非重新取噪声或双线性插值，确保落点与碰撞面一致。
func height_at(p: Vector2) -> float:
	if not BOUNDS.has_point(p) or heights.is_empty(): return BASE
	var grid: Vector2=(p-BOUNDS.position)/STEP
	var x:=mini(int(grid.x),columns-2)
	var z:=mini(int(grid.y),rows-2)
	var u:=grid.x-x
	var v:=grid.y-z
	var a:=heights[z*columns+x]
	var b:=heights[z*columns+x+1]
	var c:=heights[(z+1)*columns+x]
	var d:=heights[(z+1)*columns+x+1]
	return a+(b-a)*u+(c-a)*v if u+v<=1.0 else d+(c-d)*(1.0-u)+(b-d)*(1.0-v)
