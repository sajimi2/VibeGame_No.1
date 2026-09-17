extends MeshInstance3D
## A short, depth-tested blade ribbon marks the active part of a swing.
var samples: Array=[]
var surface := ImmediateMesh.new()
func _ready() -> void:
	top_level=true
	mesh=surface
	cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo=true
	mat.cull_mode=BaseMaterial3D.CULL_DISABLED
	material_override=mat
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
