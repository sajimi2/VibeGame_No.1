extends Control
## F6 工作台只负责交互；资产类型、拼帧和持久化分别由来源、文档和 Store 提供。
const Registry = preload("res://scripts/art/source_registry.gd")
const Document = preload("res://scripts/art/atlas_document.gd")
const Store = preload("res://scripts/art/atlas_store.gd")
const ModelPreview = preload("res://tools/art_model_preview.gd")
const OUTPUT := "res://work/art_atlases"
var sources: Array[Resource] = []
var document: RefCounted
var asset: OptionButton
var action: OptionButton
var direction: OptionButton
var zoom: OptionButton
var options_row: HBoxContainer
var option_controls: Dictionary = {}
var frame: SpinBox
var fps: SpinBox
var play: Button
var large: TextureRect
var sheet: TextureRect
var selected_cell: Panel
var grip_marker: ColorRect
var edit_grip: CheckBox
var status: Label
var frame_info: Label
var picker: FileDialog
var phase_time := 0.0
var view_mode: OptionButton
var atlas_scroll: ScrollContainer
var model_panel: VBoxContainer
var model_view: SubViewportContainer
var model_info: Label

func label_in(parent: Node, value: String) -> Label:
	var item := Label.new()
	item.text = value
	parent.add_child(item)
	return item

func choice(parent: Node, caption: String, values: Array = []) -> OptionButton:
	label_in(parent,caption)
	var item := OptionButton.new()
	for value in values: item.add_item(str(value))
	parent.add_child(item)
	return item

func button(parent: Node, caption: String, callback: Callable) -> Button:
	var item := Button.new()
	item.text = caption
	item.pressed.connect(callback)
	parent.add_child(item)
	return item

func image_view(parent: Node) -> TextureRect:
	var item := TextureRect.new()
	item.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	item.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	item.stretch_mode = TextureRect.STRETCH_SCALE
	item.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	item.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	parent.add_child(item)
	return item

## 场景独立运行，不创建关卡、不访问进度；写入只由导出/应用/恢复按钮触发。
func _ready() -> void:
	sources = Registry.list_sources()
	var background := ColorRect.new()
	background.color = Color("25313b")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","top","right","bottom"]: margin.add_theme_constant_override("margin_"+side,12)
	add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation",6)
	margin.add_child(layout)
	label_in(layout,"像素图集工作台 · 查看 / 导出 / 回导").add_theme_font_size_override("font_size",24)
	var selection := HBoxContainer.new()
	layout.add_child(selection)
	asset = choice(selection,"资产")
	for source in sources: asset.add_item(source.title)
	action = choice(selection,"动作")
	zoom = choice(selection,"图集缩放",["1 倍","2 倍","3 倍","4 倍"])
	zoom.select(1)
	view_mode = choice(selection,"查看",["像素图集","3D 源模型"])
	options_row = HBoxContainer.new()
	layout.add_child(options_row)
	var playback := HBoxContainer.new()
	layout.add_child(playback)
	direction = choice(playback,"朝向列")
	label_in(playback,"帧")
	frame = SpinBox.new()
	frame.step = 1
	playback.add_child(frame)
	button(playback,"上一帧",func(): select_frame(int(frame.value)-1))
	button(playback,"下一帧",func(): select_frame(int(frame.value)+1))
	play = button(playback,"播放",func(): pass)
	play.toggle_mode = true
	play.toggled.connect(func(playing: bool):
		play.text = "暂停" if playing else "播放"
		phase_time = 0)
	label_in(playback,"帧/秒")
	fps = SpinBox.new()
	fps.min_value = 1
	fps.max_value = 120
	fps.value = 8
	playback.add_child(fps)
	label_in(playback,"横向：朝向；纵向：动作帧。点图集选帧。")
	var content := HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(content)
	var detail := VBoxContainer.new()
	detail.custom_minimum_size.x = 230
	content.add_child(detail)
	large = image_view(detail)
	large.gui_input.connect(grip_input)
	grip_marker = ColorRect.new()
	grip_marker.color = Color("f5c542")
	grip_marker.size = Vector2(5,5)
	grip_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	large.add_child(grip_marker)
	edit_grip = CheckBox.new()
	edit_grip.text = "点击大图修正本帧握点"
	edit_grip.toggled.connect(func(enabled: bool):
		if enabled: play.button_pressed = false
		refresh_frame())
	detail.add_child(edit_grip)
	frame_info = label_in(detail,"")
	var scroll := ScrollContainer.new()
	atlas_scroll = scroll
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)
	model_panel = VBoxContainer.new()
	model_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	model_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(model_panel)
	var model_toolbar := HBoxContainer.new()
	model_panel.add_child(model_toolbar)
	button(model_toolbar,"复位视角",func(): model_view.reset_camera())
	label_in(model_toolbar,"左键拖动旋转 · 滚轮缩放 · 与左侧像素帧同步")
	model_view = ModelPreview.new()
	model_panel.add_child(model_view)
	model_info = label_in(model_panel,"")
	model_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	model_panel.hide()
	model_view.set_active(false)
	sheet = image_view(scroll)
	sheet.gui_input.connect(atlas_input)
	selected_cell = Panel.new()
	selected_cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var border := StyleBoxFlat.new()
	border.bg_color = Color.TRANSPARENT
	border.border_color = Color("e3c27b")
	border.set_border_width_all(2)
	selected_cell.add_theme_stylebox_override("panel",border)
	sheet.add_child(selected_cell)
	var exports := HBoxContainer.new()
	layout.add_child(exports)
	button(exports,"导出原尺寸 PNG + JSON",export_atlas)
	button(exports,"打开导出目录",func():
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
		OS.shell_open(ProjectSettings.globalize_path(OUTPUT)))
	button(exports,"载入编辑稿 JSON",func(): picker.popup_centered_ratio(0.8))
	button(exports,"应用当前图集到游戏",apply_atlas)
	button(exports,"恢复该资产源外观",restore_asset)
	status = label_in(layout,"")
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label_in(layout,"三维烘焙：完整合成可查看/导出，上身/下身可补色回导；形体改源模型后重烘焙。切换选项会放弃未应用预览，请先导出保留。")
	label_in(layout,"人物本体不含独立剑/盾/弓。三维源场景的 AnimationPlayer 可编辑共享动作；回导在下次 F5 生效。")
	picker = FileDialog.new()
	picker.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	picker.access = FileDialog.ACCESS_FILESYSTEM
	picker.filters = PackedStringArray(["*.json ; 图集清单"])
	var output_path := ProjectSettings.globalize_path(OUTPUT)
	picker.current_dir = output_path if DirAccess.dir_exists_absolute(output_path) else ProjectSettings.globalize_path("res://")
	picker.file_selected.connect(load_draft)
	add_child(picker)
	asset.item_selected.connect(func(_index: int): configure_source())
	action.item_selected.connect(func(_index: int): rebuild_atlas())
	direction.item_selected.connect(func(_index: int): refresh_frame())
	zoom.item_selected.connect(func(_index: int): resize_sheet())
	frame.value_changed.connect(func(_value: float): refresh_frame())
	view_mode.item_selected.connect(func(_index: int): refresh_view_mode())
	if not sources.is_empty(): configure_source()

