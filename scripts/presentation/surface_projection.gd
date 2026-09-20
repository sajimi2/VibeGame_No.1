extends Resource
## 表面图片的资产配置：输入图片、局部投影轴和面朝向，输出 UV 网格/材质；不创建碰撞或透视状态。
@export var texture: Texture2D
@export var fallback: String="plaster"
@export var texel_grid:=Vector2(160,128)
@export var tint:=Color.WHITE
@export var unmapped_color:=Color.TRANSPARENT
@export_range(0,0.3) var edge_blend:=0.0
@export var origin:=Vector3.ZERO
@export var u_axis:=Vector3.RIGHT
@export var v_axis:=Vector3.DOWN
@export var absolute_u:=false
@export var absolute_v:=false
@export var face_normal:=Vector3.ZERO
@export var outward:=false
@export var repeat_uv:=false
@export_enum("planar", "box") var mapping: String="planar"
@export var tile_size:=Vector2(4,4)

## pose 将网格坐标变到资产坐标。多块墙可使用同一份配置，让图案跨几何接缝连续。
func project(source: Mesh,pose:=Transform3D.IDENTITY) -> ArrayMesh:
	var result:=ArrayMesh.new()
	var normal_basis:=pose.basis.inverse().transposed()
	for index in source.get_surface_count():
		var arrays:=source.surface_get_arrays(index).duplicate(true)
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
		var uv:=PackedVector2Array()
		var mask:=PackedVector2Array()
		var edges:=PackedColorArray()
		var original_uv: PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV]!=null else PackedVector2Array()
		for i in vertices.size():
			var p: Vector3=pose*vertices[i]-origin
			var n: Vector3=(normal_basis*normals[i]).normalized()
			var u:=p.dot(u_axis)
			var v:=p.dot(v_axis)
			if absolute_u: u=absf(u)
			if absolute_v: v=absf(v)
			if mapping=="box":
				var axis:=n.abs()
				var plane:=Vector2(p.x,p.z) if axis.y>maxf(axis.x,axis.z) else Vector2(p.z,-p.y) if axis.x>axis.z else Vector2(p.x,-p.y)
				u=plane.x/tile_size.x
				v=plane.y/tile_size.y
			var direction:=face_normal
			if outward: direction*=signf(p.dot(face_normal))
			var exterior:=face_normal==Vector3.ZERO or n.dot(direction)>.7
			uv.append(Vector2(u,v))
			mask.append(Vector2(1 if exterior else 0,0))
			var edge:=original_uv[i] if original_uv.size()==vertices.size() else Vector2(.5,.5)
			edges.append(Color(edge.x,edge.y,1,1))
		arrays[Mesh.ARRAY_TEX_UV]=uv
		arrays[Mesh.ARRAY_TEX_UV2]=mask
		# 保留原始边缘坐标供土路柔边使用；投影 UV 可以重复，不能再拿它判断网格边缘。
		arrays[Mesh.ARRAY_COLOR]=edges
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return result

func configure(material: ShaderMaterial) -> void:
	material.set_shader_parameter("art_projection_enabled",texture!=null)
	material.set_shader_parameter("art_texture",texture)
	material.set_shader_parameter("art_texel_grid",texel_grid)
	material.set_shader_parameter("art_tint",tint)
	material.set_shader_parameter("art_unmapped_color",unmapped_color)
	material.set_shader_parameter("art_edge_blend",edge_blend)
	material.set_shader_parameter("art_repeat",repeat_uv)
	material.set_shader_parameter("art_uv_present",true)

func make_material(base: ShaderMaterial=null) -> ShaderMaterial:
	var result: ShaderMaterial=(base if base!=null else preload("res://scripts/presentation/environment_library.gd").material(fallback)).duplicate()
	configure(result)
	return result
