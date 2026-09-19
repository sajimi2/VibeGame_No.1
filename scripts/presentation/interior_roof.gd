extends Node3D
## 独立屋顶表现：关卡注入观察角色，以建筑局部室内范围判断淡出；不参与寻路、任务或碰撞。
@export var interior := AABB(Vector3(-3,-0.25,-3),Vector3(6,4.5,6))
@export var fade_seconds := 0.4
@export var exit_margin := 0.22
@export var can_enter := true
var observer: Node3D
var inside := false
var opacity := 1.0
var roof_material: ShaderMaterial

func _ready() -> void:
	process_physics_priority = 20
	roof_material = ShaderMaterial.new()
	roof_material.shader = preload("res://scripts/presentation/interior_roof.gdshader")
	for child in get_children():
		if child is MeshInstance3D: child.material_override=roof_material

## 门边保留小范围滞回，避免站在边缘或移动浮点抖动让屋顶反复闪烁；高度范围排除高台下的人。
func contains_observer(point: Vector3) -> bool:
	var bounds := interior
	if inside:
		bounds.position.x -= exit_margin
		bounds.position.z -= exit_margin
		bounds.size.x += exit_margin*2
		bounds.size.z += exit_margin*2
	return can_enter and bounds.has_point(to_local(point))

func _physics_process(delta: float) -> void:
	if not is_instance_valid(observer): return
	inside = contains_observer(observer.global_position)
	opacity = move_toward(opacity,0.0 if inside else 1.0,delta/maxf(fade_seconds,0.01))
	roof_material.set_shader_parameter("opacity",opacity)
	visible = opacity>0.001
