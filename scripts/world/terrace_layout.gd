extends RefCounted
## 粗格是地形制作数据，不是角色移动单位；每个 XZ 位置只保存一个行走面。
const CELL:=4.0
const STEP:=0.5
const BASE:=-0.02
const ORIGIN:=Vector2(8,-20)
const SIZE:=Vector2i(10,12)
const DIRS: Array[Vector2i]=[Vector2i(0,-1),Vector2i(1,0),Vector2i(0,1),Vector2i(-1,0)]
var cells: Dictionary={}
var seed_value:=0

## 0 是固定验收布局；其他种子只改变外围平台长度和位置，主通路与坑出口固定。
func build(seed: int=0) -> void:
	seed_value=seed
	cells.clear()
	for c in [Vector2i(3,4),Vector2i(4,4),Vector2i(3,5),Vector2i(4,5),Vector2i(5,5),Vector2i(3,6),Vector2i(4,6)]: put(c,2)
	put(Vector2i(4,4),4)
	put(Vector2i(4,5),2,2,Vector2i(0,-1))
	put(Vector2i(3,7),0,2,Vector2i(0,-1))
	put(Vector2i(1,2),2)
	put(Vector2i(1,3),1)
	put(Vector2i(6,2),2)
	put(Vector2i(7,2),2)
	for c in [Vector2i(6,7),Vector2i(7,7),Vector2i(6,8),Vector2i(7,8)]: put(c,-2)
	put(Vector2i(6,8),-2,2,Vector2i(0,1))
	if seed!=0:
		var rng:=RandomNumberGenerator.new()
		rng.seed=seed
		var length:=rng.randi_range(1,3)
		# 随机块限制在主路南侧；坡脚朝北接平地，不覆盖通往凹坑的道路。
		var column:=rng.randi_range(1,2)
		for x in length: put(Vector2i(column+x,10),2)
		put(Vector2i(column,9),0,2,Vector2i(0,1))
		if rng.randf()>.5: put(Vector2i(5,4),2)

func put(cell: Vector2i,height: int,rise: int=0,direction: Vector2i=Vector2i.ZERO) -> void:
	cells[cell]={"height":height,"rise":rise,"direction":direction}

## 坡道两端必须接同高平台；错误布局在生成前报告，避免画面连通而碰撞断路。
func validate() -> PackedStringArray:
	var errors:=PackedStringArray()
	for cell in cells:
		var item:=spec(cell)
		if not inside(cell): errors.append("格子超出范围: %s"%cell)
		if item.rise==0: continue
		if not item.direction in DIRS:
			errors.append("坡向无效: %s"%cell)
			continue
		var high:=spec(cell+item.direction)
		var low:=spec(cell-item.direction)
		if high.rise!=0 or high.height!=item.height+item.rise: errors.append("坡顶没有同高平台: %s"%cell)
		if low.rise!=0 or low.height!=item.height: errors.append("坡脚没有同高平台: %s"%cell)
	return errors

func inside(cell: Vector2i) -> bool: return cell.x>=0 and cell.y>=0 and cell.x<SIZE.x and cell.y<SIZE.y
func spec(cell: Vector2i) -> Dictionary: return cells.get(cell,{"height":0,"rise":0,"direction":Vector2i.ZERO})

## 平台只取一档高度；坡道只沿明确方向线性连接两档，不猜测半砖的用途。
func height_in(cell: Vector2i,uv: Vector2) -> float:
	var item:=spec(cell)
	var direction: Vector2i=item.direction
	var t:=0.0
	if direction.x!=0: t=uv.x if direction.x>0 else 1.0-uv.x
	elif direction.y!=0: t=uv.y if direction.y>0 else 1.0-uv.y
	return BASE+(float(item.height)+float(item.rise)*t)*STEP

func height_at(point: Vector2) -> float:
	var p: Vector2=(point-ORIGIN)/CELL
	var cell:=Vector2i(floori(p.x),floori(p.y))
	if not inside(cell): return BASE
	return height_in(cell,p-Vector2(cell))

func world(cell: Vector2i,uv: Vector2) -> Vector3:
	var p:=ORIGIN+(Vector2(cell)+uv)*CELL
	return Vector3(p.x,height_in(cell,uv),p.y)

## 沿外边界顺时针取端点；相邻格在同一世界端点采样，坡道侧面也按实际高差裁出。
func edge(cell: Vector2i,side: int) -> Array[Vector3]:
	var corners: Array[Vector2]=[Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1)]
	return [world(cell,corners[side]),world(cell,corners[(side+1)%4])]

func exposed_edges() -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for z in SIZE.y:
		for x in SIZE.x:
			var cell:=Vector2i(x,z)
			for side in 4:
				var ends:=edge(cell,side)
				var neighbor:=cell+DIRS[side]
				var a: Vector3=ends[0]
				var b: Vector3=ends[1]
				var start:=ORIGIN+Vector2(neighbor)*CELL
				var low_a:=height_in(neighbor,(Vector2(a.x,a.z)-start)/CELL)
				var low_b:=height_in(neighbor,(Vector2(b.x,b.z)-start)/CELL)
				var da:=a.y-low_a
				var db:=b.y-low_b
				if maxf(da,db)<.001: continue
				var bottom_a:=Vector3(a.x,low_a,a.z)
				var bottom_b:=Vector3(b.x,low_b,b.z)
				# 两条坡边交叉时只保留正高差的一段，避免重复侧壁和反向三角形。
				if minf(da,db)<0:
					var t:=da/(da-db)
					if da<0:
						a=a.lerp(b,t)
						bottom_a=bottom_a.lerp(bottom_b,t)
					else:
						b=a.lerp(b,t)
						bottom_b=bottom_a.lerp(bottom_b,t)
				result.append({"cell":cell,"side":side,"a":a,"b":b,"low_a":bottom_a,"low_b":bottom_b})
	return result

## 道路线段跟随已设计的入口与坡道；随机块另补自己的坡道入口。
func roads() -> Array[PackedVector2Array]:
	var paths: Array[PackedVector2Array]=[PackedVector2Array([Vector2(8,13),Vector2(16,13),Vector2(22,13),Vector2(22,6),Vector2(26,6),Vector2(26,-2)]),PackedVector2Array([Vector2(22,13),Vector2(28,18),Vector2(34,18),Vector2(34,10)])]
	for cell in cells:
		if cell.y==9 and spec(cell).rise>0:
			var center:=ORIGIN+(Vector2(cell)+Vector2(.5,.5))*CELL
			paths.append(PackedVector2Array([Vector2(center.x,13),Vector2(center.x,22)]))
	return paths
