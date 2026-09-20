extends Node3D
## 简模拥有形状/碰撞，平面图片拥有细节；投影坐标烘进资产网格，复制位置不会令贴图滑动。
const Roof=preload("res://scripts/presentation/interior_roof.gd")
const Library=preload("res://scripts/presentation/environment_library.gd")
const TEXTURES="res://assets/environment/experiments/cottage/textures/"
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
	roof.surface_material=_surface("roof",Vector2(201,98),"timber")
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
		visual.mesh=_project_mesh(original.mesh,pose,mapping)
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
		if front: material=_surface("front",Vector2(150,123),"plaster")
		elif part=="SupportFloor": material=_surface("floor",Vector2.ZERO,"planks")
		elif part=="Crate": material=_surface("crate",Vector2.ZERO,"wood")
		else: material=_surface("side",Vector2(180,84),"plaster")
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

## 单面立面投影：UV 是整片墙坐标，不按门左/门右重新铺图；内侧使用原灰泥而非外墙窗户。
func _project_mesh(source: Mesh,pose: Transform3D,kind: String) -> ArrayMesh:
	var result:=ArrayMesh.new()
	for index in source.get_surface_count():
		var arrays:=source.surface_get_arrays(index).duplicate(true)
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
		var uv:=PackedVector2Array()
		var mask:=PackedVector2Array()
		var normal_basis:=pose.basis.inverse().transposed()
		for i in vertices.size():
			var p:=pose*vertices[i]
			var n: Vector3=(normal_basis*normals[i]).normalized()
			var at: Vector2
			var exterior:=false
			if kind=="front":
				at=Vector2((p.x+2.5)/5.0,1-p.y/4.1)
				exterior=n.z>.7
			elif kind=="side":
				at=Vector2((p.z+3)/6.0,1-p.y/2.8)
				exterior=n.x*signf(p.x)>.7
			elif kind=="roof":
				at=Vector2((p.z+3.35)/6.7,absf(p.x)/2.9)
				exterior=n.y>.7
			else:
				at=Vector2((p.x+2.5)/5.0,1-p.y/2.8)
				exterior=n.z<-.7
			uv.append(at)
			mask.append(Vector2(1 if exterior else 0,0))
		arrays[Mesh.ARRAY_TEX_UV]=uv
		arrays[Mesh.ARRAY_TEX_UV2]=mask
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return result

func _surface(id: String,grid: Vector2,fallback: String) -> ShaderMaterial:
	if surfaces.has(id): return surfaces[id]
	var material: ShaderMaterial=Library.material(fallback).duplicate()
	if grid!=Vector2.ZERO:
		material.set_shader_parameter("art_projection_enabled",true)
		material.set_shader_parameter("art_texture",load(TEXTURES+id+".png"))
		material.set_shader_parameter("art_texel_grid",grid)
	surfaces[id]=material
	return material

## 对比只切颜色；不动几何、碰撞、分组和当前透视状态。
func set_art_enabled(value: bool) -> void:
	art_enabled=value
	for material in surfaces.values(): material.set_shader_parameter("art_gray_preview",not value)
	if is_instance_valid(roof) and roof.roof_material!=null: roof.roof_material.set_shader_parameter("art_gray_preview",not value)
