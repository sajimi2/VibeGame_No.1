extends StaticBody3D
## 试验场训练靶，只记录命中部位和次数，不参与真实奖励。
var strikes := 0
var last_region := ""
var feedback: Label3D
var flash := 0.0
var visual: MeshInstance3D

## 创建圆柱训练靶、顶部色块和命中反馈文字。
func _ready() -> void:
	collision_layer = 1 | 16
	collision_mask = 0
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 0.42
	cylinder.height = 1.5
	shape.shape = cylinder
	shape.position.y = 0.75
	add_child(shape)
	visual = MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.42
	mesh.bottom_radius = 0.42
	mesh.height = 1.5
	mesh.radial_segments = 12
	visual.mesh = mesh
	visual.position.y = 0.75
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("a48058")
	material.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	visual.material_override = material
	add_child(visual)
	var cap := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.43
	disc.bottom_radius = 0.43
	disc.height = 0.025
	disc.radial_segments = 12
	cap.mesh = disc
	cap.position.y = 1.505
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color("d3b76c")
	gold.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	gold.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	cap.material_override = gold
	add_child(cap)
	feedback = Label3D.new()
	feedback.text = "训练靶"
	feedback.position.y = 2
	feedback.font_size = 32
	feedback.pixel_size = 0.018
	feedback.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(feedback)

## 按法线与来袭方向区分顶部或身体命中，累计次数并触发闪烁。
func receive_strike(_point: Vector3, normal: Vector3, incoming: Vector3) -> String:
	strikes += 1
	last_region = "顶部" if normal.y > 0.65 and incoming.y < -0.05 else "身体"
	feedback.text = "%s · 第 %d 次命中" % [last_region, strikes]
	flash = 0.2
	return last_region

## 按帧衰减受击闪烁；训练靶不参与敌人 AI。
func _process(delta: float) -> void:
	flash = maxf(0, flash - delta)
	visual.material_override.albedo_color = Color("fff2bf") if flash > 0 else Color("a48058")
