extends RefCounted
## 原始图集按4×4取图，保持透明边缘；不把缩略图当作碰撞或装备尺寸。
static var atlas: Texture2D
static var cache: Dictionary = {}
static var regions: Dictionary = {}
static func icon(id: String, catalog: ItemCatalog) -> Texture2D:
	if id.is_empty(): return null
	if cache.has(id): return cache[id]
	var definition := catalog.definition(StringName(id))
	if definition != null and definition.icon_texture != null: return definition.icon_texture
	if definition == null or definition.icon_index < 0: return null
	if atlas == null: atlas = load("res://assets/ui/items/woodpath_atlas.png")
	var region := AtlasTexture.new()
	region.atlas = atlas
	if regions.is_empty(): regions = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ui/items/regions.json"))
	# 区域取原稿主体轮廓，避开透明底的孤立噪点；原图保持完整、不在运行时读回像素。
	var bounds: Array = regions[str(definition.icon_index)]
	region.region = Rect2(bounds[0],bounds[1],bounds[2],bounds[3])
	cache[id] = region
	return region
