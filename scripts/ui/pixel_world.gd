extends Node2D
## All blocked surfaces are drawn from existing collision rectangles.
var region := "village"
var obstacles: Array[Dictionary] = []

func setup(level: Node2D) -> void:
	region = String(level.level_id)
	z_index = -5
	for name in ["Floor", "Ground"]:
		var old := level.get_node_or_null(name) as CanvasItem
		if old != null: old.hide()
	_collect(level)
	queue_redraw()

func _collect(node: Node) -> void:
	if node is StaticBody2D:
		var shape := node.get_node_or_null("Shape") as CollisionShape2D
		if shape != null and shape.shape is RectangleShape2D:
			var size: Vector2 = shape.shape.size
			obstacles.append({"name": String(node.name), "rect": Rect2(shape.global_position - size / 2, size)})
			for child in node.get_children():
				if child is Polygon2D: child.hide()
	for child in node.get_children(): _collect(child)

func _draw() -> void:
	var inside := region.begins_with("outpost")
	var forest := region == "forest"
	var ground := Color("303c32") if forest else Color("56583d")
	if inside: ground = Color("343d46")
	draw_rect(Rect2(0, 0, 960, 540), ground)
	var rng := RandomNumberGenerator.new()
	rng.seed = 6719
	for y in range(0, 540, 32):
		for x in range(0, 960, 32):
			var at := Vector2(x, y)
			var tint := ground.lightened(rng.randf_range(0.01, 0.09))
			if inside:
				draw_rect(Rect2(at + Vector2.ONE, Vector2(30, 30)), tint)
				draw_line(at + Vector2(2, 2), at + Vector2(29, 2), tint.lightened(0.07))
				if rng.randf() < 0.2: draw_line(at + Vector2(5, 8), at + Vector2(12, 13), ground.darkened(0.12))
			else:
				var path := absf(y - 256) < (32 if forest else 48)
				if path:
					tint = Color("665c45") if forest else Color("8a7853")
					draw_rect(Rect2(at, Vector2(32, 32)), tint.darkened(rng.randf_range(0, 0.08)))
				for i in 6:
					var point := at + Vector2(rng.randi_range(2, 28), rng.randi_range(2, 28))
					draw_rect(Rect2(point, Vector2(2, 1 if path else 3)), tint.lightened(0.14))
	for obstacle in obstacles:
		var rect: Rect2 = obstacle.rect
		var name: String = obstacle.name
		draw_rect(Rect2(rect.position + Vector2(3, 5), rect.size), Color(0.04, 0.06, 0.06, 0.5))
		if name.begins_with("House"):
			_house(rect)
		elif name.begins_with("Tree"):
			_tree(rect)
		elif name == "Pool":
			draw_rect(rect, Color("526853"))
			draw_rect(rect.grow(-3), Color("2a5056"))
			for i in 30:
				var p := rect.position + Vector2(rng.randf_range(5, rect.size.x - 12), rng.randf_range(5, rect.size.y - 5))
				draw_line(p, p + Vector2(7, 0), Color("5d8584"))
		else:
			_stone(rect, Color("626d72") if inside else Color("737767"))
			if name == "Well":
				draw_rect(rect.grow(-8), Color("202e33"))
				draw_rect(rect.grow(-11), Color("3c6064"))
	# Edge torches are decorative and do not add collision.
	if inside:
		for x in [110, 360, 630, 850]:
			draw_rect(Rect2(x, 30, 5, 12), Color("6e553d"))
			draw_rect(Rect2(x - 2, 27, 9, 7), Color("d68b45"))
			draw_rect(Rect2(x, 27, 4, 4), Color("ffe0a0"))

func _stone(rect: Rect2, color: Color) -> void:
	draw_rect(rect, color.darkened(0.4))
	for y in range(0, int(rect.size.y), 12):
		for x in range(0, int(rect.size.x), 24):
			var cell := Rect2(rect.position + Vector2(x + 1, y + 1), Vector2(mini(22, int(rect.size.x) - x - 1), mini(10, int(rect.size.y) - y - 1)))
			if cell.size.x > 0 and cell.size.y > 0:
				draw_rect(cell, color)
				draw_line(cell.position, cell.position + Vector2(cell.size.x, 0), color.lightened(0.12))

func _house(rect: Rect2) -> void:
	draw_rect(rect, Color("b09a70"))
	var roof := Rect2(rect.position, Vector2(rect.size.x, rect.size.y * 0.5))
	draw_rect(roof, Color("71483c"))
	for y in range(0, int(roof.size.y), 6):
		draw_line(roof.position + Vector2(0, y), roof.position + Vector2(roof.size.x, y), Color("9a6650"), 2)
	for x in [3.0, rect.size.x - 7]:
		draw_rect(Rect2(rect.position + Vector2(x, roof.size.y), Vector2(4, rect.size.y / 2)), Color("574734"))
	draw_rect(Rect2(rect.end - Vector2(rect.size.x / 2 + 8, 23), Vector2(16, 23)), Color("463e32"))
	for x in [14.0, rect.size.x - 27]:
		draw_rect(Rect2(rect.position + Vector2(x, roof.size.y + 9), Vector2(12, 10)), Color("503e2f"))
		draw_rect(Rect2(rect.position + Vector2(x + 2, roof.size.y + 10), Vector2(8, 7)), Color("d3b873"))

func _tree(rect: Rect2) -> void:
	draw_rect(rect, Color("283c2c"))
	draw_rect(rect.grow(-2), Color("3e5939"))
	draw_rect(Rect2(rect.position + Vector2(5, 2), Vector2(rect.size.x - 10, 12)), Color("617446"))
	draw_rect(Rect2(rect.position + Vector2(2, 10), Vector2(rect.size.x - 10, 13)), Color("4d683e"))
	draw_rect(Rect2(rect.position + Vector2(rect.size.x / 2 - 3, rect.size.y - 10), Vector2(6, 10)), Color("705336"))
	for i in 5:
		draw_rect(Rect2(rect.position + Vector2(4 + i * 5, 5 + (i % 2) * 8), Vector2(3, 2)), Color("819458"))
