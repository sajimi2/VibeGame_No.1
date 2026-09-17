extends RefCounted
## 在指定关卡根下生成配套的网格和碰撞，不依赖玩家、界面或任务。
var root: Node3D
var materials: Dictionary = {}

## 记录生成节点的挂载根；构建器自身是 RefCounted，不进入场景树。
func _init(parent: Node3D) -> void:
	root = parent

## 按材质种类生成像素纹理并缓存，同类地形共享资源。
func material(kind: String) -> StandardMaterial3D:
	if materials.has(kind): return materials[kind]
	var palette := {"grass": Color("536448"), "stone": Color("778184"), "wall": Color("626b72"), "path": Color("988468"), "soil": Color("514a3e"), "wood": Color("796349"), "cloth": Color("985b4f"), "wood_frame": Color("4e4032")}
	var base: Color = palette.get(kind, Color.GRAY)
	var image := Image.create(64, 64, false, Image.FORMAT_RGB8)
	image.fill(base)
	var texture_rng := RandomNumberGenerator.new()
	texture_rng.seed = 7319 + kind.hash()
	for y in 64:
		for x in 64:
			var shade := int(texture_rng.randi() % 47)
			if kind in ["wall","stone"]:
				var row := y/16 as int
				var brick_x := (x+row*16)%32
				var brick_tone := ((x+row*16)/32 as int + row*3)%3
				var color := base.darkened(brick_tone*0.045)
				if y%16==0 or brick_x==0: color=base.darkened(0.32)
				elif y%16 in [1,2] or brick_x==1: color=base.lightened(0.12)
				elif y%16==15 or brick_x==31: color=base.darkened(0.14)
				image.set_pixel(x,y,color)
			elif kind == "wood":
				var grain := sin(float(x/2)*2.2+sin(float(y)*0.15))
				image.set_pixel(x,y,base.darkened(0.16) if grain>0.65 else base)
			elif kind in ["soil","path","grass"]:
				# 用较大像素色块组织纹理，避免细密噪点和连续渐变。
				var cx := x/8 as int
				var cy := y/8 as int
				var cluster := sin(cx*1.73+sin(cy*0.83)*2.0)+cos(cy*1.32-cx*0.37)
				var color := base.lightened(0.04) if cluster>1.2 else base.darkened(0.045) if cluster< -1.2 else base
				if kind=="grass": color=base.lightened(0.018) if cluster>1.65 else base.darkened(0.02) if cluster< -1.65 else base
				if kind=="soil":
					var band := (y+int(3*sin(cx*0.7)))%20
					if band<2: color=base.darkened(0.22)
				image.set_pixel(x,y,color)
			elif shade<2: image.set_pixel(x,y,base.lightened(0.055))
	var result := StandardMaterial3D.new()
	result.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	result.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	result.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	result.roughness = 1.0
	result.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	result.albedo_texture = ImageTexture.create_from_image(image)
	result.uv1_triplanar = true
	result.uv1_scale = Vector3(0.5, 0.5, 0.5)
	materials[kind] = result
	return result

## 同时生成盒状网格和碰撞；layers 控制它参与哪些物理查询。
func box(label: String, center: Vector3, size: Vector3, kind: String, layers: int = 13) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = label
	body.position = center
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

## 生成指定宽度、长度和升高量的楔形坡道，网格与碰撞保持一致。
func ramp(label: String, origin: Vector3, width: float, length: float, rise: float) -> void:
	# 坡道朝 -Z 方向升高，显示与碰撞使用相同顶点。
	var vertices := PackedVector3Array([
		Vector3(-width / 2, 0, 0), Vector3(width / 2, 0, 0),
		Vector3(-width / 2, 0, -length), Vector3(width / 2, 0, -length),
		Vector3(-width / 2, rise, -length), Vector3(width / 2, rise, -length)])
	var body := StaticBody3D.new()
	body.name = label
	body.position = origin
	body.collision_layer = 13
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
	var mat := material("path")
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	visual.material_override = mat
	body.add_child(visual)

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
