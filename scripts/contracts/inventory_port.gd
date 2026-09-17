@abstract
class_name InventoryPort
extends Node
signal inventory_changed
signal equipment_changed(slot: StringName, instance_id: String)

## 无效物品、重复 ID 或背包满时返回 false，库存不变；成功时库存保存深拷贝。
@abstract
func try_add(item: ItemInstance) -> bool

## 装备槽为 weapon、head、body、accessory。换装时旧装备回到新装备原来的位置，满包也能交换。
## 槽位、类型或归属不合法时直接拒绝，不留下部分修改。
@abstract
func try_equip(instance_id: String, slot: StringName) -> bool

## 返回库存的数据副本：bag 是物品字典数组，equipment 按槽位索引；空位为空字典。
## 物品字段为 instance_id、definition_id、rarity、modifiers，不返回可修改的 Resource 引用。
@abstract
func get_snapshot() -> Dictionary
