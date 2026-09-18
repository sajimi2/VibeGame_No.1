extends MeshInstance3D
## 短刀光带标记挥刀的有效阶段，参与深度测试以保留遮挡关系。
var samples: Array=[]
var surface := ImmediateMesh.new()

## 刀光使用世界坐标，不跟随父节点的后续变换。
func _ready() -> void:
	top_level=true
	# top_level 只断开后续继承，仍保留入树时的变换；世界坐标顶点必须配单位变换。
	global_transform=Transform3D.IDENTITY
	mesh=surface
	cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo=true
	mat.cull_mode=BaseMaterial3D.CULL_DISABLED
	material_override=mat

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
