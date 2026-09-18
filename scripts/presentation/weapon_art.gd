extends RefCounted
## 玩家和敌人共用的低面数 3D 武器模型。
const ArrowArt = preload("res://scripts/presentation/arrow_art.gd")
const SHIELD_CENTER := Vector3(0.36,-0.12,-0.25)
const SHIELD_SIZE := Vector3(0.48,0.65,0.11)

static func material(color: String) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color=Color(color)
	mat.specular_mode=BaseMaterial3D.SPECULAR_DISABLED
	mat.diffuse_mode=BaseMaterial3D.DIFFUSE_TOON
	return mat

## 创建武器装饰用的小长方体网格，不附带碰撞。
static func block(parent: Node3D, size: Vector3, at: Vector3, color: String) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size=size
	node.mesh=mesh
	node.material_override=material(color)
	parent.add_child(node)
	node.position=at
	return node

## 所有刀剑共用封闭挤出：上下表面、侧面及正确面朝向一起生成，避免新增型号又退回单面。
static func solid_blade(points: PackedVector3Array, thickness: float) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := thickness*0.5
	for side in [-1,1]:
		for i in range(1,points.size()-1):
			var face := [points[0],points[i],points[i+1]] if side>0 else [points[0],points[i+1],points[i]]
			for point in face: surface.add_vertex(point+Vector3.UP*half*side)
	for i in points.size():
		var a := points[i]
		var b := points[(i+1)%points.size()]
		for point in [a+Vector3.UP*half,b-Vector3.UP*half,b+Vector3.UP*half,a+Vector3.UP*half,a-Vector3.UP*half,b-Vector3.UP*half]: surface.add_vertex(point)
	surface.generate_normals()
	return surface.commit()

## 宝剑与守卫共用同一实体刀身，外轮廓和长度保持原尺寸。
static func sword() -> MeshInstance3D:
	var root := MeshInstance3D.new()
	var points := [Vector3(-0.075,0,-0.22),Vector3(0.075,0,-0.22),Vector3(0.095,0,-1.35),Vector3(0,0,-1.7),Vector3(-0.065,0,-1.37)]
	root.mesh=solid_blade(PackedVector3Array(points),0.06)
	var mat := material("a7bac0")
	mat.cull_mode=BaseMaterial3D.CULL_DISABLED
	root.material_override=mat
	block(root,Vector3(0.027,0.027,1.15),Vector3(-0.05,0.04,-0.82),"e1e5d0")
	block(root,Vector3(0.105,0.10,0.29),Vector3(0,0,-0.045),"503b2e")
	for z in [-0.13,-0.06,0.01]: block(root,Vector3(0.113,0.108,0.018),Vector3(0,0,z),"9a7950")
	block(root,Vector3(0.35,0.08,0.085),Vector3(0,0,-0.24),"b39453")
	block(root,Vector3(0.15,0.13,0.08),Vector3(0,0,0.13),"889ba1")
	return root

## 玩家刀具保留握柄原点；反持由动作曲线控制，模型本身始终向局部 -Z 延伸。
static func melee_model(id: String) -> MeshInstance3D:
	if id not in ["knife","cleaver"]: return sword()
	var heavy := id == "cleaver"
	var root := MeshInstance3D.new()
	var tip := 1.7 if heavy else 0.95
	var breadth := 0.16 if heavy else 0.06
	var points := [Vector3(-breadth,0,-0.19),Vector3(breadth,0,-0.19),Vector3(breadth,0,-tip+0.18),Vector3(-breadth*0.3,0,-tip),Vector3(-breadth,0,-tip+0.08)]
	# 封闭刀身有上下表面和刀背，侧视不再消失；真实体积也参与太阳投影。
	var half := 0.055 if heavy else 0.015
	root.mesh = solid_blade(PackedVector3Array(points),half*2)
	var mat := material("829397" if heavy else "b9c6c5")
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	root.material_override = mat
	block(root,Vector3(0.025,0.025,tip-0.3),Vector3(-breadth+0.018,half+0.005,-(tip+0.16)*0.5),"dae0d1")
	block(root,Vector3(0.09,0.085,0.23),Vector3(0,0,-0.015),"4b372d")
	for z in [-0.09,-0.015,0.06]: block(root,Vector3(0.10,0.092,0.015),Vector3(0,0,z),"9f8155")
	block(root,Vector3(0.27 if heavy else 0.15,0.06,0.06),Vector3(0,0,-0.17),"b09961")
	root.set_meta("blade_base",Vector3(0,0,-0.24))
	root.set_meta("blade_tip",Vector3(-breadth*0.3,0,-tip))
	return root

## 创建弓身、弓弦及搭在弦上的展示箭，供拉弓动画使用。
static func bow() -> MeshInstance3D:
	var root := MeshInstance3D.new()
	var grip := BoxMesh.new()
	grip.size=Vector3(0.10,0.24,0.10)
	root.mesh=grip
	root.material_override=material("513d30")
	# 原点即握柄中心，与纸片手心对齐；弓身不能再额外前移。
	root.position.z=0
	var string := ImmediateMesh.new()
	string.surface_begin(Mesh.PRIMITIVE_LINES)
	string.surface_add_vertex(Vector3(0,-0.63,0.02))
	string.surface_add_vertex(Vector3(0,0,0.18))
	string.surface_add_vertex(Vector3(0,0,0.18))
	string.surface_add_vertex(Vector3(0,0.63,0.02))
	string.surface_end()
	var thread := MeshInstance3D.new()
	thread.name="BowString"
	thread.mesh=string
	thread.material_override=material("d6cba6")
	root.add_child(thread)
	var nocked := ArrowArt.model()
	root.add_child(nocked)
	nocked.position.z = 0.18 - ArrowArt.LENGTH
	nocked.name="NockedArrow"
	for i in 10:
		var a := Vector3(0,-0.63+i*0.126,-0.22*cos((-0.63+i*0.126)/1.26*PI))
		var b := Vector3(0,-0.63+(i+1)*0.126,-0.22*cos((-0.63+(i+1)*0.126)/1.26*PI))
		var limb := block(root,Vector3(0.075,a.distance_to(b)+0.01,0.065),(a+b)*0.5,"b48b52" if i%2==0 else "896139")
		limb.rotation.x=atan2(b.z-a.z,b.y-a.y)
	block(root,Vector3(0.11,0.22,0.12),Vector3(0,0,-0.22),"59442f")
	return root

## 按拉弓量重画弓弦并移动展示箭；真正的飞行箭由战斗模块创建。
static func set_bow_draw(root: Node3D, amount: float, nocked: bool=true) -> void:
	var string: ImmediateMesh=root.get_node("BowString").mesh
	string.clear_surfaces()
	string.surface_begin(Mesh.PRIMITIVE_LINES)
	for point in [Vector3(0,-0.63,0.02),Vector3(0,0,0.02+amount*0.30),Vector3(0,0,0.02+amount*0.30),Vector3(0,0.63,0.02)]: string.surface_add_vertex(point)
	string.surface_end()
	root.get_node("NockedArrow").visible=nocked
	root.get_node("NockedArrow").position.z=0.02+amount*0.30-ArrowArt.LENGTH
