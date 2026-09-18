class_name TacticalWeaponData
extends Resource
## 约定只读的 3D 武器参数；距离单位为米，时间单位为秒。
# 保留已序列化的 HEAVY=1；新增中型不能把旧重刀误读成中型。
enum WeightClass { LIGHT = 0, MEDIUM = 2, HEAVY = 1 }
@export var weight_class: WeightClass = WeightClass.LIGHT
@export var model_id := "knife"
@export var idle_action := "light_ready"
@export var attack_sequence: PackedStringArray = ["light_rise","light_stab"]
@export var damage: int = 16
@export var reach: float = 1.45
@export var duration: float = 0.38
@export var interval: float = 0.42
@export var visual_scale := Vector3(0.85, 1.0, 0.76)

func allows_sprint() -> bool:
	return weight_class != WeightClass.HEAVY

func weight_label() -> String:
	return {WeightClass.LIGHT:"轻型 · 移速 +10%",WeightClass.MEDIUM:"中型",WeightClass.HEAVY:"重型 · 无法疾跑"}.get(weight_class,"中型")

## 装备倍率只作用于主动移动；不放大跳跃初速和攻击前冲。
func movement_scale() -> float:
	return 1.1 if weight_class == WeightClass.LIGHT else 1.0
