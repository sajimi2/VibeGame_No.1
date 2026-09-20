extends Node
## 只管理普通环境遮挡：输入玩家和场景网格，输出局部淡化；屋顶/战斗/物理状态仍各自持有。
const Style=preload("res://scripts/presentation/occlusion_style.gd")
const Probe=preload("res://scripts/presentation/body_occlusion_probe.gd")
const SURFACE=preload("res://scripts/presentation/environment_surface.gdshader")
const STONE=preload("res://scripts/presentation/pixel_stone.gdshader")
@export_range(.5,1.0) var enter_ratio:=.90
@export_range(.1,1.0) var exit_ratio:=.80
var observer: CharacterBody3D
var camera: Camera3D
var ratio:=0.0
var reveal:=0.0
var engaged:=false
var hold:=0.0
var sample_clock:=0.0
var sample_count:=0
var sample_usec:=0
var enabled:=true
var probe:=Probe.new()
var meshes: Array[Dictionary]=[]
var materials: Dictionary={}
var sources: Dictionary={}
var material_groups: Dictionary={}
var groups: Dictionary={}
var shaders: Dictionary={}
var registered: Dictionary={}
var roofs: Array[Node]=[]

func _ready() -> void: process_physics_priority=21

## 静态地图完成后注册一次。只接管实心环境材质；平地、路面、屋顶、角色和阴影不参与比例。
## 后续动态生成环境构件可再次传入对应子树，不必扫描整个关卡。
func register_branch(node: Node) -> void:
	if _is_support(node): return
	if node.get_script()==preload("res://scripts/presentation/interior_roof.gd"):
		if not roofs.has(node): roofs.append(node)
		return
	if node is MeshInstance3D: _register_mesh(node)
	for child in node.get_children():
		if not child.has_meta("wall_shadow"): register_branch(child)

## 承托结构按用途显式标记并向下继承，不能用石材/木材或网格厚度猜地板与墙的区别。
## 即使动态构件只注册某个子节点，也不能绕过祖先的地形保护。
func _is_support(node: Node) -> bool:
	var current:=node
	while current!=null:
		if current.get_meta("occlusion_role","")=="support": return true
		current=current.get_parent()
	return false

## 一段实体墙及其压顶/窗框共用淡化状态；独立墙段绝不能因共用材质而连带消失。
## 没有物理实体的美术预制件按自身归组，散放网格则各自独立。
func _group_owner(mesh: MeshInstance3D) -> Node:
	var current: Node=mesh
	var piece: Node=mesh
	while current!=null:
		if current is CollisionObject3D: return current
		if current.get_script()==preload("res://scripts/presentation/architecture_piece.gd"): piece=current
		current=current.get_parent()
	return piece

func _register_mesh(mesh: MeshInstance3D) -> void:
	if registered.has(mesh.get_instance_id()) or mesh.mesh==null or mesh.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY: return
	# 尚未填充的特效 ArrayMesh 不是环境；无表面时不能产生三角面采样器。
	if mesh.mesh.get_surface_count()==0: return
	# 墙帽/横梁可能很薄，仍须和墙身一起淡化；地板保护改由明确的 support 用途负责。
	var bounds:=mesh.get_aabb()
	var originals: Array[Material]=[]
	for index in mesh.mesh.get_surface_count():
		var original:=mesh.get_active_material(index)
		if not original is ShaderMaterial or original.shader not in [SURFACE,STONE]: return
		if original.shader==SURFACE:
			var texture: Texture2D=original.get_shader_parameter("surface_texture")
			if texture!=null and texture.resource_path.get_file().get_basename() in ["grass","soil","path"]: return
		originals.append(original)
	registered[mesh.get_instance_id()]=true
	var group_id:=_group_owner(mesh).get_instance_id()
	if not groups.has(group_id): groups[group_id]={"hit":false,"hold":0.0,"weight":0.0}
	# 显示版使用透视变体，影子仍按完整原网格投射，圆孔不会在太阳阴影上跟着跑。
	var shadow:=MeshInstance3D.new()
	shadow.name="WallOcclusionShadow"
	shadow.set_meta("wall_shadow",true)
	shadow.mesh=mesh.mesh
	shadow.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	for index in originals.size(): shadow.set_surface_override_material(index,originals[index])
	if mesh.cast_shadow!=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF: mesh.add_child(shadow)
	else: shadow.free()
	mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var had_override:=mesh.material_override!=null
	mesh.material_override=null
	for index in originals.size():
		var original: ShaderMaterial=originals[index]
		var id:=str(group_id)+":"+str(original.get_instance_id())
		if not materials.has(id):
			var copy: ShaderMaterial=original.duplicate()
			var shader_id:=original.shader.get_instance_id()
			if not shaders.has(shader_id):
				var shader:=Shader.new()
				shader.code="#define WALL_REVEAL_PASS\n"+original.shader.code
				shaders[shader_id]=shader
			copy.shader=shaders[shader_id]
			materials[id]=copy
			sources[id]=original
			material_groups[id]=group_id
		if had_override: mesh.material_override=materials[id]
		else: mesh.set_surface_override_material(index,materials[id])
	meshes.append({"node":mesh,"group":group_id,"bounds":bounds,"triangles":mesh.mesh.generate_triangle_mesh()})

