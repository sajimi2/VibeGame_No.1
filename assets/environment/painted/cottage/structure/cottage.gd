extends Node3D
## 小屋空间代理只提供碰撞、承托、遮挡和灰模对照；精细外观由 painted_cottage 独立装配。
const Roof=preload("res://scripts/presentation/interior_roof.gd")
const Library=preload("res://scripts/presentation/environment_library.gd")
var roof: Node3D

func _ready() -> void:
	roof=Roof.new()
	roof.name="Roof"
	roof.interior=AABB(Vector3(-2.15,-.2,-2.65),Vector3(4.3,3.0,5.3))

	var imported: Node3D=load("res://assets/environment/painted/cottage/structure/cottage_shell.glb").instantiate()
	var bodies: Dictionary={}
	for original in imported.find_children("*","MeshInstance3D",true,false):
		var part:=str(original.name)
		var pose: Transform3D=original.transform
		var parent:=original.get_parent()
		while parent!=imported:
			pose=parent.transform*pose
			parent=parent.get_parent()
		var front:=part in ["WallFrontLeft","WallFrontRight","WallLintel","GableFront"]
		var group: String="FrontWall" if front else "WallBack" if part=="GableBack" else part
		var visual:=MeshInstance3D.new()
		visual.name=part if front or part=="GableBack" else "Visual"
		visual.transform=pose
		visual.mesh=original.mesh
		if part.begins_with("Roof"):
			visual.name=part
			roof.add_child(visual)
			continue
		if not bodies.has(group):
			var body:=StaticBody3D.new()
			body.name=group
			body.collision_layer=13
			body.collision_mask=0
			if part.begins_with("Support"): body.set_meta("occlusion_role","support")
			add_child(body)
			bodies[group]=body
		# 灰模模式仍可看见体积；生产画面隐藏墙/地板颜色，保留这些网格给几何检测。
		visual.material_override=Library.material("planks" if part=="SupportFloor" else "wood" if part=="Crate" else "plaster").duplicate()
		var collision:=CollisionShape3D.new()
		collision.name=part+"Collision"
		collision.transform=pose
		collision.shape=original.mesh.create_trimesh_shape()
		bodies[group].add_child(collision)
		bodies[group].add_child(visual)
	imported.free()
	add_child(roof)
