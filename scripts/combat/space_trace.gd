extends RefCounted
## 近战与箭共用线段检测，覆盖整段轨迹，避免只检查终点造成穿透。

## 沿有限线段查找第一个不可穿透目标，同时收集沿途布帘；不在此函数中扣血。
static func trace(world: World3D, start: Vector3, finish: Vector3, excluded: Array[RID] = [], mask: int = 8 | 16) -> Dictionary:
	var skip: Array[RID] = excluded.duplicate()
	var penetrated: Array = []
	for i in 16:
		var query := PhysicsRayQueryParameters3D.create(start, finish, mask, skip)
		query.hit_from_inside = true
		var hit := world.direct_space_state.intersect_ray(query)
		if hit.is_empty(): return {"penetrated": penetrated}
		var body: Object = hit.collider
		if body.get_meta("penetrable", false):
			penetrated.append(body)
			skip.append(body.get_rid())
			continue
		hit["penetrated"] = penetrated
		return hit
	return {"penetrated": penetrated, "blocked": true}

## 累计布帘受击次数；第三次命中后撤掉碰撞并压低外观，表现破损落地。
static func apply_cloth(body: CollisionObject3D) -> void:
	if not is_instance_valid(body) or body.collision_layer == 0: return
	var hits := int(body.get_meta("hits", 0)) + 1
	body.set_meta("hits", hits)
	var visual := body.get_child(1) as MeshInstance3D
	visual.transparency = minf(0.55, hits * 0.18)
	if hits >= 3:
		body.collision_layer = 0
		visual.position.y = -body.position.y + 0.08
		visual.scale.y = 0.07
		visual.transparency = 0

## 按起终点和固定初速解算低弧弹道；无有效解或水平距离过小时退回直射方向。
static func launch_velocity(start: Vector3, target: Vector3, speed: float = 18.0) -> Vector3:
	var offset := target - start
	var horizontal := Vector3(offset.x, 0, offset.z)
	var distance := horizontal.length()
	if distance < 0.05: return offset.normalized() * speed
	var v2 := speed * speed
	var discriminant := v2 * v2 - 9.8 * (9.8 * distance * distance + 2 * offset.y * v2)
	if discriminant < 0: return offset.normalized() * speed
	var angle := atan((v2 - sqrt(discriminant)) / (9.8 * distance))
	return horizontal.normalized() * cos(angle) * speed + Vector3.UP * sin(angle) * speed
