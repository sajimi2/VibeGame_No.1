extends Node3D
## 蝴蝶与落叶是有限数量的纯表现节点，不创建任何物理体、射线或寻路数据。
var elapsed:=0.0
var butterflies: Array[Dictionary]=[]
var leaves: Array[Dictionary]=[]
var animated:=true

func setup(layout: Dictionary) -> void:
	var rng:=RandomNumberGenerator.new()
	rng.seed=913
	for point in layout.butterflies:
		var butterfly:=Node3D.new()
		add_child(butterfly)
		var wings: Array[Node3D]=[]
		for sign_value in [-1,1]:
			var wing:=_paper(Vector2(.09,.12),Color("ead49a") if butterflies.size()%2==0 else Color("bd742f"))
			butterfly.add_child(wing)
			wing.position.x=sign_value*.043
			wings.append(wing)
		butterflies.append({"node":butterfly,"origin":_point(point),"phase":rng.randf()*TAU,"wings":wings})
	for origin in layout.leaf_origins:
		for i in 7:
			var leaf:=_paper(Vector2(.055,.11),Color("b39b4d") if i%2==0 else Color("947640"))
			add_child(leaf)
			leaves.append({"node":leaf,"origin":_point(origin)+Vector3(rng.randf_range(-1.5,1.5),0,rng.randf_range(-1,1)),"phase":rng.randf()*9.0,"speed":rng.randf_range(.45,.65)})
	_process(0)

func _point(values: Array) -> Vector3: return Vector3(values[0],values[1],values[2])

func _paper(size: Vector2,color: Color) -> MeshInstance3D:
	var node:=MeshInstance3D.new()
	var mesh:=QuadMesh.new()
	mesh.size=size
	node.mesh=mesh
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material:=StandardMaterial3D.new()
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode=BaseMaterial3D.CULL_DISABLED
	material.albedo_color=color
	node.material_override=material
	return node

func _process(delta: float) -> void:
	if not animated: return
	elapsed+=delta
	for item in butterflies:
		var phase: float=elapsed+item.phase
		item.node.position=item.origin+Vector3(sin(phase*.8)*.55,sin(phase*2.1)*.15,cos(phase*.65)*.4)
		item.node.rotation=Vector3(-.5,phase*.3,0)
		for i in 2: item.wings[i].rotation.y=sin(phase*19)*(1 if i==0 else -1)*1.15
	for item in leaves:
		var time: float=fmod(elapsed+item.phase,item.origin.y/item.speed)
		item.node.position=item.origin+Vector3(sin(time*1.5+item.phase)*.5,time*-item.speed,time*.14)
		item.node.rotation=Vector3(time*2,time*1.4,item.phase+time*.8)
