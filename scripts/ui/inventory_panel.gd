extends CanvasLayer
## 背包发布操作意图；实际库存、容器与持久化由成长/篇章模块负责。
signal equip_requested(instance_id: String)
signal quick_requested(index: int)
signal refresh_requested
signal action_requested(action: String, data: Dictionary)
signal closed
const Grid = preload("res://scripts/ui/inventory_grid_view.gd")
const Icons = preload("res://scripts/ui/item_icons.gd")
const GOLD := Color("d6bc84")
const INK := Color("172126")
const SLOT_NAMES := {"weapon":"武器","head":"头部","body":"躯干","hands":"手套","feet":"靴子","cloak":"披风","accessory":"饰品"}
var panel: Panel
var content: Control
var quick_bar: HBoxContainer
var quick_buttons: Array[Button] = []
var shade: ColorRect
var open := false
var previous_pause := false
var model: Dictionary = {}
var catalog: ItemCatalog
var bag_grid: Control
var external_grid: Control
var detail: RichTextLabel
var message: Label
var journal_view: RichTextLabel
var equipment_root: Control
var external_root: Control
var equipment_buttons: Dictionary = {}
var selected: Dictionary = {}
var selected_source := "bag"
var drag: Dictionary = {}
var drag_source := ""
var drag_offset := Vector2i.ZERO
var drag_rotated := false
var ghost: TextureRect
var context: PopupMenu
var context_actions: Array[String] = []
var actions: HBoxContainer
var recovery_button: Button
var recovery_popup: PopupMenu
var heading: Label
var stat_label: Label
var coins_label: Label
var storage_title: Label
var journal_open := false
var show_equipment := false

func tile_style(chosen := false, hover := false) -> StyleBoxTexture:
	return preload("res://scripts/ui/pixel_style.gd").box(chosen,hover)

func label(parent: Node, text: String, at: Vector2, font_size := 16) -> Label:
	var node := Label.new()
	node.text = text
	node.position = at
	node.add_theme_font_size_override("font_size",font_size)
	node.add_theme_color_override("font_color",GOLD)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node

func button(parent: Node, text: String, at: Vector2, extent: Vector2, callback: Callable) -> Button:
	var node := Button.new()
	node.text = text
	node.position = at
	node.size = extent
	node.focus_mode = Control.FOCUS_NONE
	node.add_theme_stylebox_override("normal",tile_style())
	node.add_theme_stylebox_override("hover",tile_style(false,true))
	node.add_theme_stylebox_override("pressed",tile_style(true))
	node.pressed.connect(callback)
	parent.add_child(node)
	return node

