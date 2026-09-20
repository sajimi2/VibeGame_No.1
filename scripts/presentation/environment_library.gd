@tool
extends RefCounted
## 环境材质唯一入口。资源在磁盘上可独立替换，场景和构件只选择语义名称。
const ROOT="res://assets/environment/materials/"
const ALIASES={"wall":"masonry","stone":"masonry","wood_frame":"timber","floor":"planks"}
static var cache: Dictionary={}
static func material(kind: String) -> ShaderMaterial:
	var id: String=ALIASES.get(kind,kind)
	if not cache.has(id): cache[id]=load(ROOT+id+".tres")
	return cache[id]
