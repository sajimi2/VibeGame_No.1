extends RefCounted
## 在指定关卡根下生成配套的网格和碰撞，不依赖玩家、界面或任务。
var root: Node3D
var materials: Dictionary = {}

## 记录生成节点的挂载根；构建器自身是 RefCounted，不进入场景树。
func _init(parent: Node3D) -> void:
	root = parent

## 地图与建筑共用磁盘像素资产；只缓存材质引用，不在启动时重复绘制纹理。
func material(kind: String) -> ShaderMaterial:
	if not materials.has(kind): materials[kind]=preload("res://scripts/presentation/environment_library.gd").material(kind)
	return materials[kind]

## 同时生成盒状网格和碰撞；layers 控制它参与哪些物理查询。
func box(label: String, center: Vector3, size: Vector3, kind: String, layers: int = 13) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = label
	body.position = center
	if kind in ["grass","soil","floor","planks"]: body.set_meta("occlusion_role","support")
	body.collision_layer = layers
	body.collision_mask = 0
	root.add_child(body)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.material_override = material(kind)
	body.add_child(visual)
	return body

## 保留指定宽度/长度/升高量的连续坡碰撞，用共用木架桥构件贴合行走面。
func ramp(label: String, origin: Vector3, width: float, length: float, rise: float) -> void:
	# 坡道朝 -Z 方向升高，木桥原点与碰撞坡脚重合。
	var vertices := PackedVector3Array([
		Vector3(-width / 2, 0, 0), Vector3(width / 2, 0, 0),
		Vector3(-width / 2, 0, -length), Vector3(width / 2, 0, -length),
		Vector3(-width / 2, rise, -length), Vector3(width / 2, rise, -length)])
	var body := StaticBody3D.new()
	body.name = label
	body.position = origin
	body.collision_layer = 13
	body.set_meta("occlusion_role","support")
	root.add_child(body)
	var collision := CollisionShape3D.new()
	var shape := ConvexPolygonShape3D.new()
	shape.points = vertices
	collision.shape = shape
	body.add_child(collision)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_smooth_group(-1)
	for index in [0, 1, 5, 0, 5, 4, 2, 4, 5, 2, 5, 3, 0, 4, 2, 1, 3, 5, 0, 2, 3, 0, 3, 1]:
		surface.add_vertex(vertices[index])
	surface.generate_normals()
	var visual := MeshInstance3D.new()
	visual.mesh = surface.commit()
	visual.material_override = material("wood")
	visual.visible=false
	body.add_child(visual)
	var bridge:=preload("res://scripts/presentation/architecture_piece.gd").new()
	bridge.name="TimberBridge"
	bridge.kind="bridge"
	bridge.extent=Vector3(width,.1,length)
	bridge.rise=rise
	body.add_child(bridge)

## 把二维轮廓拉成立体高台，使用同一组面生成外观和碰撞。
func natural_ledge(label: String, origin: Vector3, outline: PackedVector2Array, height: float) -> void:
	# 平顶和不规则侧面共用同一网格生成显示与碰撞；南侧入口与坡道对齐。
	var top := SurfaceTool.new()
	top.begin(Mesh.PRIMITIVE_TRIANGLES)
	top.set_smooth_group(-1)
	var indices := Geometry2D.triangulate_polygon(outline)
	for i in range(0, indices.size(), 3):
		for j in [0, 1, 2]:
			var point := outline[indices[i + j]]
			top.add_vertex(Vector3(point.x, height, point.y))
	top.generate_normals()
	top.set_material(material("grass"))
	var mesh := top.commit()
	var sides := SurfaceTool.new()
	sides.begin(Mesh.PRIMITIVE_TRIANGLES)
	sides.set_smooth_group(-1)
	for i in outline.size():
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		var ring_a := Vector3(a.x, height, a.y)
		var ring_b := Vector3(b.x, height, b.y)
		var middle_a := Vector3(a.x * (1.04 + 0.02 * (i % 3)), height * (0.42 + 0.05 * (i % 3)), a.y)
		var middle_b := Vector3(b.x * (1.04 + 0.02 * (((i + 1) % outline.size()) % 3)), height * (0.42 + 0.05 * (((i + 1) % outline.size()) % 3)), b.y)
		var foot_a := Vector3(a.x * 1.1, 0, a.y)
		var foot_b := Vector3(b.x * 1.1, 0, b.y)
		for vertex in [ring_a, middle_b, ring_b, ring_a, middle_a, middle_b,
			middle_a, foot_b, middle_b, middle_a, foot_a, foot_b]:
			sides.add_vertex(vertex)
	sides.generate_normals()
	sides.set_material(material("soil"))
	sides.commit(mesh)
	var body := StaticBody3D.new()
	body.name = label
	body.position = origin
	body.collision_layer = 13
	body.collision_mask = 0
	# 高台包含顶面和侧壁，必须作为完整承托体保留，不能把底下草地透出来。
	body.set_meta("occlusion_role","support")
	root.add_child(body)
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	body.add_child(visual)
	var collision := CollisionShape3D.new()
	collision.shape = mesh.create_trimesh_shape()
	body.add_child(collision)

## 创建可随相机朝向的空间标注，并加入标注分组供 F1 开关控制。
func _label(text: String, where: Vector3) -> void:
	var label := Label3D.new()
	label.text = text
	label.add_to_group("sample_annotations")
	label.visible = false
	label.font_size = 24
	label.pixel_size = 0.026
	label.outline_size = 6
	label.modulate = Color("eddbac")
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# 空间文字作为标注显示，避免下半部分被地形遮住。
	label.no_depth_test = true
	label.render_priority = 20
	label.position = where
	root.add_child(label)
