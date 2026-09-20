extends SceneTree
## 为内景绘画输出固定正交配准草图和顶点屏幕坐标；不修改原碰撞或 Blender 源。
const FOLDER="res://assets/environment/painted/cottage/"
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var viewport:=SubViewport.new()
	viewport.size=Vector2i(768,768)
	viewport.own_world_3d=true
	viewport.transparent_bg=true
	root.add_child(viewport)
	var camera:=Camera3D.new()
	viewport.add_child(camera)
	camera.rotation_degrees=Vector3(-35,25,0)
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=9.5
	camera.position=Vector3(0,1.4,0)+camera.basis.z*26
	camera.current=true
	var planes: Dictionary={
		"floor":[Vector3(-2.35,.035,2.86),Vector3(2.35,.035,2.86),Vector3(2.35,.035,-2.86),Vector3(-2.35,.035,-2.86)],
		"west":[Vector3(-2.35,0,2.86),Vector3(-2.35,0,-2.86),Vector3(-2.35,2.8,-2.86),Vector3(-2.35,2.8,2.86)],
		"back":[Vector3(-2.35,0,-2.86),Vector3(2.35,0,-2.86),Vector3(2.35,2.8,-2.86),Vector3(-2.35,2.8,-2.86)]}
	var data: Dictionary={"canvas":768,"planes":{}}
	for label in planes:
		var arrays:=[]
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array(planes[label])
		arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([0,1,2,0,2,3])
		var mesh:=ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		var visual:=MeshInstance3D.new()
		visual.mesh=mesh
		var mat:=StandardMaterial3D.new()
		mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode=BaseMaterial3D.CULL_DISABLED
		mat.albedo_color=Color("95785e") if label=="floor" else Color("d0c5a3") if label=="west" else Color("afa486")
		visual.material_override=mat
		viewport.add_child(visual)
		var vertices: Array=[]
		var pixels: Array=[]
		for point in planes[label]:
			vertices.append([point.x,point.y,point.z])
			var pixel:=camera.unproject_position(point)
			pixels.append([pixel.x,pixel.y])
		data.planes[label]={"vertices":vertices,"pixels":pixels}
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	for i in 5: await process_frame
	RenderingServer.force_draw(false)
	viewport.get_texture().get_image().save_png(FOLDER+"interior_guide.png")
	# 草图可重生成，但不能覆盖人工确认的画稿配准坐标。
	FileAccess.open(FOLDER+"interior_guide_registration.json",FileAccess.WRITE).store_string(JSON.stringify(data,"\t"))
	quit()
