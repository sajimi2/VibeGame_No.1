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

## 将装饰直接做在源模型双面上；分区至少接近一个输出像素，避免只在三维放大图中可见。
static func blade_panel(parent: Node3D, points: PackedVector2Array, half: float, color: String) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1,1]:
		for i in range(1,points.size()-1):
			for p in ([points[0],points[i],points[i+1]] if side>0 else [points[0],points[i+1],points[i]]):
				surface.add_vertex(Vector3(p.x,side*(half+0.002),p.y))
	surface.generate_normals()
	var panel := MeshInstance3D.new()
	panel.mesh = surface.commit()
	panel.material_override = material(color)
	panel.material_override.cull_mode = BaseMaterial3D.CULL_DISABLED
	# 面板为双面着色细节，阴影仍由封闭主体承担。
	panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(panel)

## 玩家与守卫共用紧凑宝剑；缩小实体几何，像素外观、真实投影和刀光端点同步变化。
static func sword() -> MeshInstance3D:
	var root := MeshInstance3D.new()
	var points := [Vector3(-0.075,0,-0.22),Vector3(0.075,0,-0.22),Vector3(0.095,0,-1.35),Vector3(0,0,-1.7),Vector3(-0.065,0,-1.37)]
	root.mesh=solid_blade(PackedVector3Array(points),0.06)
	var mat := material("a7bac0")
	mat.cull_mode=BaseMaterial3D.CULL_DISABLED
	root.material_override=mat
	blade_panel(root,PackedVector2Array([Vector2(-0.075,-0.25),Vector2(-0.028,-0.28),Vector2(0,-1.62),Vector2(-0.065,-1.37)]),0.03,"e2e6cf")
	blade_panel(root,PackedVector2Array([Vector2(-0.02,-0.35),Vector2(0.027,-0.35),Vector2(0.02,-1.25),Vector2(0,-1.49)]),0.03,"526d78")
	blade_panel(root,PackedVector2Array([Vector2(0.03,-0.27),Vector2(0.07,-0.27),Vector2(0.07,-0.43),Vector2(0.03,-0.43)]),0.03,"c6b17b")
	block(root,Vector3(0.105,0.10,0.29),Vector3(0,0,-0.045),"503b2e")
	for z in [-0.13,-0.06,0.01]: block(root,Vector3(0.113,0.108,0.018),Vector3(0,0,z),"9a7950")
	block(root,Vector3(0.35,0.08,0.085),Vector3(0,0,-0.24),"b39453")
	for side in [-1,1]: block(root,Vector3(0.08,0.115,0.10),Vector3(side*0.17,0,-0.25),"dfca8b")
	block(root,Vector3(0.15,0.13,0.08),Vector3(0,0,0.13),"889ba1")
	block(root,Vector3(0.07,0.145,0.055),Vector3(0,0,0.13),"507d7a")
	var size_scale := 0.8
	var arrays := root.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for index in vertices.size(): vertices[index] *= size_scale
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var compact := ArrayMesh.new()
	compact.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	root.mesh = compact
	for detail in root.get_children():
		detail.position *= size_scale
		detail.scale *= size_scale
	root.set_meta("blade_base", Vector3(0,0,-0.24) * size_scale)
	root.set_meta("blade_tip", Vector3(0,0,-1.7) * size_scale)
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
	var bevel := 0.055 if heavy else 0.035
	blade_panel(root,PackedVector2Array([Vector2(-breadth,-0.22),Vector2(-breadth+bevel,-0.27),Vector2(-breadth*0.3,-tip+0.04),Vector2(-breadth,-tip+0.08)]),half,"d9e0ca")
	blade_panel(root,PackedVector2Array([Vector2(breadth-0.045,-0.25),Vector2(breadth,-0.25),Vector2(breadth,-tip+0.18),Vector2(breadth-0.045,-tip+0.24)]),half,"455b65")
	if heavy:
		for z in [-0.48,-0.88,-1.2]:
			blade_panel(root,PackedVector2Array([Vector2(0.035,z),Vector2(0.085,z-0.035),Vector2(0.085,z-0.095),Vector2(0.035,z-0.06)]),half,"9fafac")
	else:
		blade_panel(root,PackedVector2Array([Vector2(-0.02,-0.27),Vector2(0.025,-0.27),Vector2(0.02,-0.45),Vector2(-0.02,-0.4)]),half,"a08c61")
	block(root,Vector3(0.09,0.085,0.23),Vector3(0,0,-0.015),"4b372d")
	for z in [-0.09,-0.015,0.06]: block(root,Vector3(0.10,0.092,0.015),Vector3(0,0,z),"9f8155")
	block(root,Vector3(0.27 if heavy else 0.15,0.06,0.06),Vector3(0,0,-0.17),"b09961")
	block(root,Vector3(0.12,0.12,0.07),Vector3(0,0,0.12),"717f83")
	root.set_meta("blade_base",Vector3(0,0,-0.24))
	root.set_meta("blade_tip",Vector3(-breadth*0.3,0,-tip))
	return root