## 控件来自来源的选项描述；新增角色或非人形资产不需要在此增加类型分支。
func configure_source(rebuild: bool = true) -> void:
	var source: Resource = sources[asset.selected]
	action.clear()
	for clip in source.animations(): action.add_item(clip.label)
	direction.clear()
	for column in source.direction_count: direction.add_item(str(column))
	for child in options_row.get_children():
		options_row.remove_child(child)
		child.queue_free()
	option_controls.clear()
	for option in source.options():
		var item := choice(options_row,option.label,option.labels)
		item.select(option.values.find(option.default))
		item.item_selected.connect(func(_index: int): rebuild_atlas())
		option_controls[option.id] = item
	if rebuild: rebuild_atlas()

## 切换选项即创建新预览文档；手绘稿需先应用或导出，避免把临时图误当成已保存资产。
func rebuild_atlas() -> void:
	var source: Resource = sources[asset.selected]
	var settings := {}
	for option in source.options(): settings[option.id] = option.values[option_controls[option.id].selected]
	document = Document.new()
	document.build(source,source.animations()[action.selected],settings)
	display_document()
	status.text = "预览：%s / %s · 原尺寸 %d×%d。导出包含当前选项的所有朝向与动作帧。" % [source.title,document.animation.label,document.image.get_width(),document.image.get_height()]

func display_document() -> void:
	frame.max_value = int(document.animation.frames)-1
	frame.set_value_no_signal(0)
	phase_time = 0
	sheet.texture = ImageTexture.create_from_image(document.image)
	large.custom_minimum_size = Vector2(document.source.cell_size)*4
	resize_sheet()

func resize_sheet() -> void:
	if document == null: return
	sheet.custom_minimum_size = Vector2(document.image.get_size())*(zoom.selected+1)
	sheet.size = sheet.custom_minimum_size
	refresh_frame()

## 显示与导出共用文档，握点标记是独立控件，绝不画进 PNG 像素。
func refresh_frame() -> void:
	if document == null: return
	large.texture = document.cell_texture(direction.selected,int(frame.value))
	selected_cell.position = Vector2(direction.selected,frame.value)*Vector2(document.source.cell_size)*(zoom.selected+1)
	selected_cell.size = Vector2(document.source.cell_size)*(zoom.selected+1)
	var anchors: Dictionary = document.cells[int(frame.value)*document.source.direction_count+direction.selected].anchors
	edit_grip.disabled = not anchors.has("grip")
	grip_marker.visible = anchors.has("grip") and edit_grip.button_pressed
	if anchors.has("grip"): grip_marker.position = Vector2(anchors.grip[0]+0.5,anchors.grip[1]+0.5)*4-Vector2(2.5,2.5)
	frame_info.text = "朝向 %d · 帧 %d / %d\n单格 %d×%d · 大图 4 倍" % [direction.selected,int(frame.value),int(frame.max_value),document.source.cell_size.x,document.source.cell_size.y]
	refresh_view_mode()

