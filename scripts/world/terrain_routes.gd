extends Node
## 每个 X/Z 网格只记录一个行走表面，不支持桥上桥下的多层路径。
## 用实际碰撞检测高度、净空和连通性，避免路径跨墙。
const CELL := 0.6
## 地形层与巨石移动代理层必须和角色一致；不采样只用于箭矢/视线的凹凸石面。
const MOVEMENT_MASK := 1 | 32
var graph := AStar3D.new()
var cells: Dictionary = {}
var world: World3D

## 按网格射线采样地面，筛除陡面和净空不足处，再把可步行的邻点连接成 A* 图。
func build(source: World3D, bounds: Rect2 = Rect2(-15,-15.6,30,31.2)) -> void:
	graph.clear()
	cells.clear()
	world = source
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.6
	var clearance := PhysicsShapeQueryParameters3D.new()
	clearance.shape = capsule
	clearance.collision_mask = MOVEMENT_MASK
	for z in range(roundi(bounds.position.y/CELL),roundi(bounds.end.y/CELL)+1):
		for x in range(roundi(bounds.position.x/CELL),roundi(bounds.end.x/CELL)+1):
			var ray := PhysicsRayQueryParameters3D.create(Vector3(x*CELL,8,z*CELL),Vector3(x*CELL,-2,z*CELL),MOVEMENT_MASK)
			var hit := world.direct_space_state.intersect_ray(ray)
			if hit.is_empty() or hit.normal.y<0.75: continue
			var point: Vector3 = hit.position
			clearance.transform = Transform3D(Basis.IDENTITY,point+Vector3.UP*0.89)
			if not world.direct_space_state.intersect_shape(clearance,1).is_empty(): continue
			var id := graph.get_available_point_id()
			graph.add_point(id,point)
			cells[Vector2i(x,z)] = id
	for cell in cells:
		for offset in [Vector2i(1,0),Vector2i(0,1),Vector2i(1,1),Vector2i(-1,1)]:
			var neighbor: Vector2i = cell+offset
			if not cells.has(neighbor): continue
			var a: Vector3 = graph.get_point_position(cells[cell])
			var b: Vector3 = graph.get_point_position(cells[neighbor])
			if traversable(a,b): graph.connect_points(cells[cell],cells[neighbor])

## 验证两点之间的高差、角色宽度和连续支撑面，防止路线穿墙或切入坡道侧面。
func traversable(a: Vector3, b: Vector3, excluded: Array[RID] = []) -> bool:
	if absf(a.y-b.y)>0.43: return false
	var distance := Vector2(a.x-b.x,a.z-b.z).length()
	if distance>0.01 and absf(a.y-b.y)/distance>0.75: return false
	var side := (b-a).cross(Vector3.UP).normalized()*0.31
	for shift in [Vector3.ZERO,side,-side]:
		var ray := PhysicsRayQueryParameters3D.create(a+shift+Vector3.UP*0.30,b+shift+Vector3.UP*0.30,MOVEMENT_MASK,excluded)
		if not world.direct_space_state.intersect_ray(ray).is_empty(): return false
	# 贴地射线配合支撑面采样，区分连续坡面与竖直台阶，避免路线切过坡道侧壁。
	var foot := PhysicsRayQueryParameters3D.create(a+Vector3.UP*0.01,b+Vector3.UP*0.01,MOVEMENT_MASK,excluded)
	var foot_hit := world.direct_space_state.intersect_ray(foot)
	if not foot_hit.is_empty() and foot_hit.normal.y<0.75: return false
	var steps := maxi(2,ceili(distance/0.035))
	var support := PhysicsRayQueryParameters3D.create(a+Vector3.UP*0.2,a-Vector3.UP*0.2,MOVEMENT_MASK,excluded)
	var initial := world.direct_space_state.intersect_ray(support)
	if initial.is_empty(): return false
	var previous: float = initial.position.y
	for i in range(1,steps+1):
		var p := a.lerp(b,float(i)/steps)
		var ray := PhysicsRayQueryParameters3D.create(p+Vector3.UP*0.6,p-Vector3.UP*0.6,MOVEMENT_MASK,excluded)
		var hit := world.direct_space_state.intersect_ray(ray)
		if hit.is_empty() or hit.normal.y<0.75: return false
		# 逐段检查支撑面的局部坡度，允许平地与坡道转折，不假定整段是同一斜面。
		if absf(hit.position.y-previous)>distance/steps*0.8+0.002: return false
		previous=hit.position.y
	return true

## 在角色附近寻找可直接走到的导航点；找不到时返回 -1。
func entry_point(point: Vector3, excluded: Array[RID]) -> int:
	var best := -1
	var distance := 2.4
	for id in graph.get_point_ids():
		var candidate := graph.get_point_position(id)
		var d := point.distance_to(candidate)
		if d<distance and traversable(point,candidate,excluded):
			best=id
			distance=d
	return best

## 把起终点映射到导航图并返回路径；无法接入图时返回空数组。
func path(from: Vector3, to: Vector3, excluded: Array[RID] = []) -> PackedVector3Array:
	if graph.get_point_count()==0: return PackedVector3Array()
	var start := entry_point(from,excluded)
	var end := graph.get_closest_point(to)
	if start<0: return PackedVector3Array()
	return graph.get_point_path(start,end)
