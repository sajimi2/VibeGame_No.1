@tool
extends "res://scripts/art/humanoid_rig.gd"
## Blender/glTF 源资产适配器：读取标准骨架、蒙皮和材质；只用于工作台与离线烘焙。
var pieces: Array[MeshInstance3D]=[]
var surfaces: Array[Dictionary]=[]

func build() -> void:
	if is_instance_valid(rig_skeleton): return
	rig_skeleton=find_children("*","Skeleton3D",true,false)[0]
	animator=find_children("*","AnimationPlayer",true,false)[0]
	for index in rig_skeleton.get_bone_count():
		var id:=str(rig_skeleton.get_bone_name(index))
		bones.append({"part":"lower" if id=="Pelvis" or id.begins_with("Thigh") or id.begins_with("Shin") or id.begins_with("Foot") else "upper"})
	for item in find_children("*","MeshInstance3D",true,false):
		if item.mesh!=null:
			item.set_meta("art_part",item.get_meta("extras",{}).get("art_part",""))
			pieces.append(item)
			for surface in item.mesh.get_surface_count():
				var material:=item.get_active_material(surface) as StandardMaterial3D
				surfaces.append({"piece":item,"arrays":item.mesh.surface_get_arrays(surface),"color":material.albedo_color if material!=null else Color.WHITE})

func _sync() -> void:
	rig_skeleton.force_update_all_bone_transforms()

## 离线按 Skin 的逆绑定矩阵求蒙皮，避免 GPU 延迟一帧导致整批采到旧姿态；游戏不调用。
func geometry(part: String, offset:=Vector3.ZERO) -> Array:
	var result: Array=[]
	for surface in surfaces:
		var piece: MeshInstance3D=surface.piece
		if part!="all" and piece.get_meta("art_part","")!=part: continue
		var arrays: Array=surface.arrays
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX].duplicate()
		var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL].duplicate()
		var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
		var local:=global_transform.affine_inverse()*piece.global_transform
		if piece.skin!=null:
			local=global_transform.affine_inverse()*rig_skeleton.global_transform
			var bind_ids: PackedInt32Array=arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array=arrays[Mesh.ARRAY_WEIGHTS]
			var stride:=weights.size()/vertices.size()
			var transforms: Array[Transform3D]=[]
			for bind in piece.skin.get_bind_count():
				var bone:=rig_skeleton.find_bone(piece.skin.get_bind_name(bind))
				if bone<0: bone=piece.skin.get_bind_bone(bind)
				assert(bone>=0,"蒙皮引用了不存在的骨骼")
				transforms.append(rig_skeleton.get_bone_global_pose(bone)*piece.skin.get_bind_pose(bind))
			for index in vertices.size():
				var point:=Vector3.ZERO
				var normal:=Vector3.ZERO
				for influence in stride:
					var at:=index*stride+influence
					if weights[at]<=0: continue
					var transform:=transforms[bind_ids[at]]
					point+=(transform*vertices[index])*weights[at]
					normal+=(transform.basis*normals[index])*weights[at]
				vertices[index]=point
				normals[index]=normal.normalized()
		var count:=indices.size() if not indices.is_empty() else vertices.size()
		for face in range(0,count,3):
			var a:=indices[face] if not indices.is_empty() else face
			var b:=indices[face+1] if not indices.is_empty() else face+1
			var c:=indices[face+2] if not indices.is_empty() else face+2
			# 凹胸腔/眼眶按实际法线判断面绕序，不能用凸体中心猜外侧。
			if (vertices[b]-vertices[a]).cross(vertices[c]-vertices[a]).dot(normals[a])<0:
				var swap:=b; b=c; c=swap
			result.append({"points":[local*vertices[a]-offset,local*vertices[b]-offset,local*vertices[c]-offset],"color":surface.color})
	return result

func set_preview_part(part: String) -> void:
	for piece in pieces: piece.visible=part=="full" or piece.get_meta("art_part","")==part