func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	catalog = ItemCatalog.build()
	shade = ColorRect.new()
	shade.color = Color(.015,.025,.035,.78)
	shade.size = Vector2(1280,720)
	shade.hide()
	add_child(shade)
	panel = Panel.new()
	panel.theme=preload("res://scripts/ui/pixel_style.gd").theme()
	panel.position = Vector2(8,8)
	panel.size = Vector2(1264,704)
	var style := StyleBoxEmpty.new()
	panel.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	panel.add_theme_stylebox_override("panel",style)
	add_child(panel)
	# 整幅织物/石雕框背景放在所有控件之下，避免纹样覆盖正文或截获鼠标。
	var background:=TextureRect.new()
	background.texture=load("res://assets/ui/woodpath_v3/ui_panel.png")
	background.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	background.size=panel.size
	background.mouse_filter=Control.MOUSE_FILTER_IGNORE
	panel.add_child(background)
	content = panel
	heading = label(panel,"旅人的行囊",Vector2(64,92),26)
	coins_label = label(panel,"",Vector2(640,102),16)
	button(panel,"收起  I / Esc",Vector2(1060,94),Vector2(138,36),toggle)
	button(panel,"装备 / 容器",Vector2(62,136),Vector2(130,32),func(): journal_open=false; show_equipment=not show_equipment; refresh(model))
	button(panel,"冒险日志",Vector2(206,136),Vector2(130,32),func(): journal_open=true; refresh(model))
	label(panel,"随身物品 · 8 × 6",Vector2(358,170),18)
	bag_grid = Grid.new()
	bag_grid.position = Vector2(358,204)
	bag_grid.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bag_grid.item_pressed.connect(func(entry: Dictionary,event: InputEventMouseButton): _pressed(entry,event,"bag"))
	panel.add_child(bag_grid)
	equipment_root = Control.new()
	equipment_root.position = Vector2(62,190)
	panel.add_child(equipment_root)
	var figure:=preload("res://scripts/ui/equipment_figure.gd").new()
	equipment_root.add_child(figure)
	var places := {"head":Vector2(106,24),"weapon":Vector2(8,110),"body":Vector2(8,210),"cloak":Vector2(204,110),"hands":Vector2(204,210),"feet":Vector2(106,306),"accessory":Vector2(204,306)}
	for slot in places:
		var tile := make_tile(68)
		tile.position = places[slot]
		equipment_root.add_child(tile)
		equipment_buttons[slot] = tile
		label(equipment_root,SLOT_NAMES[slot],places[slot]+Vector2(20,-22),14)
		tile.gui_input.connect(func(event: InputEvent): _equipment_input(slot,event))
	stat_label = label(panel,"",Vector2(62,568),14)
	external_root = Control.new()
	panel.add_child(external_root)
	storage_title = label(external_root,"",Vector2(62,188),17)
	external_grid = Grid.new()
	external_grid.position = Vector2(62,218)
	external_grid.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	external_grid.item_pressed.connect(func(entry: Dictionary,event: InputEventMouseButton): _pressed(entry,event,model.get("container_id","")))
	external_root.add_child(external_grid)
	button(external_root,"全部拿取",Vector2(62,450),Vector2(130,34),func(): action_requested.emit("take_all",{}))
	button(external_root,"查看装备",Vector2(202,450),Vector2(130,34),func(): show_equipment=true; refresh(model))
	journal_view = RichTextLabel.new()
	journal_view.position = Vector2(62,190)
	journal_view.size = Vector2(282,372)
	journal_view.add_theme_font_size_override("normal_font_size",16)
	journal_view.add_theme_constant_override("line_separation",6)
	panel.add_child(journal_view)
	label(panel,"物品详情",Vector2(788,170),19)
	detail = RichTextLabel.new()
	detail.position = Vector2(788,204)
	detail.size = Vector2(410,260)
	detail.bbcode_enabled = true
	detail.add_theme_font_size_override("normal_font_size",18)
	detail.add_theme_constant_override("line_separation",6)
	panel.add_child(detail)
	actions = HBoxContainer.new()
	actions.position = Vector2(788,488)
	actions.add_theme_constant_override("separation",8)
	panel.add_child(actions)
	recovery_button = button(panel,"领取遗留物",Vector2(788,550),Vector2(140,32),_show_recovery)
	label(panel,"音乐",Vector2(940,543),14)
	var volume := HSlider.new()
	volume.position = Vector2(995,545)
	volume.size = Vector2(200,24)
	volume.min_value = 0
	volume.max_value = 100
	var music_bus := AudioServer.get_bus_index("Music")
	volume.value = db_to_linear(AudioServer.get_bus_volume_db(music_bus))*100 if music_bus>=0 else 40
	volume.value_changed.connect(func(value: float):
		var bus := AudioServer.get_bus_index("Music")
		if bus>=0: AudioServer.set_bus_volume_db(bus,linear_to_db(value/100.0) if value>0 else -80.0))
	panel.add_child(volume)
	label(panel,"音效",Vector2(940,579),14)
	var sfx_volume:=HSlider.new()
	sfx_volume.position=Vector2(995,581)
	sfx_volume.size=Vector2(200,24)
	sfx_volume.max_value=100
	var sfx_bus:=AudioServer.get_bus_index("SFX")
	sfx_volume.value=db_to_linear(AudioServer.get_bus_volume_db(sfx_bus))*100 if sfx_bus>=0 else 100
	sfx_volume.value_changed.connect(func(value: float):
		var bus:=AudioServer.get_bus_index("SFX")
		if bus>=0: AudioServer.set_bus_volume_db(bus,linear_to_db(value/100) if value>0 else -80))
	panel.add_child(sfx_volume)
	message = label(panel,"",Vector2(358,540),14)
	label(panel,"拖放整理 · 拖动时 R 旋转 · 右键操作 · Shift 单击转移 · Esc 取消拖动",Vector2(64,593),14)
	context = PopupMenu.new()
	context.id_pressed.connect(func(index: int): _action(context_actions[index]))
	add_child(context)
	recovery_popup = PopupMenu.new()
	recovery_popup.id_pressed.connect(func(index: int):
		var entries: Array = model.inventory.get("recovery",[])
		if index<entries.size(): action_requested.emit("recover",{"id":entries[index].instance_id}))
	add_child(recovery_popup)
	ghost = TextureRect.new()
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ghost.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ghost.modulate = Color(1,1,1,.7)
	ghost.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(ghost)
	ghost.hide()
	panel.hide()
	quick_bar = HBoxContainer.new()
	quick_bar.theme=preload("res://scripts/ui/pixel_style.gd").theme()
	quick_bar.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	quick_bar.position = Vector2(404,620)
	quick_bar.add_theme_constant_override("separation",12)
	add_child(quick_bar)
	for i in 5:
		var tile := make_tile(84)
		tile.pressed.connect(func(): if drag.is_empty(): quick_requested.emit(i))
		label(tile,str(i+1),Vector2(8,4),14)
		quick_bar.add_child(tile)
		quick_buttons.append(tile)

