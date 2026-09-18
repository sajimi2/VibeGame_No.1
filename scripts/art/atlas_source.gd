extends Resource
## 可复用的帧来源协议；工具只调用这些接口，新资产可用独立脚本提供不同尺寸/方向/动作。
@export var asset_id := ""
@export var title := ""
@export var cell_size := Vector2i(32,48)
@export var direction_count := 12

func animations() -> Array: return []
func options() -> Array: return []
func sample(_animation: String, _direction: int, _phase: int, _options: Dictionary) -> Dictionary: return {}
