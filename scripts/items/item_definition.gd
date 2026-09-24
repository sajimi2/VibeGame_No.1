class_name ItemDefinition
extends Resource
## 共享物品定义，运行时约定只读；实例持有独立属性副本。

## 物品类别决定可放入的装备槽。
enum Category { WEAPON, HEAD, BODY, ACCESSORY, HANDS, FEET, CLOAK, CONSUMABLE, EVIDENCE, VALUABLE }

@export var id: StringName = &""
@export var display_name: String = ""
@export var category: Category = Category.ACCESSORY
## 装备属性的基础加成；兼容键包括 attack、armor、max_health、max_stamina、move_speed。
## 这些值保留在物品数据中，具体是否应用由玩法控制器决定。
@export var base_modifiers: Dictionary = {}
## 随机品质从此列表选择一个属性增加加成。
@export var bonus_pool: Array[StringName] = []
## 3D 战斗参数；库存快照只存定义 ID，不序列化此资源。
@export var weapon_profile: TacticalWeaponData
## 矩形尺寸和堆叠规则只属于定义；旋转、数量属于实例。
@export var footprint := Vector2i.ONE
@export var rotatable := true
@export var max_stack := 1
@export var description := ""
@export var heal_amount := 0
@export var sell_value := 0
@export var icon_index := -1
## 独立原画优先于旧图集，新增物品不必重新生成整张图集。
@export var icon_texture: Texture2D
