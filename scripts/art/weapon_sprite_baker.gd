extends RefCounted
## 将源网格投到正交像素网格，输出颜色与逐像素深度；不读取战斗或场景。
const SIZE := 128
const PIXEL_SIZE := 0.04
const DEPTH_SPAN := 6.0

## 提前展开网格与装饰件，保留握柄原点；此后切帧无需重新读取网格资源。
static func geometry(model: MeshInstance3D) -> Array:
	var result: Array = []
	_collect(model,Transform3D.IDENTITY,result)
	return result

static func _collect(node: Node3D, local: Transform3D, result: Array) -> void:
	if node.get_meta("pixel_bake_ignore",false): return
	if node is MeshInstance3D and node.mesh != null:
		var points: PackedVector3Array = node.mesh.get_faces()
		var color := Color.WHITE
		if node.material_override is StandardMaterial3D: color = node.material_override.albedo_color
		var center: Vector3 = node.mesh.get_aabb().get_center()
		for i in range(0,points.size(),3):
			var a := points[i]
			var b := points[i+1]
			var c := points[i+2]
			# 当前来源均为凸刀身、盒体或双面装饰；统一 Godot 基元与自建网格的面绕序。
			if (b-a).cross(c-a).dot((a+b+c)/3-center)<0:
				var swap := b
				b = c
				c = swap
			result.append({"points": [local*a,local*b,local*c], "color":color})
	for child in node.get_children():
		if child is Node3D: _collect(child,local*child.transform,result)

## 与几何采集使用相同排除规则：已有像素箭和显示适配器不再烘焙，也不隐藏其本体。
static func meshes(node: Node3D) -> Array:
	if node.get_meta("pixel_bake_ignore",false): return []
	var result: Array = [node] if node is MeshInstance3D else []
	for child in node.get_children():
		if child is Node3D: result.append_array(meshes(child))
	return result

## view_basis 把握柄局部坐标变为相机坐标，light 是同一坐标系中的来光方向。
## 像素中心采样、不做抗锯齿，分段明暗保留刀背厚度；深度图避免整张纸片穿墙或穿身体。
static func bake(triangles: Array, view_basis: Basis, light: Vector3) -> Dictionary:
	var image := Image.create(SIZE,SIZE,false,Image.FORMAT_RGBA8)
	var depth := Image.create(SIZE,SIZE,false,Image.FORMAT_RGBA8)
	var buffer := PackedFloat32Array()
	buffer.resize(SIZE*SIZE)
	buffer.fill(-INF)
	for triangle in triangles:
		var a: Vector3 = view_basis*triangle.points[0]
		var b: Vector3 = view_basis*triangle.points[1]
		var c: Vector3 = view_basis*triangle.points[2]
		var normal := (b-a).cross(c-a).normalized()
		# 封闭实体背面不会成为可见像素；刀光是双面开放面，仍保留两侧。
		if normal.z<=0 and not triangle.get("unlit",false): continue
		var illumination := normal.dot(light)
		var shade := 1.0 if triangle.get("unlit",false) else 1.05 if illumination>0.72 else 0.88 if illumination>0.2 else 0.68 if illumination> -0.4 else 0.48
		var base: Color = triangle.color
		var color := Color(snappedf(base.r*shade,1.0/31),snappedf(base.g*shade,1.0/31),snappedf(base.b*shade,1.0/31),base.a)
		_raster(a,b,c,color,image,depth,buffer)
	return {"image":image,"depth":depth}

## 正交投影下使用重心坐标同时插值颜色覆盖与深度；只保留朝镜头最近的表面。
static func _raster(a: Vector3,b: Vector3,c: Vector3,color: Color,image: Image,depth: Image,buffer: PackedFloat32Array) -> void:
	var p := Vector2(a.x,-a.y)/PIXEL_SIZE+Vector2.ONE*SIZE*0.5
	var q := Vector2(b.x,-b.y)/PIXEL_SIZE+Vector2.ONE*SIZE*0.5
	var r := Vector2(c.x,-c.y)/PIXEL_SIZE+Vector2.ONE*SIZE*0.5
	var area := (q-p).cross(r-p)
	if absf(area)<0.00001: return
	var start := Vector2i(maxi(0,floori(minf(p.x,minf(q.x,r.x)))),maxi(0,floori(minf(p.y,minf(q.y,r.y)))))
	var end := Vector2i(mini(SIZE-1,ceili(maxf(p.x,maxf(q.x,r.x)))),mini(SIZE-1,ceili(maxf(p.y,maxf(q.y,r.y)))))
	for y in range(start.y,end.y+1):
		for x in range(start.x,end.x+1):
			var sample := Vector2(x+0.5,y+0.5)
			var u := (q-sample).cross(r-sample)/area
			var v := (r-sample).cross(p-sample)/area
			var w := 1.0-u-v
			if minf(u,minf(v,w))< -0.00001: continue
			var z := u*a.z+v*b.z+w*c.z
			var index := y*SIZE+x
			if z<=buffer[index]: continue
			buffer[index] = z
			image.set_pixel(x,y,color)
			var encoded := clampi(roundi((z/DEPTH_SPAN+0.5)*65535),0,65535)
			depth.set_pixel(x,y,Color8(encoded>>8,encoded&255,0,255))