func make_tile(side: float) -> Button:
	var tile := Button.new()
	tile.custom_minimum_size = Vector2.ONE*side
	tile.size = Vector2.ONE*side
	tile.focus_mode = Control.FOCUS_NONE
	for state in ["normal","disabled","hover","pressed"]: tile.add_theme_stylebox_override(state,tile_style(state=="pressed",state=="hover"))
	var art := TextureRect.new()
	art.name = "Art"
	art.position = Vector2(10,10)
	art.size = Vector2.ONE*(side-20)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tile.add_child(art)
	return tile

func set_tile(tile: Button, definition: String, chosen: bool, available: bool) -> void:
	tile.get_node("Art").texture = weapon_icon(definition)
	tile.get_node("Art").modulate = Color.WHITE if available else Color(.5,.5,.5,.55)
	tile.disabled = not available
	tile.add_theme_stylebox_override("normal",tile_style(chosen))
	tile.set_meta("definition_id",definition)

func weapon_icon(id: String) -> Texture2D: return Icons.icon(id,catalog)

## 快照刷新不重建拖动源；按实际实例更新选择，避免堆叠/交付后的幽灵物品。
func refresh(data: Dictionary) -> void:
	if data.is_empty(): return
	model = data
	catalog = model.catalog
	coins_label.text = "%d 枚钱币  ·  等级 %d" % [model.coins,model.level]
	for i in quick_buttons.size():
		var entry: Dictionary = model.quick_slots[i]
		set_tile(quick_buttons[i],entry.definition_id,entry.selected,not entry.id.is_empty())
		quick_buttons[i].tooltip_text = entry.label+(" · 未随身携带" if entry.id.is_empty() else " · 按 %d 装备" % (i+1))
	bag_grid.setup(model.inventory,catalog,48)
	var has_external: bool = not model.container_id.is_empty()
	external_root.visible = has_external and not journal_open and not show_equipment
	equipment_root.visible = (not has_external or show_equipment) and not journal_open
	journal_view.visible = journal_open
	if has_external:
		external_grid.setup(model.container,catalog,34)
		storage_title.text = model.container_title
	for slot in equipment_buttons:
		var entry: Dictionary = model.inventory.equipment.get(slot,{})
		var tile: Button = equipment_buttons[slot]
		set_tile(tile,entry.get("definition_id",""),false,not entry.is_empty())
		tile.disabled = false
		tile.tooltip_text = SLOT_NAMES[slot]+(" · 空" if entry.is_empty() else " · 右键卸下，或拖入背包")
	stat_label.text = "生命 %d / %d   护甲 %d" % [model.hp,model.max_hp,model.armor]
	journal_view.text = "还没有记录。去营地与管事谈谈。" if model.journal.is_empty() else "\n\n".join(model.journal)
	message.text = model.message
	message.text = message.text.left(54)
	recovery_button.visible = not model.inventory.get("recovery",[]).is_empty()
	if not selected.is_empty():
		var found := false
		var source_data: Dictionary = model.inventory if selected_source in ["bag","equipment"] else model.container
		var entries: Array = source_data.get("equipment",{}).values() if selected_source=="equipment" else source_data.get("bag",[])
		for entry in entries:
			if entry.get("instance_id","") == selected.get("instance_id",""):
				selected = entry
				found = true
				break
		if not found: selected = {}
	_update_detail()

