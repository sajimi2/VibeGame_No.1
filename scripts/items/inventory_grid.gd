class_name InventoryGrid
extends RefCounted
## 纯排布规则：输入网格尺寸、已占矩形和候选矩形，返回是否可放；不持有物品。
static func fits(columns: int, rows: int, cell: Vector2i, footprint: Vector2i, occupied: Array[Rect2i]) -> bool:
	if cell.x < 0 or cell.y < 0 or footprint.x < 1 or footprint.y < 1: return false
	if cell.x + footprint.x > columns or cell.y + footprint.y > rows: return false
	var area := Rect2i(cell, footprint)
	for other in occupied:
		if area.intersects(other): return false
	return true

static func first_fit(columns: int, rows: int, footprint: Vector2i, occupied: Array[Rect2i]) -> Vector2i:
	for y in rows:
		for x in columns:
			if fits(columns, rows, Vector2i(x,y), footprint, occupied): return Vector2i(x,y)
	return Vector2i(-1,-1)
