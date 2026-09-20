extends RefCounted
## 从当前颜色/深度图集采样身体轮廓。只缓存静态图页，不读取屏幕或改变角色播放。
var images: Dictionary={}

func image_for(texture: Texture2D) -> Image:
	var id:=texture.get_instance_id()
	if not images.has(id):
		var image:=texture.get_image()
		if image.is_compressed(): image.decompress()
		images[id]=image
	return images[id]

## 在同一个相机平面网格采样上下身，并保留重叠处最前表面，避免把腰部重复计权。
func points(visual: Node3D,camera: Camera3D) -> PackedVector3Array:
	var result:=PackedVector3Array()
	if not visual.active: return result
	var cells: Dictionary={}
	var step: float=visual.pixel_size*3.0
	var camera_inverse:=camera.global_transform.affine_inverse()
	for layer in visual.layers.values():
		var card: MeshInstance3D=layer.body
		if not card.is_visible_in_tree(): continue
		var mat: ShaderMaterial=card.material_override
		var color:=image_for(mat.get_shader_parameter("color_atlas"))
		var depth:=image_for(mat.get_shader_parameter("depth_atlas"))
		var rect: Vector4=mat.get_shader_parameter("frame_rect")
		var depth_rect: Vector4=mat.get_shader_parameter("depth_rect")
		var size: Vector2=layer.size
		var center:=camera_inverse*card.global_position
		for y in range(ceili((center.y-size.y*.5)/step),floori((center.y+size.y*.5)/step)+1):
			for x in range(ceili((center.x-size.x*.5)/step),floori((center.x+size.x*.5)/step)+1):
				var uv:=Vector2((x*step-center.x)/size.x+.5,.5-(y*step-center.y)/size.y)
				var at:=Vector2(rect.x,rect.y)+uv*Vector2(rect.z,rect.w)
				var pixel:=Vector2i(at*Vector2(color.get_size())).clamp(Vector2i.ZERO,color.get_size()-Vector2i.ONE)
				if color.get_pixelv(pixel).a<.5: continue
				var depth_uv:=Vector2(depth_rect.x,depth_rect.y)+uv*Vector2(depth_rect.z,depth_rect.w)
				var depth_pixel:=Vector2i(depth_uv*Vector2(depth.get_size())).clamp(Vector2i.ZERO,depth.get_size()-Vector2i.ONE)
				var data:=depth.get_pixelv(depth_pixel)
				var z:=center.z+((data.r*65280.0+data.g*255.0)/65535.0-.5)*6.0
				var key:=Vector2i(x,y)
				if not cells.has(key) or z>cells[key].z: cells[key]=Vector3(x*step,y*step,z)
	for point in cells.values(): result.append(camera.global_transform*point)
	return result
