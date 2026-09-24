extends Node
## 管理装备和首通奖励，连接玩家、战斗、库存、存档与背包视图。
const Save = preload("res://scripts/persistence/tactical_save.gd")
const InventoryView = preload("res://scripts/ui/inventory_panel.gd")
var save_path := "user://tactical_progress_v1.json"
var persist := true
var expedition: Node
var container_id := ""
var status_message := ""
var save_error := ""
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

## 创建初始库存并恢复 v1/v2 进度，再连接库存信号、背包视图并应用装备。
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
	var data := Save.read_snapshot(save_path) if persist else {}
	if persist:
		if not data.is_empty():
			rewarded = bool(data.get("rewarded", false))
			level = clampi(int(data.get("level", 1)), 1, 2)
			xp = clampi(int(data.get("xp", 0)), 0, 60)
			if data.get("inventory") is Dictionary:
				inventory.restore_from_snapshot(data.inventory)
	expedition = preload("res://scripts/progression/expedition_state.gd").new()
	add_child(expedition)
	expedition.setup(catalog,inventory,data.get("expedition",{}))
	expedition.changed.connect(changed)
	# 新旧进度都补一把可试用宝剑；先检查稳定实例 ID，重启不会重复发放或替换装备。
	if not expedition.owns_anywhere("camp_sword"):
		var sword := ItemInstance.new()
		sword.instance_id = "camp_sword"
		sword.definition_id = &"arming_sword"
		inventory.try_add(sword)
	# 试用断剑使用稳定实例 ID；满包时不覆盖物品，下次有空位再补发。
	if not expedition.owns_anywhere("camp_oath_blade"):
		var oath := ItemInstance.new()
		oath.instance_id = "camp_oath_blade"
		oath.definition_id = &"oath_blade"
		inventory.try_add(oath)
	# 弓成为独立装备；旧进度按稳定 ID 补发，不重复占用背包。
	if not expedition.owns_anywhere("camp_bow"):
		var bow_item := ItemInstance.new()
		bow_item.instance_id="camp_bow"
		bow_item.definition_id=&"hunting_bow"
		inventory.try_add(bow_item)
	# 初始装备与读档完成后再连接信号，避免恢复一半时就保存或刷新界面。
	inventory.inventory_changed.connect(changed)
	view = InventoryView.new()
	view.equip_requested.connect(equip)
	view.quick_requested.connect(equip_quick)
	view.refresh_requested.connect(refresh)
	view.action_requested.connect(handle_action)
	view.closed.connect(func(): container_id = "")
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
	combat.has_equipped_weapon = profile != null
	combat.hand.visible = profile != null
	if profile == null:
		combat.guard_held = false
		player.blocking = false
		combat.queued_action = 0
		combat.charge_hits = 0
	if profile == null:
		profile = catalog.definition(&"hunting_knife").weapon_profile
	combat.apply_weapon(profile)
	var modifiers := inventory.equipped_modifiers()
	player.max_hp = 100 + (level - 1) * 5 + int(modifiers.get("max_health",0))
	player.hp = mini(player.hp,player.max_hp)
	player.equipment_armor = int(modifiers.get("armor",0))
	if persist:
		var error := Save.write_snapshot(save_path, {
			"version": 2, "inventory": inventory.get_snapshot(), "expedition": expedition.get_snapshot(),
			"rewarded": rewarded, "level": level, "xp": xp,
		})
		if error != OK:
			save_error = "保存失败：" + error_string(error)
			push_warning(save_error)
		else: save_error = ""
	refresh()

## 死亡或攻击冷却中拒绝换装；成功交换后由库存信号触发后续刷新。
func equip(id: String) -> bool:
	if player.hp <= 0 or player.roll_time>0 or combat.cooldown > 0:
		return false
	return inventory.try_equip(id, &"weapon")

## 把库存与战斗状态转换成界面数据；武器说明读取同一份参数资源。
func refresh() -> void:
	if not is_instance_valid(view): return
	var item := inventory.get_equipped(&"weapon")
	view.refresh({"level":level,"xp":xp,"quick_slots":quick_slots(),"equipped_definition":str(item.definition_id) if item else "",
		"equipped_name":catalog.definition(item.definition_id).display_name if item else "无",
		"inventory":inventory.get_snapshot(),"catalog":catalog,"coins":expedition.coins,
		"journal":expedition.journal,"container_id":container_id,
		"container":expedition.source(container_id).get_snapshot() if not container_id.is_empty() else {},
		"container_title":expedition.TITLES.get(container_id,""),"hp":player.hp,"max_hp":player.max_hp,
		"armor":player.equipment_armor,"message":save_error if not save_error.is_empty() else status_message,
		"can_equip":player.hp>0 and player.roll_time<=0 and combat.cooldown<=0,"attacking":combat.cooldown>0})

