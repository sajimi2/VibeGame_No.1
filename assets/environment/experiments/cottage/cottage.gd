extends Node3D
## 简模拥有形状/碰撞，平面图片拥有细节；投影坐标烘进资产网格，复制位置不会令贴图滑动。
const Roof=preload("res://scripts/presentation/interior_roof.gd")
const Library=preload("res://scripts/presentation/environment_library.gd")
const PROJECTIONS={
	"front":preload("res://assets/environment/experiments/cottage/projections/front.tres"),
	"side":preload("res://assets/environment/experiments/cottage/projections/side.tres"),
	"back":preload("res://assets/environment/experiments/cottage/projections/back.tres"),
	"roof":preload("res://assets/environment/experiments/cottage/projections/roof.tres")}
var roof: Node3D
var gray_material: ShaderMaterial
var surfaces: Dictionary={}
var art_enabled:=true

func _ready() -> void:
	gray_material=Library.material("plaster").duplicate()
	var color:=Image.create(1,1,false,Image.FORMAT_RGB8)
	color.fill(Color("aaa99f"))
	gray_material.set_shader_parameter("surface_texture",ImageTexture.create_from_image(color))
	roof=Roof.new()
	roof.name="Roof"
	roof.interior=AABB(Vector3(-2.15,-.2,-2.65),Vector3(4.3,3.0,5.3))
	roof.surface_material=_surface("roof","timber")
	var imported: Node3D=load("res://assets/environment/experiments/cottage/cottage_shell.glb").instantiate()
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
		var mapping: String="front" if front else "roof" if part.begins_with("Roof") else "side" if part in ["WallWest","WallEast"] else "back"
		var visual:=MeshInstance3D.new()
		visual.name=part if front or part=="GableBack" else "Visual"
		visual.transform=pose
		visual.mesh=PROJECTIONS[mapping].project(original.mesh,pose)
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
		var material: ShaderMaterial
		if front: material=_surface("front","plaster")
		elif part=="SupportFloor": material=_surface("floor","planks")
		elif part=="Crate": material=_surface("crate","wood")
		else: material=_surface("side","plaster")
		visual.material_override=material
		var collision:=CollisionShape3D.new()
		collision.name=part+"Collision"
		collision.transform=pose
		collision.shape=original.mesh.create_trimesh_shape()
		bodies[group].add_child(collision)
		bodies[group].add_child(visual)
	imported.free()
	add_child(roof)
	set_art_enabled(art_enabled)

## 图片、尺寸和朝向由资产资源持有；小屋装配不再包含专属 UV 计算器。
func _surface(id: String,fallback: String) -> ShaderMaterial:
	if surfaces.has(id): return surfaces[id]
	var material: ShaderMaterial=Library.material(fallback).duplicate()
	if PROJECTIONS.has(id): PROJECTIONS[id].configure(material)
	surfaces[id]=material
	return material

## 对比只切颜色；不动几何、碰撞、分组和当前透视状态。
func set_art_enabled(value: bool) -> void:
	art_enabled=value
	for material in surfaces.values(): material.set_shader_parameter("art_gray_preview",not value)
	if is_instance_valid(roof) and roof.roof_material!=null: roof.roof_material.set_shader_parameter("art_gray_preview",not value)