## 10Hz 采样原始三角面，不看已淡化的深度，避免透视开启后比例下降造成开关振荡。
## 采样的是当前身体轮廓并合并多个遮挡物；90% 为离散面积估计，不是单条胸口射线。
func measure() -> void:
	var started:=Time.get_ticks_usec()
	var points:=probe.points(observer.baked_visual,camera)
	sample_count=points.size()
	for group in groups.values(): group.hit=false
	var candidates: Array[Dictionary]=[]
	var center:=observer.global_position+Vector3.UP*.8
	var center_origin:=camera.project_ray_origin(camera.unproject_position(center))
	for entry in meshes:
		# 动态构件可能已经释放，先校验再赋给强类型变量，避免访问失效实例。
		if not is_instance_valid(entry.node): continue
		var mesh: MeshInstance3D=entry.node
		if not mesh.is_visible_in_tree(): continue
		var inverse:=mesh.global_transform.affine_inverse()
		# 保守扩大包围盒，只用于粗筛；最终每个身体采样点仍与真实三角面求交。
		if entry.bounds.grow(2.0).intersects_segment(inverse*center_origin,inverse*center)==null: continue
		candidates.append({"group":entry.group,"inverse":inverse,"triangles":entry.triangles})
	var blocked:=0
	for point in points:
		var origin:=camera.project_ray_origin(camera.unproject_position(point))
		var point_blocked:=false
		for entry in candidates:
			if not entry.triangles.intersect_segment(entry.inverse*origin,entry.inverse*(point+camera.global_basis.z*.025)).is_empty():
				point_blocked=true
				groups[entry.group].hit=true
				# 不在首个命中处退出：透开前墙后，后面仍挡住身体的第二段墙也需要淡化。
		if point_blocked: blocked+=1
	ratio=float(blocked)/maxi(1,sample_count)
	sample_usec=Time.get_ticks_usec()-started

func _physics_process(delta: float) -> void:
	if not is_instance_valid(observer) or camera==null: return
	sample_clock-=delta
	if sample_clock<=0:
		sample_clock=.1
		if enabled and observer.hp>0: measure()
		else:
			ratio=0
			for group in groups.values(): group.hit=false
		if not engaged and ratio>=enter_ratio: engaged=true
		elif engaged and ratio<minf(exit_ratio,enter_ratio): engaged=false
	if engaged: hold=.16
	else: hold=maxf(0,hold-delta)
	reveal=move_toward(reveal,1.0 if enabled and observer.hp>0 and (engaged or hold>0) else 0.0,delta/Style.FADE_SECONDS)
	# 触发比例决定是否开圆，命中集合决定哪些构件能开；退出有缓冲，避免动作采样边缘闪烁。
	for group in groups.values():
		if group.hit: group.hold=.16
		else: group.hold=maxf(0,group.hold-delta)
		group.weight=move_toward(group.weight,1.0 if group.hit or group.hold>0 else 0.0,delta/Style.FADE_SECONDS)
	_publish()

## 每帧仅刷新少量材质参数。若同处一个屋顶圆下，直接沿用该屋顶的半径、柔边与淡化数值。
func _publish() -> void:
	var radius:=Style.RADIUS
	var feather:=Style.FEATHER
	var coverage:=Style.FADED_COVERAGE
	for roof in roofs:
		if is_instance_valid(roof) and (roof.blocked or roof.inside):
			radius=roof.reveal_radius
			feather=roof.feather_width
			coverage=roof.indoor_opacity
			break
	var height:=.9 if observer.crouched else 1.6
	var target:=observer.global_position+Vector3.UP*(height*.48)
	var viewport:=get_viewport().get_visible_rect().size
	for id in materials:
		var material: ShaderMaterial=materials[id]
		# B 明暗对比仍由原环境库控制；透视显示副本只镜像这个状态，不接管它。
		if sources[id].shader==SURFACE:
			material.set_shader_parameter("banded",sources[id].get_shader_parameter("banded"))
			# 实验的灰模/美术对比只换颜色，不重建碰撞或丢失已注册的透视分组。
			material.set_shader_parameter("art_gray_preview",sources[id].get_shader_parameter("art_gray_preview"))
			material.set_shader_parameter("art_projection_enabled",sources[id].get_shader_parameter("art_projection_enabled"))
		var strength: float=reveal*groups[material_groups[id]].weight
		material.set_shader_parameter("wall_reveal",strength)
		# 分组后材质数量增加；未参与透视的构件不必每帧更新圆心等十余个参数。
		if strength<=0: continue
		material.set_shader_parameter("wall_coverage",coverage)
		material.set_shader_parameter("wall_center",camera.unproject_position(target)/viewport)
		material.set_shader_parameter("wall_viewport",viewport)
		material.set_shader_parameter("wall_radius",radius*viewport.y/camera.size)
		material.set_shader_parameter("wall_feather",feather*viewport.y/camera.size)
		material.set_shader_parameter("wall_clear_core",Style.CLEAR_CORE_FRACTION)
		material.set_shader_parameter("wall_dither_origin",camera.unproject_position(Vector3.ZERO).round())
		material.set_shader_parameter("wall_target",target)
		material.set_shader_parameter("wall_to_camera",camera.global_basis.z)
