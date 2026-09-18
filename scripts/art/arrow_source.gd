extends "res://scripts/art/atlas_source.gd"
## 箭使用单张侧影贴到交叉面，三维旋转由投射物负责，因此不需要十二份重复侧影。
const Art = preload("res://scripts/presentation/arrow_art.gd")

func animations() -> Array:
	return [{"id":"profile","label":"箭尖 · 木杆 · 尾羽","frames":1}]

func sample(_animation: String, _direction: int, _phase: int, _settings: Dictionary) -> Dictionary:
	return {"key":"profile","texture":Art.texture(asset_id),"anchors":{}}
