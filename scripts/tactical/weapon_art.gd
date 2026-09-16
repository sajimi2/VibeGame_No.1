extends RefCounted
## Small faceted world-space weapons, shared by player and enemies.
static func material(color: String) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color=Color(color)
	mat.specular_mode=BaseMaterial3D.SPECULAR_DISABLED
	mat.diffuse_mode=BaseMaterial3D.DIFFUSE_TOON
	return mat
static func block(parent: Node3D, size: Vector3, at: Vector3, color: String) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size=size
	node.mesh=mesh
	node.material_override=material(color)
	parent.add_child(node)
	node.position=at
	return node
static func sword() -> MeshInstance3D:
	var root := MeshInstance3D.new()
	var blade := SurfaceTool.new()
	blade.begin(Mesh.PRIMITIVE_TRIANGLES)
	var points := [Vector3(-0.075,0,-0.22),Vector3(0.075,0,-0.22),Vector3(0.095,0,-1.35),Vector3(0,0,-1.7),Vector3(-0.065,0,-1.37)]
	for i in range(1,4):
		for p in [points[0],points[i],points[i+1]]: blade.add_vertex(p)
	blade.generate_normals()
	root.mesh=blade.commit()
	var mat := material("a7bac0")
	mat.cull_mode=BaseMaterial3D.CULL_DISABLED
	root.material_override=mat
	block(root,Vector3(0.027,0.027,1.15),Vector3(-0.05,0.015,-0.82),"e1e5d0")
	block(root,Vector3(0.105,0.10,0.29),Vector3(0,0,-0.045),"503b2e")
	for z in [-0.13,-0.06,0.01]: block(root,Vector3(0.113,0.108,0.018),Vector3(0,0,z),"9a7950")
	block(root,Vector3(0.35,0.08,0.085),Vector3(0,0,-0.24),"b39453")
	block(root,Vector3(0.15,0.13,0.08),Vector3(0,0,0.13),"889ba1")
	return root
static func bow() -> MeshInstance3D:
	var root := MeshInstance3D.new()
	var grip := BoxMesh.new()
	grip.size=Vector3(0.10,0.24,0.10)
	root.mesh=grip
	root.material_override=material("513d30")
	root.position.z=-0.33
	var string := ImmediateMesh.new()
	string.surface_begin(Mesh.PRIMITIVE_LINES)
	string.surface_add_vertex(Vector3(0,-0.63,0.02))
	string.surface_add_vertex(Vector3(0,0,0.18))
	string.surface_add_vertex(Vector3(0,0,0.18))
	string.surface_add_vertex(Vector3(0,0.63,0.02))
	string.surface_end()
	var thread := MeshInstance3D.new()
	thread.mesh=string
	thread.material_override=material("d6cba6")
	root.add_child(thread)
	for i in 10:
		var a := Vector3(0,-0.63+i*0.126,-0.22*cos((-0.63+i*0.126)/1.26*PI))
		var b := Vector3(0,-0.63+(i+1)*0.126,-0.22*cos((-0.63+(i+1)*0.126)/1.26*PI))
		var limb := block(root,Vector3(0.075,a.distance_to(b)+0.01,0.065),(a+b)*0.5,"b48b52" if i%2==0 else "896139")
		limb.rotation.x=atan2(b.z-a.z,b.y-a.y)
	block(root,Vector3(0.11,0.22,0.12),Vector3(0,0,-0.22),"59442f")
	return root
