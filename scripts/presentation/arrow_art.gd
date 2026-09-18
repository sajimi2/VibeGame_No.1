extends RefCounted
## 飞行箭与弓上展示箭共用一份像素侧影；两张交叉裁剪面保留三维俯仰、遮挡与阴影。
const Store = preload("res://scripts/art/atlas_store.gd")
const LENGTH := 0.8
const SIZE := Vector2i(32,12)
static var generated: ImageTexture

static func texture(asset_id: String = "arrow") -> Texture2D:
	var imported := Store.lookup(asset_id,"profile")
	if not imported.is_empty(): return imported.texture
	if generated == null:
		var image := Image.create(SIZE.x,SIZE.y,false,Image.FORMAT_RGBA8)
		# 箭尖在左、箭尾在右；深色描边和亮面让金属、木杆、尾羽在地面上可辨。
		image.fill_rect(Rect2i(5,5,26,2),Color("584537"))
		image.fill_rect(Rect2i(6,5,23,1),Color("bea66c"))
		for x in range(1,7):
			var radius := mini(x/2,2)
			image.fill_rect(Rect2i(x,5-radius,1,2+radius*2),Color("465860"))
			image.fill_rect(Rect2i(x,5-radius,1,1+radius),Color("d3dfe0"))
		for x in range(23,30):
			var height := mini((x-22)/2+1,3)
			image.fill_rect(Rect2i(x,5-height,1,height),Color("e2d8b6") if x%2 == 0 else Color("ad9d7b"))
			image.fill_rect(Rect2i(x,7,1,height),Color("a26a4d") if x%2 == 0 else Color("704b3d"))
		image.fill_rect(Rect2i(29,5,2,2),Color("dfcca0"))
		generated = ImageTexture.create_from_image(image)
	return generated

## 原点固定为箭尖，局部 +Z 指向箭尾；更新朝向时旋转整支箭，不能绕箭杆中心转。
static func model(asset_id: String = "arrow") -> MeshInstance3D:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var width := LENGTH * float(SIZE.y) / SIZE.x * 0.5
	for axis in [Vector3.UP,Vector3.RIGHT]:
		var points := [-axis*width,axis*width,axis*width+Vector3.BACK*LENGTH,-axis*width+Vector3.BACK*LENGTH]
		var uv := [Vector2(0,1),Vector2(0,0),Vector2(1,0),Vector2(1,1)]
		for index in [0,1,2,0,2,3]:
			surface.set_uv(uv[index])
			surface.add_vertex(points[index])
	surface.generate_normals()
	var node := MeshInstance3D.new()
	node.mesh = surface.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = texture(asset_id)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.5
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	node.material_override = mat
	return node

## 每支箭拥有独立材质；淡出时改用透明混合，不能让 alpha scissor 在半透明时突然整支裁掉。
static func set_opacity(node: MeshInstance3D, opacity: float) -> void:
	var mat := node.material_override as StandardMaterial3D
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = clampf(opacity,0,1)
