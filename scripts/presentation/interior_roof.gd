@tool
extends Node3D
## 室外按真实视线开透视圆；室内叠加整组低不透明度，两个渐变通道互不替代。
@export var interior:=AABB(Vector3(-3,-.25,-3),Vector3(6,4.5,6))
const Style=preload("res://scripts/presentation/occlusion_style.gd")
@export var fade_seconds:=Style.FADE_SECONDS
@export var can_enter:=true
@export var reveal_radius:=Style.RADIUS
@export var feather_width:=Style.FEATHER
@export_range(0.05,0.5) var indoor_opacity:=Style.FADED_COVERAGE
var observer: Node3D
var inside:=false
var blocked:=false
var reveal:=0.0
var hold_time:=0.0
var interior_fade:=0.0
var interior_hold:=0.0
var roof_material: ShaderMaterial
var pieces: Array[MeshInstance3D]=[]
func _ready() -> void:
	process_physics_priority=20
	roof_material=ShaderMaterial.new()
	roof_material.shader=preload("res://scripts/presentation/interior_roof.gdshader")
	roof_material.set_shader_parameter("surface_texture",load("res://assets/environment/textures/roof.png"))
	for child in get_children():
		if child is MeshInstance3D and child.mesh!=null:
			pieces.append(child)
			child.material_override=roof_material
			# 阴影代理不执行屏幕空间开洞，避免人物移动时屋子的太阳阴影跟着变化。
			child.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var shadow:=MeshInstance3D.new()
			shadow.mesh=child.mesh
			shadow.transform=child.transform
			shadow.material_override=preload("res://scripts/presentation/environment_library.gd").material("roof")
			shadow.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			add_child(shadow)

## 只有可进入的室内触发整组淡化；局部透视独立检查视线，仍覆盖屋檐外和不可进入的塔顶。
func contains_observer(point: Vector3) -> bool:
	return can_enter and interior.has_point(to_local(point))

## 当前坡屋面是薄盒，转换到网格局部即精确 OBB；不增加移动或阻弹碰撞体。
func blocks_point(point: Vector3,camera: Camera3D) -> bool:
	var origin:=camera.project_ray_origin(camera.unproject_position(point))
	for piece in pieces:
		if not piece.visible: continue
		var inverse:=piece.global_transform.affine_inverse()
		if piece.mesh.get_aabb().intersects_segment(inverse*origin,inverse*point)!=null: return true
	return false
func _physics_process(delta: float) -> void:
	if not is_instance_valid(observer): return
	var camera: Camera3D=observer.camera
	if camera==null: return
	inside=contains_observer(observer.global_position)
	# 进门淡化整组屋面，短暂离开缓冲防止门槛往返抖动；屋外不会误触发整顶半透明。
	if inside: interior_hold=.13
	else: interior_hold=maxf(0,interior_hold-delta)
	interior_fade=move_toward(interior_fade,1.0 if inside or interior_hold>0 else 0.0,delta/maxf(.01,fade_seconds))
	blocked=false
	var crouched: bool=observer.get("crouched")==true
	var height:=.9 if crouched else 1.6
	# 脚、胸、头分别探测，中心射线偶尔露出不会使屋檐效果闪烁。
	for h in [.15,height*.55,height]:
		if blocks_point(observer.global_position+Vector3.UP*h,camera): blocked=true; break
	if blocked: hold_time=.13
	else: hold_time=maxf(0,hold_time-delta)
	reveal=move_toward(reveal,1.0 if blocked or hold_time>0 else 0.0,delta/maxf(.01,fade_seconds))
	var target:=observer.global_position+Vector3.UP*(height*.48)
	var viewport_size:=get_viewport().get_visible_rect().size
	var center:=camera.unproject_position(target)/viewport_size
	var pixels_per_meter:=viewport_size.y/camera.size
	roof_material.set_shader_parameter("reveal",reveal)
	roof_material.set_shader_parameter("roof_opacity",lerpf(1.0,indoor_opacity,interior_fade))
	# 覆盖率图案锚在世界投影，避免镜头移动时整片低透明屋顶的网点爬动。
	roof_material.set_shader_parameter("dither_origin",camera.unproject_position(Vector3.ZERO).round())
	roof_material.set_shader_parameter("reveal_center",center)
	roof_material.set_shader_parameter("reveal_radius",reveal_radius*pixels_per_meter)
	roof_material.set_shader_parameter("feather_width",feather_width*pixels_per_meter)
	roof_material.set_shader_parameter("viewport_size",viewport_size)
	roof_material.set_shader_parameter("reveal_target",target)
	roof_material.set_shader_parameter("view_to_camera",camera.global_basis.z)
