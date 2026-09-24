extends Node
## 小篇章数据所有者：箱子、证据、日志、钱币。输入已验证交互，输出可保存快照与变化信号。
signal changed
var inventory: ActorInventory
var catalog: ItemCatalog
var containers: Dictionary = {}
var facts: Dictionary = {}
var coins := 0
var journal: Array = []
const TITLES := {"stash":"营地仓库", "satchel":"信使遗留的背包", "chest":"驿站货箱", "cache":"榆树根的藏匿处", "supply":"遗迹中的药材箱"}

func setup(items: ItemCatalog, bag: ActorInventory, saved: Dictionary) -> void:
	catalog = items
	inventory = bag
	facts = saved.get("facts",{}).duplicate(true)
	coins = int(saved.get("coins",0))
	journal = saved.get("journal",[]).duplicate()
	var snapshots: Dictionary = saved.get("containers",{})
	for id in TITLES:
		var container := ActorInventory.new()
		container.set_catalog(catalog)
		container.muted = true
		add_child(container)
		containers[id] = container
		if snapshots.has(id): container.restore_from_snapshot(snapshots[id],false)
		else: _seed(id,container)

func _seed(id: String, target: ActorInventory) -> void:
	# 新箱子只在快照缺失时初始化；旧箱子与玩家物品不补发、不重排。
	if id == "supply":
		for i in 3: target.try_add(make_item("medicine_bundle","woodpath_supply_%d" % i))
		return
	var seeds := {"stash":[["bandage",3],["leather_gloves",1],["leather_boots",1]],"satchel":[["sealed_letter",1],["signet_ring",1],["bandage",2]],"chest":[["bronze_relic",1],["iron_helmet",1],["leather_armor",1],["healing_potion",2]],"cache":[["travel_cloak",1],["amber_pendant",1],["bronze_relic",1]]}
	for spec in seeds[id]:
		var item := make_item(spec[0],"woodpath_"+id+"_"+spec[0],spec[1])
		target.try_add(item)

func make_item(definition: String, id: String, quantity := 1) -> ItemInstance:
	var item := ItemInstance.new()
	item.instance_id = id
	item.definition_id = StringName(definition)
	item.quantity = quantity
	item.modifiers = catalog.definition(item.definition_id).base_modifiers.duplicate(true)
	return item

func get_snapshot() -> Dictionary:
	var snapshots := {}
	for id in containers: snapshots[id] = containers[id].get_snapshot()
	return {"containers":snapshots,"facts":facts.duplicate(true),"coins":coins,"journal":journal.duplicate()}

func source(id: String) -> ActorInventory:
	return inventory if id == "bag" else containers.get(id)

func owns_anywhere(id: String) -> bool:
	for store in [inventory] + containers.values():
		if store.has_instance(id): return true
		for entry in store.recovery:
			if entry.get("instance_id","") == id: return true
	return false

## 两端先在副本校验；成功才同时恢复两份状态，并只发一次完整事务通知。
func transfer(from: String, to: String, id: String, cell := Vector2i(-1,-1), rotated := false) -> bool:
	var origin := source(from)
	var destination := source(to)
	if origin == null or destination == null or origin == destination: return false
	var item := origin.get_in_bag(id)
	if item == null: return false
	var trial := ActorInventory.new()
	trial.set_catalog(catalog)
	trial.muted = true
	trial.restore_from_snapshot(destination.get_snapshot(),false)
	var ok := trial.try_add(item) if cell.x < 0 else trial.try_add_at(item,cell,rotated)
	var result := trial.get_snapshot()
	trial.free()
	if not ok: return false
	var previous_mute := origin.muted
	origin.muted = true
	origin.consume(id,item.quantity)
	origin.muted = previous_mute
	destination.restore_from_snapshot(result,false)
	changed.emit()
	return true

func take_all(id: String) -> int:
	var container := source(id)
	if container == null or id == "bag": return 0
	var count := 0
	for entry in container.get_snapshot().bag:
		if not entry.is_empty() and transfer(id,"bag",entry.instance_id): count += 1
	return count

func note(key: String, text: String) -> void:
	if facts.get(key,false): return
	facts[key] = true
	journal.append(text)
	changed.emit()

func find_carried(definition: String) -> String:
	for entry in inventory.get_snapshot().bag:
		if entry.get("definition_id","") == definition: return entry.instance_id
	return ""

func read_item(id: String) -> bool:
	var item := inventory.get_in_bag(id)
	if item == null: return false
	if item.definition_id == &"sealed_letter":
		note("letter_read","密信：被带走的并非军饷，而是送往隔离村的药款。信使打算留下原始账目。")
		return true
	if item.definition_id == &"signet_ring":
		note("ring_read","戒指：榆叶家徽，内刻「给归家的人」。也许井边的药师认得它。")
		return true
	return false

## 小型补给交易让搜刮收入可用于下次出行；装不下或钱不足时不扣款。
func buy_supply(definition: String) -> bool:
	var prices := {"bandage":6,"healing_potion":12}
	if not prices.has(definition) or coins<int(prices[definition]): return false
	var item := make_item(definition,"purchase_"+definition+"_"+str(Time.get_ticks_usec()))
	var was_muted := inventory.muted
	inventory.muted=true
	var ok := inventory.try_add(item)
	inventory.muted=was_muted
	if not ok: return false
	coins-=int(prices[definition])
	changed.emit()
	return true

## 商人只收白名单随身物品；扣物与加钱一次通知，重复请求不能凭空售卖。
func sell_carried(definition: String) -> bool:
	if definition not in ["bronze_relic", "medicine_bundle"]: return false
	var id := find_carried(definition)
	if id.is_empty(): return false
	var was_muted := inventory.muted
	inventory.muted = true
	inventory.consume(id)
	inventory.muted = was_muted
	coins += catalog.definition(StringName(definition)).sell_value
	changed.emit()
	return true

func recover(id: String) -> bool:
	for i in inventory.recovery.size():
		var entry: Dictionary = inventory.recovery[i]
		if entry.get("instance_id","") != id: continue
		var item := ActorInventory._instance_from_dictionary(entry)
		var was_muted := inventory.muted
		inventory.muted = true
		var ok := inventory.try_add(item)
		if ok: inventory.recovery.remove_at(i)
		inventory.muted = was_muted
		if ok: changed.emit()
		return ok
	return false

## 对话只调用白名单结果。交付原件与结果同时提交；出示戒指不消耗。
func resolve(choice: String) -> bool:
	if not facts.get("outcome","").is_empty(): return false
	var letter := find_carried("sealed_letter")
	if letter.is_empty(): return false
	if choice == "expose" and not (facts.get("letter_read",false) and facts.get("witness",false)): return false
	if choice not in ["deliver","expose"]: return false
	var was_muted := inventory.muted
	inventory.muted = true
	inventory.consume(letter)
	inventory.muted = was_muted
	facts.outcome = choice
	coins += 40 if choice == "deliver" else 20
	journal.append("你交出了密信。管事付了40枚钱币，却立即把信投入火中。药师不再愿意多谈。" if choice == "deliver" else "你把账目交给米菈保管。管事退还20枚钱币作为药款。药师交给你北方渡口的线索，允许领取树根藏物。")
	if choice == "expose": facts.cache_known = true
	return true
