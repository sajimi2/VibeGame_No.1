extends RefCounted
## 近战专用空间查询：允许刀刃扫过多个身体，实体墙仍截断；不改变箭矢的首个命中规则。
const Trace = preload("res://scripts/combat/space_trace.gd")

## 每条扫描线依距离收集目标；只穿过敌人和原有布帘，石材/墙/训练靶会终止扫描。
static func sweep(world: World3D, start: Vector3, finish: Vector3, attacker: RID) -> Dictionary:
	var excluded: Array[RID]=[attacker]
	var hits: Array[Dictionary]=[]
	var cloths: Array=[]
	for i in 16:
		var hit := Trace.trace(world,start,finish,excluded,1|8|16)
		for cloth in hit.get("penetrated",[]):
			if not excluded.has(cloth.get_rid()):
				excluded.append(cloth.get_rid())
				cloths.append(cloth)
		if not hit.has("collider"): break
		var body: Node=hit.collider
		hits.append(hit)
		if not body.is_in_group("tactical_enemies"): break
		excluded.append(body.get_rid())
	return {"hits":hits,"cloths":cloths}

## 地面和遮挡查询忽略演员，避免刀尖正下方的敌人把地面误报成胶囊顶部。
static func actor_exclusions(actor: CollisionObject3D) -> Array[RID]:
	var result: Array[RID]=[actor.get_rid()]
	for enemy in actor.get_tree().get_nodes_in_group("tactical_enemies"):
		result.append(enemy.get_rid())
	return result

## 落点附近按距离排序；脚底高度及两段视线同时检查，不能穿墙或跨楼层扩散。
static func impact(actor: CharacterBody3D, center: Vector3, radius: float, height_tolerance: float) -> Array[Dictionary]:
	var space := actor.get_world_3d().direct_space_state
	var excluded := actor_exclusions(actor)
	var candidates: Array[Node3D]=[]
	for enemy in actor.get_tree().get_nodes_in_group("tactical_enemies"):
		if enemy.hp<=0 or absf(enemy.global_position.y-center.y)>height_tolerance: continue
		var offset: Vector3=enemy.global_position-center
		if Vector2(offset.x,offset.z).length()>radius: continue
		candidates.append(enemy)
	candidates.sort_custom(func(a,b):return a.global_position.distance_squared_to(center)<b.global_position.distance_squared_to(center))
	var hits: Array[Dictionary]=[]
	for enemy in candidates:
		var chest: Vector3=enemy.global_position+Vector3.UP*.8
		var ray := PhysicsRayQueryParameters3D.create(actor.global_position+Vector3.UP*.8,chest,1|8|32,excluded)
		if not space.intersect_ray(ray).is_empty(): continue
		ray.from=center+Vector3.UP*.25
		ray.to=enemy.global_position+Vector3.UP*.25
		if not space.intersect_ray(ray).is_empty(): continue
		var incoming := (enemy.global_position-actor.global_position)*Vector3(1,0,1)
		hits.append({"collider":enemy,"position":chest,"normal":-incoming.normalized(),"incoming":incoming.normalized()})
	return hits
