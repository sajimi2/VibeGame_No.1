extends MeshInstance3D
## 固定落点/方向的地面预告；只表现锁定攻击，不跟踪玩家，也不参与伤害结算。
func setup(kind: String, distance: float) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	if kind=="slam":
		for i in 32:
			var a:=i*TAU/32
			var b:=(i+.72)*TAU/32
			quad(surface,Vector3(sin(a),0,cos(a))*(distance-.045),Vector3(sin(b),0,cos(b))*(distance-.045),Vector3(sin(b),0,cos(b))*distance,Vector3(sin(a),0,cos(a))*distance)
	else:
		for i in 10:
			var z:=float(i)/10*distance
			quad(surface,Vector3(-.065,0,z),Vector3(.065,0,z),Vector3(.065,0,z+distance*.055),Vector3(-.065,0,z+distance*.055))
	mesh=surface.commit()
	var material:=StandardMaterial3D.new()
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode=BaseMaterial3D.CULL_DISABLED
	material.albedo_color=Color("f1ba63")
	material_override=material
	cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible=false

func quad(surface: SurfaceTool,a: Vector3,b: Vector3,c: Vector3,d: Vector3) -> void:
	for point in [a,b,c,a,c,d]: surface.add_vertex(point)

func progress(fraction: float) -> void:
	material_override.albedo_color=Color("f1ba63").lerp(Color("ff6951"),clampf(fraction,0,1))
