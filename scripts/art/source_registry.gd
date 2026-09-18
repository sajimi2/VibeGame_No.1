extends RefCounted
## 扫描工程内的来源资源；增加角色只需添加资源/适配器，预览界面无需添加类型分支。
const Source = preload("res://scripts/art/atlas_source.gd")
static func list_sources(directory: String = "res://data/art_sources") -> Array[Resource]:
	var result: Array[Resource] = []
	var names := DirAccess.get_files_at(directory)
	names.sort()
	var ids := {}
	for file in names:
		if file.get_extension() != "tres": continue
		var source = load(directory.path_join(file))
		if not source is Source or source.asset_id.is_empty() or source.animations().is_empty(): continue
		if ids.has(source.asset_id):
			push_error("重复的美术资产 ID："+source.asset_id)
			continue
		ids[source.asset_id] = true
		result.append(source)
	return result
