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
	node.set_meta("pixel_bake_ignore",true) # 已是带透明纹理的像素箭，不能再次当无纹理网格烘焙。
	node.mesh = surface.commit()
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://scripts/presentation/arrow_sprite.gdshader")
	mat.set_shader_parameter("albedo_texture",texture(asset_id))
	mat.set_shader_parameter("albedo_color",Color.WHITE)
	mat.render_priority = 1
	node.material_override = mat
	# 身体后绘制不影响箭的世界投影；裁剪阴影代理只投影、不参与环境颜色采样。
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var shadow := MeshInstance3D.new()
	shadow.name = "ArrowShadow"
	shadow.mesh = node.mesh
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	var shadow_mat := StandardMaterial3D.new()
	shadow_mat.albedo_texture = texture(asset_id)
	shadow_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	shadow_mat.alpha_scissor_threshold = 0.5
	shadow_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	shadow.material_override = shadow_mat
	node.add_child(shadow)
	return node

## 每支箭拥有独立材质；淡出保持原半透明曲线，阴影用抖动逐步消失。
static func set_opacity(node: MeshInstance3D, opacity: float) -> void:
	var color: Color = node.material_override.get_shader_parameter("albedo_color")
	color.a = clampf(opacity,0,1)
	node.material_override.set_shader_parameter("albedo_color",color)
	var shadow: MeshInstance3D = node.get_node("ArrowShadow")
	shadow.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
	shadow.material_override.albedo_color.a = color.a
