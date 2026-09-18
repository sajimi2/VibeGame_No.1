extends RefCounted
## 通用图集文档：拼帧、锚点和导出集中在这里，不依赖任何控件或具体人物参数。
var source: Resource
var animation: Dictionary
var settings: Dictionary
var image: Image
var cells: Array[Dictionary] = []

## 外部稿必须匹配已注册来源及原导出帧键；防止改错资产、尺寸或顺序后静默覆盖游戏。
func load_package(checked: Dictionary, sources: Array[Resource]) -> String:
	if checked.has("error"): return checked.error
	var manifest: Dictionary = checked.manifest
	var selected: Resource
	for candidate in sources:
		if candidate.asset_id == manifest.asset_id: selected = candidate; break
	if selected == null: return "工程尚未注册这个资产 ID：" + manifest.asset_id
	if Vector2i(int(manifest.cell_size[0]),int(manifest.cell_size[1])) != selected.cell_size or int(manifest.columns) != selected.direction_count:
		return "单帧尺寸或朝向列数与该资产不符"
	var clip: Dictionary = {}
	for item in selected.animations():
		if item.id == manifest.get("animation",""): clip = item; break
	if clip.is_empty() or manifest.cells.size() != int(clip.frames)*selected.direction_count: return "动作或帧数量与资产不符"
	var options = manifest.get("options",{})
	if not options is Dictionary: return "动作选项必须是对象"
	options = options.duplicate(true)
	for option in selected.options():
		# JSON 把整数也读为 float，Array.find/has 却区分类型；恢复来源声明的类型再比较。
		var value = options.get(option.id,option.default)
		var found := false
		for allowed in option.values:
			if (typeof(value) == typeof(allowed) and value == allowed) or (allowed is int and value is float and value == float(allowed)):
				options[option.id] = allowed
				found = true
				break
		if not found: return "动作选项无效：" + option.label
	var index := 0
	for phase in int(clip.frames):
		for direction in selected.direction_count:
			if manifest.cells[index].key != selected.sample(clip.id,direction,phase,options).key: return "帧键或排列已改变，请保留原 JSON 中的 key"
			index += 1
	source = selected
	animation = clip
	settings = options.duplicate(true)
	image = checked.image
	cells.clear()
	for cell in manifest.cells: cells.append(cell.duplicate(true))
	return ""

## 一次性按行相位、列朝向拼原尺寸图集；播放时只裁帧，不重复生成整张图。
func build(input_source: Resource, clip: Dictionary, options: Dictionary) -> void:
	source = input_source
	animation = clip
	settings = options.duplicate(true)
	image = Image.create(source.cell_size.x*source.direction_count,source.cell_size.y*int(clip.frames),false,Image.FORMAT_RGBA8)
	cells.clear()
	for phase in int(clip.frames):
		for direction in source.direction_count:
			var frame: Dictionary = source.sample(clip.id,direction,phase,settings)
			image.blit_rect(frame.texture.get_image(),Rect2i(Vector2i.ZERO,source.cell_size),Vector2i(direction,phase)*source.cell_size)
			cells.append({"key":frame.key,"anchors":frame.get("anchors",{}).duplicate(true)})

## 显示与导出共用同一张原尺寸 Image；锚点能在界面里修正，也能在 JSON 中人工编辑。
func cell_texture(direction: int, phase: int) -> ImageTexture:
	return ImageTexture.create_from_image(image.get_region(Rect2i(Vector2i(direction,phase)*source.cell_size,source.cell_size)))

## PNG 保存像素，伴随 JSON 保存稳定帧键和握点；文件名唯一，避免覆盖人工原稿。
func export_to(directory: String) -> Dictionary:
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	if error != OK: return {"error":error_string(error)}
	var prefix := "%s_%s_%d_%d" % [source.asset_id.validate_filename(),str(animation.id).validate_filename(),int(Time.get_unix_time_from_system()),Time.get_ticks_usec()]
	var path := directory.path_join(prefix)
	error = image.save_png(path+".png")
	if error != OK: return {"error":error_string(error)}
	var manifest := {"format":"outpost_atlas_v1","asset_id":source.asset_id,"image":prefix+".png",
		"cell_size":[source.cell_size.x,source.cell_size.y],"columns":source.direction_count,
		"animation":animation.id,"options":settings,"cells":cells}
	var file := FileAccess.open(path+".json",FileAccess.WRITE)
	if file == null: return {"error":error_string(FileAccess.get_open_error())}
	file.store_string(JSON.stringify(manifest,"\t"))
	file.close()
	return {"png":path+".png","json":path+".json"}
