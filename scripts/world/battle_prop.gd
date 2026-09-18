@tool
extends StaticBody3D
## 可在编辑器摆放的程序资产；射线贴合石面，角色移动使用无倒扣的实体碰撞。
@export_enum("Boulder", "Broken wall") var kind: int = 0:
	set(value):
		kind=value
		request_rebuild()
@export var extent := Vector3(3,2.6,2.5):
	set(value):
		extent=value
		request_rebuild()
@export var variation := 11:
	set(value):
		variation=value
		request_rebuild()
var queued := false

## 编辑器参数变化时合并重复请求，延迟到当前调用结束后重建。
func request_rebuild() -> void:
	if is_inside_tree() and not queued:
		queued=true
		rebuild.call_deferred()
func _ready() -> void: rebuild()

## 按类型与种子重新生成断墙或巨石；清理旧子节点后同步更新显示和碰撞。
func rebuild() -> void:
	queued=false
	for child in get_children():
		remove_child(child)
		child.queue_free()
	collision_layer=12 if kind == 0 else 13
	collision_mask=0
	var rng := RandomNumberGenerator.new()
	rng.seed=variation
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	# 只柔化巨石的显示法线，墙面保留棱角；顶点位置及碰撞三角面不变。
	surface.set_smooth_group(0 if kind == 0 else -1)
	if kind==0: rock(surface,rng)
	else: ruin(surface,rng)
	surface.generate_normals()
	var mesh := surface.commit()
	var visual := MeshInstance3D.new()
	visual.name="StoneVisual"
	visual.mesh=mesh
	visual.material_override=stone_material()
	add_child(visual)
	var collider := CollisionShape3D.new()
	collider.name="StoneCollision"
	collider.shape=mesh.create_trimesh_shape()
	add_child(collider)
	if kind == 0: add_rock_locomotion(mesh)
	add_to_group("battle_cover")

## 石面用于视线和箭矢；移动凸包把外凸点向下补到地面，消除蹲姿能钻入的倒扣。
## 不把石面底部三角形叠到地板上，避免贴地滑动反复消耗碰撞迭代而无法退出。
func add_rock_locomotion(mesh: ArrayMesh) -> void:
	var body := StaticBody3D.new()
	body.name = "MovementBody"
	# 第六层仅供移动与导航使用，箭矢/视线不碰这个简化凸包。
	body.collision_layer = 32
	body.collision_mask = 0
	var points := mesh.get_faces()
	var expanded := points.duplicate()
	for point in points: expanded.append(Vector3(point.x, -0.08, point.z))
	var shape := ConvexPolygonShape3D.new()
	shape.points = expanded
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	add_child(body)

## 表现层统一色阶与像素密度，几何构建器只负责形状和碰撞。
func stone_material() -> ShaderMaterial:
	return preload("res://scripts/presentation/stone_palette.gd").material(kind == 0)

func triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	surface.set_color(color)
	for point in [a,b,c]: surface.add_vertex(point)

## 通过三层扰动环与顶部封面生成不规则巨石。
func rock(surface: SurfaceTool, rng: RandomNumberGenerator) -> void:
	var rings: Array[PackedVector3Array]=[]
	var n := 9
	for level in 3:
		var ring := PackedVector3Array()
		for i in n:
			var angle := i*TAU/n
			var radius: float = rng.randf_range(0.85,1.1)*[0.92,1.0,0.56][level]
			var y: float=[0.0,extent.y*0.42,extent.y*0.87][level]
			if level>0: y+=rng.randf_range(-0.10,0.10)*extent.y
			ring.append(Vector3(cos(angle)*extent.x*0.5*radius,y,sin(angle)*extent.z*0.5*radius))
		rings.append(ring)
	for level in 2:
		for i in n:
			var j := (i+1)%n
			var color := Color("74796f").lightened(rng.randf_range(-0.08,0.07))
			triangle(surface,rings[level][i],rings[level+1][i],rings[level+1][j],color)
			triangle(surface,rings[level][i],rings[level+1][j],rings[level][j],color.darkened(0.025))
	var cap := Vector3(extent.x*0.07,extent.y,extent.z*0.04)
	for i in n:
		var j := (i+1)%n
		triangle(surface,cap,rings[2][j],rings[2][i],Color("838777") if i%3 else Color("697a55"))
		triangle(surface,Vector3.ZERO,rings[0][i],rings[0][j],Color("52554d"))

## 按列生成高度不齐的残墙，再补充墙脚碎石。
func ruin(surface: SurfaceTool, rng: RandomNumberGenerator) -> void:
	var columns := maxi(3,roundi(extent.x/0.66))
	var width := extent.x/columns
	for column in columns:
		var falloff := 0.3+0.7*absf(cos((float(column)/columns+0.12)*PI))
		var rows := maxi(1,roundi(extent.y/0.4*falloff)+rng.randi_range(-1,1))
		for row in rows:
			var center := Vector3(-extent.x*0.5+width*(column+0.5),0.2+row*0.4,0)
			var size := Vector3(width*0.985,0.393,extent.z)
			if row==rows-1:
				size.x*=rng.randf_range(0.72,0.95)
				size.y*=rng.randf_range(0.65,1.0)
				center.x+=rng.randf_range(-0.06,0.06)
			var block := BoxMesh.new()
			block.size=size
			var color := Color("737d7a").lightened(rng.randf_range(-0.10,0.05))
			var faces := block.get_faces()
			for i in range(0,faces.size(),3):
				# 石块间隙形成灰缝，面色使用同一石材色系。
				triangle(surface,faces[i]+center,faces[i+1]+center,faces[i+2]+center,color)
	# 散落石块保持低矮可见，战斗通道宽度由地图布局保证。
	for i in 4:
		var cube := BoxMesh.new()
		cube.size=Vector3(0.3,0.18,0.3)
		var center := Vector3(rng.randf_range(-extent.x*0.5,extent.x*0.5),0.09,extent.z*0.5+0.22)
		var faces := cube.get_faces()
		for j in range(0,faces.size(),3): triangle(surface,faces[j]+center,faces[j+1]+center,faces[j+2]+center,Color("6c746d"))