## 盾面分出木板、金属包边、中央护脐和铆钉；碰撞/附着仍使用既有 SHIELD_SIZE。
static func shield() -> MeshInstance3D:
	var root := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = SHIELD_SIZE
	root.mesh = box
	root.material_override = material("445c60")
	for x in [-0.15,0.0,0.15]: block(root,Vector3(0.125,0.55,0.018),Vector3(x,0,-0.061),"687e76" if x==0 else "566961")
	# 包边稍突出木板，横边再包住竖边；避免共面深度竞争使 GPU/导出随机露出底色。
	for x in [-0.218,0.218]: block(root,Vector3(0.05,0.65,0.13),Vector3(x,0,0),"aa996b")
	for y in [-0.30,0.30]: block(root,Vector3(0.49,0.06,0.134),Vector3(0,y,0),"c0b17e")
	block(root,Vector3(0.48,0.055,0.144),Vector3.ZERO,"b2a374")
	var boss := block(root,Vector3(0.16,0.16,0.08),Vector3(0,0,-0.095),"bac2ad")
	boss.rotation.z = PI/4
	for point in [Vector2(-0.19,-0.25),Vector2(0.19,-0.25),Vector2(-0.19,0.25),Vector2(0.19,0.25)]:
		block(root,Vector3(0.045,0.045,0.035),Vector3(point.x,point.y,-0.076),"e0c993")
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
	var thread := Node3D.new()
	thread.name="BowString"
	root.add_child(thread)
	for i in 2: block(thread,Vector3(0.035,0.65,0.035),Vector3.ZERO,"d6cba6")
	var nocked := ArrowArt.model()
	root.add_child(nocked)
	nocked.position.z = 0.18 - ArrowArt.LENGTH
	nocked.name="NockedArrow"
	for i in 10:
		var a := Vector3(0,-0.63+i*0.126,-0.22*cos((-0.63+i*0.126)/1.26*PI))
		var b := Vector3(0,-0.63+(i+1)*0.126,-0.22*cos((-0.63+(i+1)*0.126)/1.26*PI))
		var limb := block(root,Vector3(0.075,a.distance_to(b)+0.01,0.065),(a+b)*0.5,"b48b52" if i%2==0 else "896139")
		limb.rotation.x=atan2(b.z-a.z,b.y-a.y)
		if i in [0,2,7,9]:
			var binding := block(root,Vector3(0.092,0.052,0.08),(a+b)*0.5,"dfc388" if i in [0,9] else "594b3a")
			binding.rotation.x=limb.rotation.x
	block(root,Vector3(0.11,0.22,0.12),Vector3(0,0,-0.22),"59442f")
	for y in [-0.08,0,0.08]: block(root,Vector3(0.12,0.035,0.13),Vector3(0,y,-0.22),"9f8057")
	set_bow_draw(root,0)
	return root

## 按拉弓量重画弓弦并移动展示箭；真正的飞行箭由战斗模块创建。
static func set_bow_draw(root: Node3D, amount: float, nocked: bool=true) -> void:
	var phase := clampi(roundi(amount*8),0,8)
	if int(root.get_meta("pixel_revision",-1))!=phase:
		var thread := root.get_node("BowString")
		var middle := Vector3(0,0,0.02+phase/8.0*0.30)
		for i in 2:
			var end := Vector3(0,-0.63 if i==0 else 0.63,0.02)
			var segment: MeshInstance3D = thread.get_child(i)
			segment.position = (end+middle)*0.5
			segment.mesh.size.y = end.distance_to(middle)
			segment.rotation.x = atan2(end.z-middle.z,end.y-middle.y)
		root.set_meta("pixel_revision",phase)
	root.get_node("NockedArrow").visible=nocked
	root.get_node("NockedArrow").position.z=0.02+amount*0.30-ArrowArt.LENGTH
