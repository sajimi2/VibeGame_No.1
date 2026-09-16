extends RefCounted
## Dressing follows the existing walkable surfaces; roads have no collision.
const Sample = preload("res://scripts/tactical/outpost_sample.gd")
const Art = preload("res://scripts/tactical/weapon_art.gd")

static func road(lab: Node3D, points: Array, width: float, seed_value: int) -> void:
	var count := 0
	for i in range(points.size()-1):
		var a: Vector3=points[i]
		var b: Vector3=points[i+1]
		var steps := maxi(1,ceili(a.distance_to(b)/0.55))
		for step in steps:
			var p := a.lerp(b,float(step)/steps)
			p.y=0.025+count*0.00001
			Sample.patch(lab,p,Vector2(width,0.6),Color("64684e"),seed_value+count)
			Sample.patch(lab,p+Vector3.UP*0.003,Vector2(width*0.65,0.47),Color("7b7358"),seed_value+count+600)
			count+=1

static func signpost(lab: Node3D, point: Vector3, caption: String, facing_left: bool) -> void:
	# Low, nonblocking trail signs; text is deliberately used only at junctions.
	lab.box("TrailPost",point+Vector3.UP*0.5,Vector3(0.10,1,0.10),"wood",0)
	lab.box("TrailBoard",point+Vector3.UP*0.9,Vector3(0.9,0.3,0.10),"wood",0)
	var label := Label3D.new()
	label.text=("‹ " if facing_left else "")+caption+(" ›" if not facing_left else "")
	label.position=point+Vector3.UP*1.3
	label.font_size=22
	label.pixel_size=0.011
	label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate=Color("ecdbb0")
	lab.add_child(label)

static func build(lab: Node3D) -> void:
	# Extend the central ruin: it separates the western guard's approach from
	# the archer's sightline. Both ends remain physically walkable.
	lab.box("ApproachRemnant",Vector3(-1,1.5,-1.05),Vector3(0.65,3,3.1),"wall")
	road(lab,[Vector3(-3.5,0,11),Vector3(-4.3,0,6),Vector3(-3,0,3.5),Vector3(-2.5,0,0),Vector3(-2.5,0,-3.3),Vector3(0,0,-3.3),Vector3(0.3,0,1.6),Vector3(2,0,2.8),Vector3(5,0,2)],0.82,1800)
	# The eastern approach is an optional bypass, not a second locked corridor.
	road(lab,[Vector3(-3.5,0,11),Vector3(-2,0,12.5),Vector3(4,0,12.5),Vector3(8.5,0,8),Vector3(9,0,6.4)],0.63,2600)
	road(lab,[Vector3(9,0,5.5),Vector3(12,0,5),Vector3(12,0,1),Vector3(8,0,1.8),Vector3(5,0,2.6)],0.65,3100)
	Sample.patch(lab,Vector3(-3.5,0.03,11),Vector2(2,1.6),Color("786f55"),15)
	signpost(lab,Vector3(-2.5,0,8),"旧路 / 高地",true)
	signpost(lab,Vector3(5.7,0,10.8),"帘后小径",false)
	signpost(lab,Vector3(2.6,0,3.3),"密函高地",false)
	# A bedroll, supplies, notice board and a banked fire identify the camp.
	var camp := Node3D.new()
	camp.name="TrailCamp"
	lab.add_child(camp)
	Art.block(camp,Vector3(0.75,0.09,1.45),Vector3(-2.2,0.045,11.9),"5f7774")
	Art.block(camp,Vector3(0.75,0.19,0.27),Vector3(-2.2,0.15,11.3),"ad9970")
	Art.block(camp,Vector3(0.13,1.3,0.13),Vector3(-4.9,0.65,10),"705038")
	Art.block(camp,Vector3(1.05,0.72,0.12),Vector3(-4.9,1.05,10),"624a35")
	Art.block(camp,Vector3(0.60,0.44,0.02),Vector3(-4.9,1.05,10.07),"c4b88d")
	for i in 8:
		var angle := i*TAU/8
		Art.block(camp,Vector3(0.25,0.15,0.22),Vector3(-4.8+cos(angle)*0.45,0.08,12+sin(angle)*0.45),"60625b")
	for i in 3:
		var ember := Art.block(camp,Vector3(0.12+0.06*i,0.10+0.1*i,0.18),Vector3(-5+i*0.18,0.15,12),"daaa53" if i==1 else "aa6039")
		ember.material_override.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
