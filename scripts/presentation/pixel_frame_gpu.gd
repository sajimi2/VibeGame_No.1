extends Node
## 纯显示后端：接收局部三角形、相机基底和光向，GPU 输出并排的颜色/深度图。
## 不读取角色或战斗；源模型仍负责真实阴影，CPU 烘焙器只用于人工导出与离线检查。
const Baker = preload("res://scripts/art/weapon_sprite_baker.gd")
const CaptureShader = preload("res://scripts/presentation/pixel_capture.gdshader")
var viewport: SubViewport
var color_mesh: MeshInstance3D
var depth_mesh: MeshInstance3D
var color_material: ShaderMaterial
var depth_material: ShaderMaterial

func _ready() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(Baker.SIZE*2,Baker.SIZE)
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.positional_shadow_atlas_size = 0
	add_child(viewport)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = Baker.SIZE*Baker.PIXEL_SIZE
	camera.position.z = Baker.DEPTH_SPAN*0.5
	camera.near = 0.001
	camera.far = Baker.DEPTH_SPAN+0.001
	viewport.add_child(camera)
	color_material = ShaderMaterial.new()
	color_material.shader = CaptureShader
	depth_material = ShaderMaterial.new()
	depth_material.shader = CaptureShader
	depth_material.set_shader_parameter("depth_pass",true)
	color_mesh = _instance(color_material,-Baker.SIZE*Baker.PIXEL_SIZE*0.5)
	depth_mesh = _instance(depth_material,Baker.SIZE*Baker.PIXEL_SIZE*0.5)

func _instance(mat: ShaderMaterial, x: float) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.position.x = x
	viewport.add_child(node)
	return node

## 仅几何变化时合批；日常转向只提交变换，不重建图像、不读回 GPU。
func set_triangles(triangles: Array, unlit := false) -> void:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for triangle in triangles:
		var a: Vector3 = triangle.points[0]
		var b: Vector3 = triangle.points[1]
		var c: Vector3 = triangle.points[2]
		var normal := (b-a).cross(c-a).normalized()
		for point in [a,b,c]:
			vertices.append(point)
			normals.append(normal)
			colors.append(triangle.color)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	if not vertices.is_empty(): mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	color_mesh.mesh = mesh
	depth_mesh.mesh = mesh
	for mat in [color_material,depth_material]: mat.set_shader_parameter("unlit",unlit)

## UPDATE_ONCE 保证静止、屏外或隐藏武器不重复渲染；颜色与深度在同一张纹理同步产出。
func draw(view: Basis, light_direction: Vector3) -> void:
	color_mesh.basis = view
	depth_mesh.basis = view
	color_material.set_shader_parameter("light_direction",light_direction)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func bind(material: ShaderMaterial) -> void:
	material.set_shader_parameter("packed_frame",true)
	material.set_shader_parameter("frame_color",viewport.get_texture())
	material.set_shader_parameter("frame_depth",viewport.get_texture())

func suspend() -> void:
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
