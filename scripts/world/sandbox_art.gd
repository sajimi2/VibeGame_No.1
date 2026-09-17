extends RefCounted
## 原创程序环境素材，由几何体和色块生成。

## 在两端点之间放置并旋转长方体，组成支撑梁或木栏。
static func beam(lab: Node3D, label: String, a: Vector3, b: Vector3, width: float, kind: String = "wood") -> void:
	var body: StaticBody3D = lab.box(label, (a+b)*0.5, Vector3(width,a.distance_to(b),width),kind)
	body.quaternion = Quaternion(Vector3.UP,(b-a).normalized())

## 用固定种子生成不规则地面色块；仅显示，不创建碰撞。
static func patch(lab: Node3D, center: Vector3, radius: Vector2, color: Color, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rim := PackedVector3Array()
	for i in 18:
		var angle := i * TAU / 18.0
		var scale := rng.randf_range(0.83,1.12)
		rim.append(center + Vector3(cos(angle)*radius.x*scale,0,sin(angle)*radius.y*scale))
	for i in 18:
		for v in [center,rim[i],rim[(i+1)%18]]: surface.add_vertex(v)
	surface.generate_normals()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var visual := MeshInstance3D.new()
	visual.mesh = surface.commit()
	visual.material_override = mat
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lab.add_child(visual)

## 组合入口路面、哨塔和木箱等试验场环境。
static func build(lab: Node3D) -> void:
	# 用磨损地面色块连接哨塔入口与林间空地。
	for i in 24:
		var t := i / 23.0
		var point := Vector3(-8 + 4*t + sin(t*5)*0.5,0.009+i*0.0001,13.4-9*t)
		patch(lab,point,Vector2(0.95,0.7),Color("62634a"),100+i)
		patch(lab,point+Vector3(0,0.004,0),Vector2(0.62,0.6),Color("786d54"),200+i)
	for center in [Vector3(-12,0.02,0),Vector3(12,0.02,-3),Vector3(2,0.02,9),Vector3(-12.5,0.02,10)]:
		patch(lab,center,Vector2(1.35,0.9),Color("49563e"),11)
		var rng := RandomNumberGenerator.new()
		rng.seed = 481
		for i in 18:
			var point: Vector3 = center + Vector3(rng.randf_range(-1.3,1.3),0.003,rng.randf_range(-0.8,0.8))
			patch(lab,point,Vector2(0.07,0.04),Color("8a8150") if i%3 == 0 else Color("5c6c43"),i)
	build_tower(lab)
	for spec in [Vector4(-0.5,0,10,1.2),Vector4(-0.5,1.2,10,0.8),Vector4(1.25,0,11.2,1.2)]:
		var center := Vector3(spec.x,spec.y+spec.w*0.5,spec.z)
		lab.box("ReferenceCrate",center,Vector3.ONE*spec.w,"wood")
		# 细边条帮助区分木箱各面，仅作装饰。
		for x in [-1,1]:
			for z in [-1,1]:
				lab.box("CrateUpright",center+Vector3(x*spec.w*0.5,0,z*spec.w*0.5),Vector3(0.055,spec.w,0.055),"wood_frame",0)
		for y in [-1,1]:
			for z in [-1,1]:
				lab.box("CrateRim",center+Vector3(0,y*spec.w*0.5,z*spec.w*0.5),Vector3(spec.w,0.06,0.06),"wood_frame",0)
	lab._label("木箱 · 绕行观察侧面",Vector3(0.2,2.5,10.5))

## 生成可从坡道登上的单层哨塔，栏杆在坡道出口留口。
static func build_tower(lab: Node3D) -> void:
	var o := Vector3(-8,0,9)
	# 矮石基支撑可登上的单层木平台。
	lab.box("TowerPlinth",o+Vector3(0,0.5,0),Vector3(4.2,1,3.4),"stone")
	lab.box("TowerFloorSupport",o+Vector3(0,1.09,0),Vector3(4.2,0.21,3.4),"wood")
	for i in 14:
		var length := 3.4 if i < 11 else 3.05 - (i-11)*0.25
		lab.box("TowerFloor",o+Vector3(-2.02+i*0.31,1.1,-(3.4-length)*0.5),Vector3(0.29,0.2,length),"wood",0)
	lab.ramp("TowerAccess",o+Vector3(0,0,3.7),1.6,2,1.2)
	var ramp: StaticBody3D = lab.get_node("TowerAccess")
	ramp.get_child(1).material_override = lab.material("wood")
	# 横木条沿坡面铺设，通行碰撞由连续坡道负责。
	for i in 10:
		var t := (i+0.5)/10.0
		var board: StaticBody3D = lab.box("RampSlat",o+Vector3(0,1.2*t+0.012,3.7-2*t),Vector3(1.59,0.025,0.17),"wood",0)
		board.rotation.x = atan(0.6)
	# 参差石墙中留出后墙窄窗。
	for column in 7:
		var x := -1.83 + column*0.61
		var courses: int = [9,8,6,7,6,5,4][column]
		for row in courses:
			if column == 3 and row in [3,4,5]: continue
			var block: StaticBody3D = lab.box("TowerBrokenStone",o+Vector3(x,1.2+0.2+row*0.43,-1.57),Vector3(0.58,0.40,0.44),"wall")
			if row == courses-1: block.rotation.z = (-0.09 if column%2 == 0 else 0.07)
	for segment in 5:
		var height := 2.9-segment*0.43
		lab.box("TowerSideRemnant",o+Vector3(-2,1.2+height*0.5,-1.3+segment*0.6),Vector3(0.43,height,0.55),"wall")
	# 生成残存木框架、支撑梁和少量顶板。
	for point in [Vector3(-1.65,0,-1.25),Vector3(1.65,0,-1.25),Vector3(1.65,0,1.25)]:
		beam(lab,"TowerPost",o+point+Vector3.UP*1.2,o+point+Vector3.UP*4.45,0.18)
	beam(lab,"TowerTopBeam",o+Vector3(-1.85,4.5,-1.25),o+Vector3(1.9,4.5,-1.25),0.21)
	beam(lab,"TowerBrace",o+Vector3(1.65,2,-1.25),o+Vector3(1.65,4,1.25),0.14)
	beam(lab,"BrokenRafter",o+Vector3(-1.65,4.5,-1.45),o+Vector3(-1.65,4.85,0.7),0.18)
	for i in 4:
		var plank: StaticBody3D = lab.box("RemainingRoof",o+Vector3(-1.15+i*0.43,4.65,-0.65),Vector3(0.38,0.10,1.6-i*0.19),"wood")
		plank.rotation.x = 0.15
	# 前栏杆在中央留口，确保坡道出口可通行。
	for x in [-1.8,1.8]:
		beam(lab,"RailPost",o+Vector3(x,1.2,1.5),o+Vector3(x,2.05,1.5),0.13)
	beam(lab,"BrokenRail",o+Vector3(-1.9,1.95,1.5),o+Vector3(-1,1.88,1.5),0.12)
	beam(lab,"BrokenRail",o+Vector3(1.0,1.87,1.5),o+Vector3(1.9,1.95,1.5),0.12)
	for i in 7:
		var block: StaticBody3D = lab.box("TowerRubble",o+Vector3(-2.65-(i%2)*0.3,0.14+(i%3)*0.035,-1.3+i*0.48),Vector3(0.45,0.28+(i%3)*0.07,0.4),"stone")
		block.rotation.y = i*0.63
	beam(lab,"FallenTimber",o+Vector3(2.6,0.13,-0.5),o+Vector3(3.2,0.13,1.1),0.18)
	lab._label("破损哨塔 · 木坡道登台",o+Vector3(0,4.9,0))
