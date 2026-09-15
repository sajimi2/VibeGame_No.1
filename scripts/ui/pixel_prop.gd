extends Node2D
var kind := "board"

func setup(body: Node2D) -> void:
	kind = "rack" if String(body.name) == "WeaponRack" else ("exit" if String(body.name).begins_with("Exit") else "board")
	var old := body.get_node_or_null("Visual") as CanvasItem
	if old != null: old.hide()
	queue_redraw()

func _draw() -> void:
	if kind == "exit":
		draw_rect(Rect2(-18, -23, 36, 46), Color("596568"))
		draw_rect(Rect2(-13, -18, 26, 41), Color("1e3037"))
		draw_rect(Rect2(-18, 20, 36, 4), Color("c1ae7b"))
		draw_line(Vector2(-6, 0), Vector2(7, 0), Color("d5d5a0"), 2)
		draw_line(Vector2(2, -5), Vector2(7, 0), Color("d5d5a0"), 2)
		draw_line(Vector2(2, 5), Vector2(7, 0), Color("d5d5a0"), 2)
		return
	draw_rect(Rect2(-13, 6, 28, 5), Color(0.05, 0.06, 0.04, 0.5))
	draw_rect(Rect2(-9, -4, 4, 15), Color("705234"))
	draw_rect(Rect2(6, -4, 4, 15), Color("705234"))
	draw_rect(Rect2(-14, -20, 28, 23), Color("4d3f2e"))
	draw_rect(Rect2(-12, -18, 24, 19), Color("936f44"))
	if kind == "board":
		draw_rect(Rect2(-8, -15, 15, 14), Color("dbcc93"))
		for y in [-12, -8, -4]: draw_line(Vector2(-5, y), Vector2(4, y), Color("9b855b"), 1)
	else:
		draw_rect(Rect2(-2, -19, 3, 25), Color("c2d2cd"))
		draw_rect(Rect2(1, -18, 7, 12), Color("a8b5b4"))
		draw_rect(Rect2(-5, 0, 10, 2), Color("d4b668"))
