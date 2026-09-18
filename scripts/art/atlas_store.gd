extends RefCounted
## 图集持久化与运行时查询；只认识帧键和锚点，不依赖角色、战斗或预览界面。
const Bundle = preload("res://scripts/art/atlas_bundle.gd")
const Catalog = preload("res://scripts/art/atlas_catalog.gd")
static var root_path := "res://data/art_overrides"
static var loaded := false
static var catalog: Resource
static var frames: Dictionary = {}
static var textures: Dictionary = {}

## 重载后清空裁帧缓存；测试用独立 root_path 隔离。避免命名 reload，与 GDScript 原生方法冲突。
static func reload_catalog() -> void:
	loaded = true
	frames.clear()
	textures.clear()
	var path := root_path.path_join("catalog.tres")
	catalog = ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) if FileAccess.file_exists(path) else Catalog.new()
	if not catalog is Catalog:
		push_error("图集目录资源无效：" + path)
		catalog = Catalog.new()
	for bundle in catalog.sheets:
		if not bundle is Bundle: continue
		for index in bundle.cells.size():
			var cell: Dictionary = bundle.cells[index]
			frames[bundle.asset_id+":"+cell.key] = {"bundle":bundle,"index":index,"anchors":cell.get("anchors",{})}

## 未回导的帧返回空字典，由调用者继续程序生成；只覆盖清单中精确匹配的帧。
static func lookup(asset_id: String, key: String) -> Dictionary:
	if not loaded: reload_catalog()
	var id := asset_id+":"+key
	if not frames.has(id): return {}
	var entry: Dictionary = frames[id]
	if not textures.has(id):
		var bundle: Resource = entry.bundle
		var atlas: Texture2D = bundle.get_texture()
		if atlas == null: return {}
		var tile := AtlasTexture.new()
		tile.atlas = atlas
		tile.region = Rect2(Vector2(int(entry.index) % bundle.columns, floori(float(entry.index) / bundle.columns)) * Vector2(bundle.cell_size), Vector2(bundle.cell_size))
		textures[id] = tile
	return {"texture":textures[id],"anchors":entry.anchors}

## 先完整验证 JSON/PNG，再创建有效资源；外部文件只按数据读取，不加载外部脚本或 .tres。
static func inspect_package(json_path: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(json_path)) != OK or not json.data is Dictionary:
		return {"error":"清单不是有效 JSON 对象"}
	var manifest: Dictionary = json.data
	if manifest.get("format","") != "outpost_atlas_v1": return {"error":"不支持的图集清单版本"}
	var asset_id = manifest.get("asset_id")
	if not asset_id is String or asset_id.is_empty() or asset_id.length() > 80: return {"error":"资产 ID 无效"}
	var dimensions = manifest.get("cell_size")
	if not dimensions is Array or dimensions.size() != 2: return {"error":"缺少单帧尺寸"}
	for number in dimensions:
		if not (number is float or number is int) or number != int(number) or number < 1 or number > 512: return {"error":"单帧尺寸必须为 1～512 的整数"}
	var size := Vector2i(int(dimensions[0]),int(dimensions[1]))
	var columns = manifest.get("columns",0)
	if not (columns is float or columns is int) or columns != int(columns) or columns < 1 or columns > 256: return {"error":"列数无效"}
	var cells = manifest.get("cells")
	if not cells is Array or cells.is_empty() or cells.size() > 8192 or cells.size() % int(columns) != 0: return {"error":"帧数量与列数不匹配"}
	var keys := {}
	for cell in cells:
		if not cell is Dictionary or not cell.get("key") is String or cell.key.is_empty() or cell.key.length() > 2048: return {"error":"存在无效帧键"}
		if keys.has(cell.key): return {"error":"帧键重复，无法可靠回导"}
		keys[cell.key] = true
		var anchors = cell.get("anchors",{})
		if not anchors is Dictionary: return {"error":"锚点必须是对象"}
		for name in anchors:
			var point = anchors[name]
			if not point is Array or point.size() != 2: return {"error":"锚点必须是 [x,y]"}
			for n in point:
				if not (n is float or n is int) or not is_finite(float(n)): return {"error":"锚点数值无效"}
			if point[0] < 0 or point[1] < 0 or point[0] >= size.x or point[1] >= size.y: return {"error":"锚点超出单帧范围"}
	var png_name = manifest.get("image","")
	if not png_name is String or png_name.is_empty() or png_name != png_name.get_file() or png_name.get_extension().to_lower() != "png": return {"error":"PNG 必须与清单位于同一文件夹"}
	var bytes := FileAccess.get_file_as_bytes(json_path.get_base_dir().path_join(png_name))
	var image := Image.new()
	if image.load_png_from_buffer(bytes) != OK: return {"error":"无法读取对应 PNG"}
	var expected := Vector2i(size.x*int(columns),size.y*(cells.size()/int(columns)))
	if image.get_size() != expected: return {"error":"PNG 尺寸不匹配，应为 %d×%d；请勿缩放或裁掉边距" % [expected.x,expected.y]}
	return {"manifest":manifest,"bytes":bytes,"image":image}

## 目录采用临时文件替换，失败时保留旧有效目录；历史 bundle 不删除，便于人工回退。
static func save_catalog(next: Resource) -> Error:
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root_path))
	if error != OK: return error
	var temporary := root_path.path_join("catalog.pending.tres")
	error = ResourceSaver.save(next,temporary)
	if error == OK: error = DirAccess.rename_absolute(temporary,root_path.path_join("catalog.tres"))
	if error == OK: reload_catalog()
	return error

## 全部校验通过才写新资源，最后替换目录；相交的旧帧由最新记录优先，不动其他资产。
static func import_package(path: String) -> Dictionary:
	var checked := inspect_package(path)
	if checked.has("error"): return checked
	if not loaded: reload_catalog()
	var manifest: Dictionary = checked.manifest
	var bundle := Bundle.new()
	bundle.asset_id = manifest.asset_id
	bundle.cell_size = Vector2i(int(manifest.cell_size[0]),int(manifest.cell_size[1]))
	bundle.columns = int(manifest.columns)
	bundle.png_bytes = checked.bytes
	for cell in manifest.cells: bundle.cells.append(cell)
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root_path))
	if error != OK: return {"error":error_string(error)}
	var bundle_path := root_path.path_join("atlas_%s_%d.res" % [str(Time.get_unix_time_from_system()).replace(".","_"),Time.get_ticks_usec()])
	error = ResourceSaver.save(bundle,bundle_path)
	if error != OK: return {"error":error_string(error)}
	var next := Catalog.new()
	var replaced := {}
	for cell in bundle.cells: replaced[cell.key] = true
	for old in catalog.sheets:
		if not old is Bundle: continue
		var covered: bool = old.asset_id == bundle.asset_id
		for cell in old.cells: covered = covered and replaced.has(cell.key)
		if not covered: next.sheets.append(old)
	next.sheets.append(ResourceLoader.load(bundle_path,"",ResourceLoader.CACHE_MODE_IGNORE))
	error = save_catalog(next)
	return {"asset_id":bundle.asset_id,"frames":bundle.cells.size()} if error == OK else {"error":error_string(error)}

## 只取消指定资产的全部覆盖，其他角色保持原样；已导出的人工稿与历史资源都保留。
static func restore_asset(asset_id: String) -> Error:
	if not loaded: reload_catalog()
	var next := Catalog.new()
	for bundle in catalog.sheets:
		if bundle is Bundle and bundle.asset_id != asset_id: next.sheets.append(bundle)
	return save_catalog(next)
