extends RefCounted
## 只记录命中物的相对变换；箭仍归投射物容器管理，场景重置无需遍历角色子树清理。
var target: WeakRef
var region := ""
var local_transform := Transform3D.IDENTITY
var persistent := false
var fade_after := -1.0

## 人物是无厚度纸片，胶囊外壳会让侧面箭尖悬空；视觉落点深入主体，命中记录仍保留原碰撞点。
static func body_point(origin: Vector3, point: Vector3) -> Vector3:
	var offset := Vector3(point.x-origin.x,0,point.z-origin.z).limit_length(0.06)
	return Vector3(origin.x,point.y,origin.z)+offset

func anchor(body: Node3D) -> Transform3D:
	if body.has_method("projectile_attachment_frame"): return body.projectile_attachment_frame(region)
	return body.global_transform

## 盾挡落点由角色提供；胶囊负责命中判定，盾牌表面负责视觉附着，两种几何不能混用。
func bind(projectile: Node3D, body: Node3D, hit_region: String, incoming: Vector3) -> void:
	target = weakref(body)
	region = hit_region
	persistent = body.has_method("projectile_anchor_alive")
	fade_after = float(body.projectile_attachment_duration()) if body.has_method("projectile_attachment_duration") else -1.0
	if body.has_method("projectile_attachment_point"):
		projectile.global_position = body.projectile_attachment_point(region,projectile.global_position,incoming)
	local_transform = anchor(body).affine_inverse() * projectile.global_transform

## 每次取角色当前的身体/盾朝向，不能只跟随不旋转的 CharacterBody3D 根节点。
func follow(projectile: Node3D) -> bool:
	var body = target.get_ref() if target != null else null
	if not is_instance_valid(body) or not body.is_inside_tree(): return false
	if persistent and not body.projectile_anchor_alive(): return false
	projectile.global_transform = anchor(body) * local_transform
	return true
