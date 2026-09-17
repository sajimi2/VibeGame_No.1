class_name ItemInstance
extends Resource
## 一件物品的独立实例；instance_id 区分同类物品，definition_id 指向只读定义。
## 随机属性保存在本实例中，不回写共享定义资源。
@export var instance_id: String = ""
@export var definition_id: StringName = &""
@export var rarity: int = 0
## 兼容快照的属性键：attack、armor、max_health、max_stamina、move_speed。
## 值为浮点加成，具体取值由物品目录决定。
@export var modifiers: Dictionary = {}