func _update_detail() -> void:
	for child in actions.get_children():
		actions.remove_child(child)
		child.queue_free()
	bag_grid.selected = selected.get("instance_id","")
	bag_grid.queue_redraw()
	if selected.is_empty():
		detail.text = "[color=#d6bc84]行前准备[/color]\n\n武器占据不同大小的空间。\n装备穿戴在身上，备用物品放入行囊。\n\n选择一件物品查看用途。\n靠近箱子按 E 搜查。"
		return
	var definition := catalog.definition(StringName(selected.definition_id))
	if definition == null: return
	detail.text = "[color=#e6c889][b]%s[/b][/color]\n\n%s\n\n占格 %d × %d    数量 %d / %d" % [definition.display_name,definition.description,definition.footprint.x,definition.footprint.y,int(selected.get("quantity",1)),definition.max_stack]
	if definition.weapon_profile != null:
		detail.text += "\n\n携带备用武器会占用行囊空间。\n1–5 或快捷栏切换，需能放回旧武器。"
	for pair in _available_actions():
		var node := button(actions,pair[1],Vector2.ZERO,Vector2(82,34),func(): _action(pair[0]))
		node.custom_minimum_size = Vector2(82,34)

func _available_actions() -> Array:
	if selected.is_empty(): return []
	if selected_source=="equipment": return [["unequip","卸下"]]
	if selected_source!="bag": return [["transfer","拿取"]]
	var definition := catalog.definition(StringName(selected.definition_id))
	var result: Array = []
	if ActorInventory.slot_for_category(definition.category)!=&"": result.append(["equip","装备"])
	if definition.heal_amount>0: result.append(["use","使用"])
	if definition.category==ItemDefinition.Category.EVIDENCE: result.append(["read","阅读"])
	if int(selected.get("quantity",1))>1: result.append(["split","拆分"])
	if not model.container_id.is_empty(): result.append(["transfer","存入"])
	return result

func _action(action: String) -> void:
	if selected.is_empty(): return
	var data := {"id":selected.instance_id}
	if action=="transfer":
		data.from = selected_source
		data.to = model.container_id if selected_source=="bag" else "bag"
	action_requested.emit(action,data)

func _pressed(entry: Dictionary, event: InputEventMouseButton, source: String) -> void:
	selected = entry
	selected_source = source
	_update_detail()
	if event.button_index==MOUSE_BUTTON_RIGHT:
		_show_context()
	elif event.button_index==MOUSE_BUTTON_LEFT:
		if event.shift_pressed and not model.container_id.is_empty(): _action("transfer")
		elif event.double_click:
			var options := _available_actions()
			if not options.is_empty(): _action(options[0][0])
		else:
			var grid: Control = bag_grid if source=="bag" else external_grid
			drag_offset = Vector2i((event.position-grid.entry_rect(entry).position)/grid.cell_size)
			_begin_drag(entry,source)

