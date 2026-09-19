extends Resource
## 可复用的帧来源协议；工具只调用这些接口，新资产可用独立脚本提供不同尺寸/方向/动作。
@export var asset_id := ""
@export var title := ""
@export var cell_size := Vector2i(96,96)
@export var direction_count := 12

func animations() -> Array: return []
func options() -> Array: return []
func sample(_animation: String, _direction: int, _phase: int, _options: Dictionary) -> Dictionary: return {}

## 可选的工具预览协议：提供源场景、姿态与显示层；纯二维来源返回空值。
func model_preview(_animation: String, _direction: int, _phase: int, _options: Dictionary) -> Dictionary: return {}