## 三维能力由来源声明；旧二维/箭矢来源自动回到图集，导出和回导始终操作像素文档。
func refresh_view_mode() -> void:
	if document == null: return
	var descriptor: Dictionary = document.source.model_preview(document.animation.id,direction.selected,int(frame.value),document.settings)
	view_mode.set_item_disabled(1,descriptor.is_empty())
	if descriptor.is_empty(): view_mode.select(0)
	var show_model := view_mode.selected == 1
	atlas_scroll.visible = not show_model
	model_panel.visible = show_model
	model_view.set_active(show_model)
	if descriptor.is_empty(): model_view.clear_model()
	if not show_model: return
	var error: String = model_view.show_frame(descriptor)
	model_info.text = error if not error.is_empty() else "源模型：%s\n显示已保存的模型/骨骼动作，不包含独立剑盾弓或手绘补色。导出/回导按钮仍操作左侧像素图。" % str(descriptor.scene).trim_prefix("res://")

func select_frame(value: int) -> void:
	play.button_pressed = false
	frame.value = posmod(value,int(frame.max_value)+1)

func _process(delta: float) -> void:
	if document == null or not play.button_pressed: return
	phase_time += delta*fps.value
	if phase_time >= 1:
		var steps := floori(phase_time)
		phase_time -= steps
		frame.value = posmod(int(frame.value)+steps,int(frame.max_value)+1)

func atlas_input(event: InputEvent) -> void:
	if document == null or event is not InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT: return
	var cell: Vector2i = Vector2i(event.position/(zoom.selected+1))/document.source.cell_size
	if cell.x < 0 or cell.x >= document.source.direction_count or cell.y < 0 or cell.y > frame.max_value: return
	direction.select(cell.x)
	select_frame(cell.y)
	refresh_frame()

## 手形改变后可逐帧校准握点；修改暂存在文档，导出或应用才写盘。
func grip_input(event: InputEvent) -> void:
	if document == null or not edit_grip.button_pressed or edit_grip.disabled: return
	if event is not InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT: return
	var pixel := Vector2i(event.position/4)
	if not Rect2i(Vector2i.ZERO,document.source.cell_size).has_point(pixel): return
	play.button_pressed = false
	document.cells[int(frame.value)*document.source.direction_count+direction.selected].anchors.grip = [pixel.x,pixel.y]
	refresh_frame()
	status.text = "已修改当前帧握点为 (%d,%d)；点击导出保留，或应用到游戏。" % [pixel.x,pixel.y]

func export_atlas() -> Dictionary:
	if document == null: return {"error":"没有可导出的图集"}
	var result: Dictionary = document.export_to(OUTPUT)
	status.text = "导出失败："+result.error if result.has("error") else "已导出 PNG + JSON："+result.png.trim_prefix("res://")
	return result

## 先验证显示手绘稿，失败时保留现有文档和游戏外观；载入本身不写回工程。
func load_draft(path: String) -> void:
	var candidate := Document.new()
	var error := candidate.load_package(Store.inspect_package(path),sources)
	if not error.is_empty(): status.text = "载入失败："+error; return
	document = candidate
	asset.select(sources.find(document.source))
	configure_source(false)
	for index in document.source.animations().size():
		if document.source.animations()[index].id == document.animation.id: action.select(index)
	for option in document.source.options(): option_controls[option.id].select(option.values.find(document.settings.get(option.id,option.default)))
	display_document()
	play.button_pressed = false
	status.text = "编辑稿已载入，尚未改变游戏。检查像素与握点后点击“应用当前图集到游戏”。"

## 应用另存当前 PNG/清单快照，再持久化自包含资源；移动导出稿不会破坏游戏。
func apply_atlas() -> Dictionary:
	if document==null: return {"error":"没有图集"}
	if document.source.has_method("validate_edit"):
		var reason: String=document.source.validate_edit(document)
		if not reason.is_empty():
			status.text=reason
			return {"error":reason}
	var exported := export_atlas()
	if exported.has("error"): return exported
	var result := Store.import_package(exported.json)
	status.text = "应用失败："+result.error if result.has("error") else "已应用 %s 的 %d 帧到 data/art_overrides；下次 F5 生效。其余姿态继续使用源外观。" % [result.asset_id,result.frames]
	return result

func restore_asset() -> void:
	var error := Store.restore_asset(sources[asset.selected].asset_id)
	if error == OK: rebuild_atlas()
	status.text = "已恢复该资产全部源帧；其他资产及导出稿保留，下次 F5 生效。" if error == OK else "恢复失败："+error_string(error)
