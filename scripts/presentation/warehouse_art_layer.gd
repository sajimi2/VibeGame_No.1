extends Node3D
## 样板区的美术装配：配置指出要替换的显示网格；不新增关卡职责，不移动或替换既有碰撞。
const ASSET="res://assets/environment/warehouse_slice/"
var enabled:=true
var materials: Array[ShaderMaterial]=[]
var old_details: Array[Node3D]=[]
var new_details: Array[Node3D]=[]
var projections: Dictionary={}
var bindings: Array[Dictionary]=[]
var asset_origin:=Vector3.ZERO
var projection_space:=Transform3D.IDENTITY
var region:=Vector4.ZERO

func setup(level: Node3D) -> void:
	var manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(ASSET+"bindings.json"))
	asset_origin=Vector3(manifest.origin[0],manifest.origin[1],manifest.origin[2])
	projection_space=(level.global_transform*Transform3D(Basis.IDENTITY,asset_origin)).affine_inverse()
	region=Vector4(manifest.region[0],manifest.region[1],manifest.region[2],manifest.region[3])
	for spec in manifest.get("props",[]):
		var prop: Node3D=load(ASSET+"props/"+spec.kind+".tscn").instantiate()
		prop.name=spec.name
		prop.position=asset_origin+Vector3(spec.position[0],spec.position[1],spec.position[2])
		add_child(prop)
		for mesh in prop.find_children("*","MeshInstance3D",true,false):
			if not str(mesh.name).contains("Hoop"): apply(mesh,"planks")
	for spec in manifest.meshes:
		var target: Node=level.get_node(NodePath(spec.path))
		if target is MeshInstance3D: apply(target,spec.projection,spec.get("region",false))
		else:
			for mesh in target.find_children("*","MeshInstance3D",true,false):
				if not mesh.has_meta("wall_shadow"): apply(mesh,spec.projection,spec.get("region",false))
		if spec.has("hide"):
			old_details.append(level.get_node(NodePath(spec.hide)))
	# 屋顶控制器已经就绪，向它现有的材质写表面参数，保留室内/圆孔状态与阴影代理。
	var roof: Node3D=level.get_node("Roofs/WarehouseRoof")
	var roof_projection: Resource=projection("roof")
	roof_projection.configure(roof.roof_material)
	materials.append(roof.roof_material)
	for mesh in roof.pieces:
		mesh.mesh=roof_projection.project(mesh.mesh,projection_space*mesh.global_transform)
	# 裸露墙端只补简单木包边，沿父墙一起透视；纹理负责细节，不重建密集梁架。
	for id in ["WarehouseEast","WarehouseWestSouth"]:
		var body: Node3D=level.get_node("Architecture/"+id)
		var post:=MeshInstance3D.new()
		post.name="GeneratedEndPost"
		var box:=BoxMesh.new()
		box.size=Vector3(.66,3.62,.1)
		post.mesh=box
		post.material_override=preload("res://scripts/presentation/environment_library.gd").material("timber")
		body.add_child(post)
		post.global_position=level.to_global(Vector3(body.position.x,3.6,-3.96))
		new_details.append(post)
	set_enabled(true)

func projection(id: String) -> Resource:
	if not projections.has(id): projections[id]=load(ASSET+"projections/"+id+".tres")
	return projections[id]

func apply(mesh: MeshInstance3D,id: String,limited:=false) -> void:
	var config: Resource=projection(id)
	var original: ShaderMaterial=mesh.get_active_material(0)
	var material: ShaderMaterial=config.make_material(original)
	if limited:
		material.set_shader_parameter("art_region_enabled",true)
		material.set_shader_parameter("art_region",region)
	var source:=mesh.mesh
	mesh.mesh=config.project(source,projection_space*mesh.global_transform)
	mesh.material_override=material
	materials.append(material)
	bindings.append({"mesh":mesh,"source":source,"material":material,"projection":id})

## 比较只切新贴图与旧装饰的显示；几何位置、碰撞与遮挡组注册保持不变。
func set_enabled(value: bool) -> void:
	enabled=value
	for material in materials: material.set_shader_parameter("art_projection_enabled",value)
	for detail in old_details: detail.visible=not value
	for detail in new_details: detail.visible=value
