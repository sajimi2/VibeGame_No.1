extends MeshInstance3D
## 保留世界刀刃轨迹，烘焙为像素刀光；有效窗口和四帧寿命仍由原采样规则控制。
const Baker = preload("res://scripts/art/weapon_sprite_baker.gd")
const GpuFrame = preload("res://scripts/presentation/pixel_frame_gpu.gd")
var samples: Array=[]
var surface := ImmediateMesh.new()
var card: MeshInstance3D
var pixel_material: ShaderMaterial
var gpu_frame: Node
var pixel_triangles: Array = []
var pixel_basis := Basis.IDENTITY
var last_key := ""

## 仅供离线检查/导出；实时刀光不读回图像，也不上传新纹理。
func capture_frame() -> Dictionary:
	return Baker.bake(pixel_triangles,pixel_basis,Vector3.UP)

## 刀光使用世界坐标，不跟随父节点的后续变换。
func _ready() -> void:
	top_level=true
	# top_level 只断开后续继承，仍保留入树时的变换；世界坐标顶点必须配单位变换。
	global_transform=Transform3D.IDENTITY
	mesh=surface
	cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 保留真实轨迹网格给几何检查，实际外观由下面的像素纸片承担，不重复显示。
	var hidden_shader := Shader.new()
	hidden_shader.code = "shader_type spatial; void fragment() { discard; }"
	var hidden := ShaderMaterial.new()
	hidden.shader = hidden_shader
	material_override=hidden
	card = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE*Baker.SIZE*Baker.PIXEL_SIZE
	card.mesh = quad
	card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pixel_material = ShaderMaterial.new()
	pixel_material.shader = preload("res://scripts/presentation/pixel_weapon.gdshader")
	pixel_material.set_shader_parameter("dither_fade",true)
	card.material_override = pixel_material
	add_child(card)
	if DisplayServer.get_name()!="headless":
		gpu_frame = GpuFrame.new()
		add_child(gpu_frame)
		gpu_frame.bind(pixel_material)
	card.hide()
	process_priority = 35

## 端点仍为真实世界坐标；显示时才投到相机像素网格，深度图保留墙前/墙后的局部遮挡。
func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	card.visible = is_visible_in_tree() and samples.size()>=2 and is_instance_valid(camera)
	if not card.visible:
		last_key=""
		if is_instance_valid(gpu_frame): gpu_frame.suspend()
		return
	var center: Vector3 = (samples.front().base+samples.back().tip)*0.5
	card.global_transform = Transform3D(camera.global_basis,center)
	var size := get_viewport().get_visible_rect().size
	var margin := Baker.SIZE*Baker.PIXEL_SIZE/camera.size*size.y
	if camera.is_position_behind(center) or not Rect2(-Vector2.ONE*margin,size+Vector2.ONE*margin*2).has_point(camera.unproject_position(center)):
		last_key = ""
		if is_instance_valid(gpu_frame): gpu_frame.suspend()
		return
	var key := str(hash(samples),camera.global_basis)
	if key==last_key: return
	last_key = key
	var triangles: Array = []
	for i in range(1,samples.size()):
		var a: Dictionary = samples[i-1]
		var b: Dictionary = samples[i]
		var color := Color("f7efbe") if b.life>=3 else Color("c6b56f")
		color.a = b.life/4.0
		for points in [[a.base,a.tip,b.tip],[a.base,b.tip,b.base]]:
			triangles.append({"points":[points[0]-center,points[1]-center,points[2]-center],"color":color,"unlit":true})
	pixel_triangles = triangles
	pixel_basis = camera.global_basis.inverse()
	if is_instance_valid(gpu_frame):
		gpu_frame.set_triangles(triangles,true)
		gpu_frame.draw(pixel_basis,Vector3.UP)

## 保留最近数帧刀刃端点，将相邻采样连成短带；有效挥刀阶段结束后逐帧消退。
func sample_blade(active: bool, base: Vector3, tip: Vector3) -> void:
	for item in samples: item.life-=1
	samples=samples.filter(func(item): return item.life>0)
	if active: samples.append({"base":base,"tip":tip,"life":4})
	surface.clear_surfaces()
	if samples.size()<2: return
	surface.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(1,samples.size()):
		var a: Dictionary=samples[i-1]
		var b: Dictionary=samples[i]
		surface.surface_set_color(Color(0.86,0.89,0.75,0.12+0.06*i))
		for point in [a.base,a.tip,b.tip,a.base,b.tip,b.base]: surface.surface_add_vertex(point)
	surface.surface_end()
