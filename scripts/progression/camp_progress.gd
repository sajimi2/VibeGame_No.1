extends Node
## 管理装备和首通奖励，连接玩家、战斗、库存、存档与背包视图。
const Save = preload("res://scripts/persistence/tactical_save.gd")
const InventoryView = preload("res://scripts/ui/inventory_panel.gd")
var save_path := "user://tactical_progress_v1.json"
var persist := true
var player: CharacterBody3D
var combat: Node3D
var inventory: ActorInventory
var catalog: ItemCatalog
var rewarded := false
var level := 1
var xp := 0
var view: CanvasLayer
var open: bool:
	get: return is_instance_valid(view) and view.open

## 由关卡传入玩家与战斗系统，避免成长模块依赖整个地图。
func setup(actor: CharacterBody3D, combat_system: Node3D) -> void:
	player = actor
	combat = combat_system

## 创建初始库存并恢复 v1 进度，再连接库存信号、背包视图并应用装备。
func _ready() -> void:
	catalog = ItemCatalog.build()
	inventory = ActorInventory.new()
	inventory.name = "TacticalInventory"
	inventory.set_catalog(catalog)
	add_child(inventory)
	var starter := ItemInstance.new()
	starter.instance_id = "camp_knife"
	starter.definition_id = &"hunting_knife"
	inventory.try_equip_direct(starter, &"weapon")
	if persist:
		var data := Save.read_snapshot(save_path)
		if not data.is_empty():
			rewarded = bool(data.get("rewarded", false))
			level = clampi(int(data.get("level", 1)), 1, 2)
			xp = clampi(int(data.get("xp", 0)), 0, 60)
			if data.get("inventory") is Dictionary:
				inventory.restore_from_snapshot(data.inventory)
	# 新旧进度都补一把可试用宝剑；先检查稳定实例 ID，重启不会重复发放或替换装备。
	if not inventory.has_instance("camp_sword"):
		var sword := ItemInstance.new()
		sword.instance_id = "camp_sword"
		sword.definition_id = &"arming_sword"
		inventory.try_add(sword)
	# 初始装备与读档完成后再连接信号，避免恢复一半时就保存或刷新界面。
	inventory.inventory_changed.connect(changed)
	view = InventoryView.new()
	view.equip_requested.connect(equip)
	view.refresh_requested.connect(refresh)
	add_child(view)
	changed()

## 尝试发放一次首通奖励；背包放入成功后才标记领奖、升级并保存。
func grant_reward() -> bool:
	if rewarded:
		return false
	var reward := ItemInstance.new()
	reward.instance_id = "camp_reward_cleaver"
	reward.definition_id = &"great_cleaver"
	if not inventory.has_instance(reward.instance_id) and not inventory.try_add(reward):
		return false
	rewarded = true
	xp = 60
	level = 2
	changed()
	return true

## 响应库存变化，统一更新武器参数、生命上限、持久化快照和背包显示。
func changed() -> void:
	var profile := inventory.equipped_weapon_profile()
	if profile == null:
		profile = catalog.definition(&"hunting_knife").weapon_profile
	combat.apply_weapon(profile)
	player.max_hp = 100 + (level - 1) * 5
	if persist:
		var error := Save.write_snapshot(save_path, {
			"version": 1, "inventory": inventory.get_snapshot(),
			"rewarded": rewarded, "level": level, "xp": xp,
		})
		if error != OK:
			push_warning("Could not save tactical progress: " + error_string(error))
	refresh()

## 死亡或攻击冷却中拒绝换装；成功交换后由库存信号触发后续刷新。
func equip(id: String) -> bool:
	if player.hp <= 0 or combat.cooldown > 0:
		return false
	return inventory.try_equip(id, &"weapon")

## 把库存与战斗状态转换成界面数据；武器说明读取同一份参数资源。
func refresh() -> void:
	if not is_instance_valid(view):
		return
	var item := inventory.get_equipped(&"weapon")
	var slots: Array = []
	for entry in inventory.get_snapshot().bag:
		slots.append({
			"id": entry.get("instance_id", ""),
			"label": "—" if entry.is_empty() else catalog.definition(StringName(entry.definition_id)).display_name,
		})
	var summaries := PackedStringArray()
	for id in catalog.ids():
		var definition := catalog.definition(id)
		var profile := definition.weapon_profile
		summaries.append("%s（%s）：%d 伤害 · %.2fm · %.2fs 间隔" % [definition.display_name,profile.weight_label(),profile.damage,profile.reach,profile.interval])
	view.refresh({
		"level": level, "xp": xp,
		"equipped_name": catalog.definition(item.definition_id).display_name if item else "无",
		"weapon_summary": "\n".join(summaries), "slots": slots,
		"can_equip": player.hp > 0 and combat.cooldown <= 0, "attacking": combat.cooldown > 0,
	})

## 把背包显隐请求转给视图，由视图维护暂停状态。
func toggle() -> void:
	view.toggle()