func _equipment_input(slot: String, event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed: return
	var entry: Dictionary = model.inventory.equipment.get(slot,{})
	if entry.is_empty(): return
	selected = entry
	selected_source = "equipment"
	_update_detail()
	if event.button_index==MOUSE_BUTTON_RIGHT: _show_context()
	elif event.button_index==MOUSE_BUTTON_LEFT:
		drag_offset = Vector2i.ZERO
		_begin_drag(entry,"equipment")

func _show_context() -> void:
	context.clear()
	context_actions.clear()
	for pair in _available_actions():
		context.add_item(pair[1])
		context_actions.append(pair[0])
	context.position = Vector2i(get_viewport().get_mouse_position())
	context.popup()

func _show_recovery() -> void:
	recovery_popup.clear()
	for entry in model.inventory.get("recovery",[]):
		var definition := catalog.definition(StringName(entry.get("definition_id","")))
		recovery_popup.add_item("领取 · "+(definition.display_name if definition else str(entry.get("definition_id","未知物品"))))
	recovery_popup.position = Vector2i(panel.position+Vector2(750,250))
	recovery_popup.popup()

func _begin_drag(entry: Dictionary, source: String) -> void:
	drag = entry.duplicate(true)
	drag_source = source
	drag_rotated = entry.get("rotated",false)
	ghost.texture = weapon_icon(entry.definition_id)
	ghost.size = Vector2(76,76)
	ghost.show()

func _cancel_drag() -> void:
	drag = {}
	ghost.hide()
	for grid in [bag_grid,external_grid]:
		grid.preview = Rect2i()
		grid.queue_redraw()

## 拖动只有预览，没有中途删除；松手才向拥有者提交目标格。
func _process(_delta: float) -> void:
	if drag.is_empty(): return
	var cursor := get_viewport().get_mouse_position()
	ghost.position = cursor+Vector2(12,12)
	ghost.pivot_offset=ghost.size*.5
	ghost.rotation=PI*.5 if drag_rotated else 0
	for grid in [bag_grid,external_grid]:
		grid.preview = Rect2i()
		if grid.is_visible_in_tree() and grid.get_global_rect().has_point(cursor):
			var cell := Vector2i((cursor-grid.global_position)/grid.cell_size)-drag_offset
			var definition := catalog.definition(StringName(drag.definition_id))
			var extent := definition.footprint
			if drag_rotated: extent = Vector2i(extent.y,extent.x)
			grid.preview = Rect2i(cell,extent)
			var areas: Array[Rect2i] = []
			for entry in grid.entries:
				if entry.is_empty() or entry.instance_id==drag.instance_id: continue
				var rect: Rect2 = grid.entry_rect(entry)
				areas.append(Rect2i(Vector2i(rect.position/grid.cell_size),Vector2i(rect.size/grid.cell_size)))
			grid.preview_valid = InventoryGrid.fits(8,6,cell,extent,areas)
			# 堆叠目标虽占格，兼容且能容纳整叠时仍可放置。
			var target: Dictionary=grid.entry_at(Vector2(cell)*grid.cell_size+Vector2.ONE)
			if not target.is_empty() and target.instance_id!=drag.instance_id and definition.max_stack>1:
				grid.preview_valid=target.definition_id==drag.definition_id and target.get("rarity",0)==drag.get("rarity",0) and target.get("modifiers",{})==drag.get("modifiers",{}) and int(target.get("quantity",1))+int(drag.get("quantity",1))<=definition.max_stack
			if drag_source=="equipment" and grid==external_grid: grid.preview_valid=false
		grid.queue_redraw()

func _drop(cursor: Vector2) -> void:
	for grid in [bag_grid,external_grid]:
		if not grid.is_visible_in_tree() or not grid.get_global_rect().has_point(cursor): continue
		var destination: String = "bag" if grid==bag_grid else model.container_id
		var cell := Vector2i((cursor-grid.global_position)/grid.cell_size)-drag_offset
		var data := {"id":drag.instance_id,"cell":cell,"rotated":drag_rotated}
		if drag_source=="equipment" and destination=="bag": action_requested.emit("unequip",data)
		elif drag_source==destination:
			action_requested.emit("move" if destination=="bag" else "move_container",data)
		else:
			data.from = drag_source
			data.to = destination
			action_requested.emit("transfer",data)
		_cancel_drag()
		return
	if drag_source=="bag" and equipment_root.visible:
		for slot in equipment_buttons:
			if equipment_buttons[slot].get_global_rect().has_point(cursor): action_requested.emit("equip",{"id":drag.instance_id,"slot":StringName(slot)})
	_cancel_drag()

func toggle() -> void:
	if not open and get_tree().paused: return
	open = not open
	_cancel_drag()
	context.hide()
	recovery_popup.hide()
	panel.visible = open
	shade.visible = open
	quick_bar.visible = not open
	if open:
		show_equipment=false
		journal_open=false
		previous_pause = get_tree().paused
		get_tree().paused = true
		refresh_requested.emit()
	else:
		get_tree().paused = previous_pause
		closed.emit()

## 打开背包后优先消费旋转/关闭按键，避免 R 重开或 Esc 退出穿透到世界。
func _input(event: InputEvent) -> void:
	if not open: return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed and not drag.is_empty():
		_drop(event.position)
		get_viewport().set_input_as_handled()
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode==KEY_R:
			if not drag.is_empty() and catalog.definition(StringName(drag.definition_id)).rotatable:
				drag_rotated = not drag_rotated
				drag_offset = Vector2i.ZERO
		elif event.physical_keycode==KEY_ESCAPE:
			if not drag.is_empty(): _cancel_drag()
			else: toggle()
		elif event.physical_keycode==KEY_I: toggle()
		elif event.physical_keycode>=KEY_1 and event.physical_keycode<=KEY_5:
			if drag.is_empty(): quick_requested.emit(event.physical_keycode-KEY_1)
		else: return
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or get_tree().paused: return
	if event.physical_keycode==KEY_I:
		toggle()
		get_viewport().set_input_as_handled()
	elif event.physical_keycode>=KEY_1 and event.physical_keycode<=KEY_5:
		quick_requested.emit(event.physical_keycode-KEY_1)
		get_viewport().set_input_as_handled()
