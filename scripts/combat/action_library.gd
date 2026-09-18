extends RefCounted
## 稳定动作 ID 对应本地资源；表现和图集共用，新增动作无需改人物绘制或工作台界面。
static var cache: Dictionary = {}

static func get_action(id: String) -> Resource:
	if id.is_empty(): return null
	if not cache.has(id):
		var path := "res://data/actions/"+id.validate_filename()+".tres"
		cache[id] = load(path) if ResourceLoader.exists(path) else null
	return cache[id]

static func list_actions() -> Array[Resource]:
	var result: Array[Resource] = []
	var names := DirAccess.get_files_at("res://data/actions")
	names.sort()
	for name in names:
		if name.get_extension() != "tres": continue
		var profile := get_action(name.get_basename())
		if profile != null: result.append(profile)
	return result
