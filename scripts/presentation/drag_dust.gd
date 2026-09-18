extends Node3D
## 少量短寿命像素尘；调用者只在刀尖真实接地且移动时通知，不持续冒烟。
var particles: Array[Dictionary] = []
var cooldown := 0.0
var emitted := 0
var bursts := 0

## 重击扬尘与拖地颗粒共用寿命清理；一次冲击成扇形飞散，数量与范围都有上限。
func burst(point: Vector3, direction: Vector3) -> void:
	bursts += 1
	for i in 24:
		if particles.size()>=48: break
		var node := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		var size := 0.09+0.10*(i%4)/3.0
		mesh.size = Vector3(size,size*0.6,size)
		node.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("9d9276").lightened((i%3)*0.055)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		node.material_override = mat
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		node.global_position = point+Vector3.UP*0.06
		var velocity := direction.rotated(Vector3.UP,(float(i)/23-0.5)*TAU*0.85)*(1.2+(i%5)*0.38)+Vector3.UP*(0.7+(i%4)*0.25)
		particles.append({"node":node,"age":0.0,"drift":velocity,"life":0.72,"gravity":3.0})

func contact(point: Vector3) -> void:
	if cooldown > 0 or particles.size() >= 6: return
	cooldown = 0.16
	emitted += 1
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.035,0.025,0.035)
	node.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("9d9276")
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	node.global_position = point+Vector3.UP*0.025
	node.transparency = 0.45
	particles.append({"node":node,"age":0.0,"drift":Vector3(sin(emitted*2.4)*0.06,0.13,cos(emitted*2.4)*0.06)})

func _physics_process(delta: float) -> void:
	cooldown = maxf(0,cooldown-delta)
	for i in range(particles.size()-1,-1,-1):
		var item := particles[i]
		item.age += delta
		item.drift.y -= float(item.get("gravity",0))*delta
		item.node.position += item.drift*delta
		var life := float(item.get("life",0.38))
		item.node.transparency = lerpf(0.35,1.0,item.age/life)
		if item.age >= life:
			item.node.queue_free()
			particles.remove_at(i)