## 只接受界面意图，所有写入仍回到库存或篇章事务；暂停不代表可以复活/打断攻击。
func handle_action(action: String, data: Dictionary) -> void:
	if player.hp <= 0: return
	var id: String = data.get("id","")
	var ok := false
	var item := inventory.get_in_bag(id)
	match action:
		"move": ok = inventory.try_move(id,data.cell,data.rotated)
		"move_container":
			if not container_id.is_empty():
				ok = expedition.source(container_id).try_move(id,data.cell,data.rotated)
				if ok: changed()
		"equip":
			if item != null and combat.cooldown<=0 and player.roll_time<=0:
				ok = inventory.try_equip(id,data.get("slot",ActorInventory.slot_for_category(catalog.definition(item.definition_id).category)))
		"unequip":
			if combat.cooldown<=0 and player.roll_time<=0: ok = inventory.try_unequip(id,data.get("cell",Vector2i(-1,-1)),data.get("rotated",false))
		"split": ok = inventory.try_split(id)
		"transfer":
			if not container_id.is_empty():
				var from: String = data.get("from","bag")
				var to: String = data.get("to",container_id)
				if from in ["bag",container_id] and to in ["bag",container_id]:
					ok = expedition.transfer(from,to,id,data.get("cell",Vector2i(-1,-1)),data.get("rotated",false))
		"take_all":
			var count: int = expedition.take_all(container_id)
			status_message = "已转移 %d 件，放不下的物品留在原处。" % count
			refresh()
			return
		"recover": ok = expedition.recover(id)
		"read": ok = expedition.read_item(id)
		"use":
			if item != null and player.hp<player.max_hp and combat.cooldown<=0:
				var heal := catalog.definition(item.definition_id).heal_amount
				if heal>0:
					player.hp = mini(player.max_hp,player.hp+heal)
					ok = inventory.consume(id)
	if ok and is_instance_valid(player.effects): player.effects.sound("read" if action=="read" else "inventory",player.global_position)
	status_message = "操作完成" if ok else "无法操作：检查空间、装备部位、生命或攻击状态。"
	refresh()

func open_container(id: String) -> void:
	if not expedition.containers.has(id) or player.hp<=0: return
	container_id = id
	if not open: view.toggle()
	refresh()

## 篇章结果、原件、奖励一次性落盘；满包奖励进入恢复仓储，不丢失或卡住剧情。
func finish_story(choice: String) -> bool:
	if not expedition.resolve(choice): return false
	if not rewarded:
		var reward: ItemInstance = expedition.make_item("great_cleaver","camp_reward_cleaver")
		inventory.muted = true
		if not expedition.owns_anywhere(reward.instance_id) and not inventory.try_add(reward):
			inventory.recovery.append(ActorInventory.instance_to_dictionary(reward))
		inventory.muted = false
		rewarded = true
		level = 2
		xp = 60
	changed()
	return true

## 把背包显隐请求转给视图，由视图维护暂停状态。
func toggle() -> void:
	view.toggle()

## 快捷栏只引用实际库存实例，固定武器顺序不会随背包交换而跳动。
func quick_slots() -> Array:
	var result: Array=[]
	var snapshot := inventory.get_snapshot()
	var equipped := inventory.get_equipped(&"weapon")
	for definition_id in ItemCatalog.default_ids():
		var instance_id := ""
		if equipped != null and equipped.definition_id==definition_id:
			instance_id=equipped.instance_id
		else:
			for entry in snapshot.bag:
				if entry.get("definition_id","")==str(definition_id):
					instance_id=entry.instance_id
					break
		result.append({"id":instance_id,"definition_id":str(definition_id),"label":catalog.definition(definition_id).display_name,"selected":equipped!=null and equipped.instance_id==instance_id})
	return result

## 键盘与点击共用装备规则；结算等暂停界面不允许快捷栏穿透换装。
func equip_quick(index: int) -> void:
	if get_tree().paused and not open: return
	var slots := quick_slots()
	if index>=0 and index<slots.size() and not slots[index].id.is_empty():
		equip(slots[index].id)
