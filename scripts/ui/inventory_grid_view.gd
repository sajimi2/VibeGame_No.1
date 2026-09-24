extends Control
## 网格纯视图：绘制快照与候选占格，按下只上报意图，不直接改库存。
signal item_pressed(entry: Dictionary, event: InputEventMouseButton)
const Icons = preload("res://scripts/ui/item_icons.gd")
var snapshot: Dictionary = {}
var catalog: ItemCatalog
var cell_size := 48.0
var selected := ""
var preview := Rect2i()
var preview_valid := false
var entries: Array = []

func setup(data: Dictionary, items: ItemCatalog, side: float) -> void:
	snapshot = data
	catalog = items
	cell_size = side
	size = Vector2(8,6)*side
	entries = data.get("bag",[])
	queue_redraw()

func entry_rect(entry: Dictionary) -> Rect2:
	var definition := catalog.definition(StringName(entry.definition_id))
	var extent := definition.footprint if definition != null else Vector2i.ONE
	if entry.get("rotated",false): extent = Vector2i(extent.y,extent.x)
	return Rect2(Vector2(entry.get("x",0),entry.get("y",0))*cell_size,Vector2(extent)*cell_size)

func _draw() -> void:
	for y in 6:
		for x in 8:
			var area := Rect2(Vector2(x,y)*cell_size,Vector2.ONE*cell_size)
			draw_rect(area,Color("182126") if (x+y)%2==0 else Color("1b252a"))
			draw_rect(area,Color("384249"),false,1)
	for entry in entries:
		if entry.is_empty(): continue
		var area := entry_rect(entry).grow(-2)
		draw_rect(area,Color("344047") if entry.instance_id==selected else Color("253137"))
		draw_rect(area,Color("d4b881") if entry.instance_id==selected else Color("697269"),false,1)
		var texture := Icons.icon(entry.definition_id,catalog)
		if texture != null: paint_icon(texture,area.grow(-5),entry.get("rotated",false))
		if int(entry.get("quantity",1))>1:
			draw_string(get_theme_default_font(),area.end-Vector2(21,5),str(entry.quantity),HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("f2e1b4"))
	if preview.size != Vector2i.ZERO:
		var area := Rect2(Vector2(preview.position)*cell_size,Vector2(preview.size)*cell_size)
		draw_rect(area,Color(0.3,0.8,0.5,.28) if preview_valid else Color(.9,.25,.22,.35))
		draw_rect(area,Color("8fcf98") if preview_valid else Color("f08072"),false,2)

func paint_icon(texture: Texture2D, area: Rect2, rotated: bool) -> void:
	var extent := texture.get_size()
	if rotated: extent = Vector2(extent.y,extent.x)
	var factor := minf(area.size.x/extent.x,area.size.y/extent.y)
	draw_set_transform(area.get_center(),PI*.5 if rotated else 0)
	draw_texture_rect(texture,Rect2(-texture.get_size()*factor*.5,texture.get_size()*factor),false)
	draw_set_transform(Vector2.ZERO)

func entry_at(point: Vector2) -> Dictionary:
	for entry in entries:
		if not entry.is_empty() and entry_rect(entry).has_point(point): return entry
	return {}

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var entry := entry_at(event.position)
		if not entry.is_empty(): item_pressed.emit(entry,event)
		accept_event()
