class_name ActorInventory
extends InventoryPort
## 只在物品左上角保存实例，占用格由尺寸推导。跨容器先在副本校验，再一起提交。
const BAG_CAPACITY := 48
const SLOT_WEAPON := &"weapon"
const SLOT_HEAD := &"head"
const SLOT_BODY := &"body"
const SLOT_ACCESSORY := &"accessory"
var columns := 8
var rows := 6
var muted := false
var _catalog: ItemCatalog
var _bag: Array[ItemInstance] = []
var _equipment: Dictionary = {}
var recovery: Array = []

static func legal_slots() -> Array[StringName]:
	return [SLOT_WEAPON, SLOT_HEAD, SLOT_BODY, SLOT_ACCESSORY, &"hands", &"feet", &"cloak"]

static func slot_for_category(category: int) -> StringName:
	match category:
		ItemDefinition.Category.WEAPON: return SLOT_WEAPON
		ItemDefinition.Category.HEAD: return SLOT_HEAD
		ItemDefinition.Category.BODY: return SLOT_BODY
		ItemDefinition.Category.ACCESSORY: return SLOT_ACCESSORY
		ItemDefinition.Category.HANDS: return &"hands"
		ItemDefinition.Category.FEET: return &"feet"
		ItemDefinition.Category.CLOAK: return &"cloak"
	return &""

func _init() -> void:
	_bag.resize(BAG_CAPACITY)
	for slot in legal_slots(): _equipment[slot] = null

func set_catalog(catalog: ItemCatalog) -> void: _catalog = catalog
func get_catalog() -> ItemCatalog: return _catalog
func _ready() -> void:
	if _catalog == null: _catalog = ItemCatalog.build()

func _notify(slot: StringName = &"") -> void:
	if muted: return
	if slot != &"": equipment_changed.emit(slot, "")
	inventory_changed.emit()

func item_size(item: ItemInstance, rotated: bool) -> Vector2i:
	var definition := _definition_for(item)
	var size := definition.footprint if definition else Vector2i.ONE
	return Vector2i(size.y,size.x) if rotated else size

func occupied(exclude: String = "") -> Array[Rect2i]:
	var areas: Array[Rect2i] = []
	for i in _bag.size():
		var item := _bag[i]
		if item != null and item.instance_id != exclude:
			areas.append(Rect2i(Vector2i(i % columns, i / columns), item_size(item,item.rotated)))
	return areas

func can_place(item: ItemInstance, cell: Vector2i, rotated: bool, exclude: String = "") -> bool:
	var definition := _definition_for(item)
	return definition != null and (not rotated or definition.rotatable) and InventoryGrid.fits(columns,rows,cell,item_size(item,rotated),occupied(exclude))

## 自动拾取先合并同品质堆叠，再找矩形空位；全部装下才提交。
func try_add(item: ItemInstance) -> bool:
	if not _is_acceptable(item): return false
	var remaining := item.quantity
	var definition := _definition_for(item)
	var merges := {}
	if definition.max_stack > 1:
		for i in _bag.size():
			var existing := _bag[i]
			if existing != null and existing.definition_id == item.definition_id and existing.rarity == item.rarity and existing.modifiers == item.modifiers:
				var amount := mini(remaining,definition.max_stack-existing.quantity)
				if amount > 0:
					merges[i] = amount
					remaining -= amount
	var cell := Vector2i(-1,-1)
	var rotated := item.rotated and definition.rotatable
	if remaining > 0:
		if remaining > definition.max_stack: return false
		cell = InventoryGrid.first_fit(columns,rows,item_size(item,rotated),occupied())
		if cell.x < 0 and definition.rotatable:
			rotated = not rotated
			cell = InventoryGrid.first_fit(columns,rows,item_size(item,rotated),occupied())
		if cell.x < 0: return false
	for i in merges: _bag[i].quantity += merges[i]
	if remaining > 0:
		var copy := _copy_instance(item)
		copy.quantity = remaining
		copy.rotated = rotated
		_bag[cell.y * columns + cell.x] = copy
	_notify()
	return true

func try_add_at(item: ItemInstance, cell: Vector2i, rotated: bool) -> bool:
	if not _is_acceptable(item) or item.quantity > _definition_for(item).max_stack: return false
	var target := item_at(cell)
	if can_stack(item,target):
		target.quantity += item.quantity
		_notify()
		return true
	if not can_place(item,cell,rotated): return false
	var copy := _copy_instance(item)
	copy.rotated = rotated
	_bag[cell.y * columns + cell.x] = copy
	_notify()
	return true

func try_move(id: String, cell: Vector2i, rotated: bool) -> bool:
	var i := _find_in_bag(id)
	if i < 0: return false
	var target := item_at(cell)
	if target != _bag[i] and can_stack(_bag[i],target):
		target.quantity += _bag[i].quantity
		_bag[i] = null
		_notify()
		return true
	if not can_place(_bag[i],cell,rotated,id): return false
	var item := _bag[i]
	_bag[i] = null
	item.rotated = rotated
	_bag[cell.y * columns + cell.x] = item
	_notify()
	return true

func item_at(cell: Vector2i) -> ItemInstance:
	for i in _bag.size():
		if _bag[i] != null and Rect2i(Vector2i(i%columns,i/columns),item_size(_bag[i],_bag[i].rotated)).has_point(cell): return _bag[i]
	return null

func can_stack(item: ItemInstance, target: ItemInstance) -> bool:
	if item==null or target==null or item==target: return false
	var definition := _definition_for(item)
	return definition!=null and definition.max_stack>1 and item.definition_id==target.definition_id and item.rarity==target.rarity and item.modifiers==target.modifiers and item.quantity+target.quantity<=definition.max_stack

## 换装先模拟移走新装备，再安放旧装备；大武器装不下时完整回滚。
func try_equip(id: String, slot: StringName) -> bool:
	if not _equipment.has(slot): return false
	if _find_equipped_slot(id) == slot: return true
	var i := _find_in_bag(id)
	if i < 0 or slot_for_category(_definition_for(_bag[i]).category) != slot: return false
	var incoming := _bag[i]
	var displaced: ItemInstance = _equipment[slot]
	var prior := get_snapshot()
	var was_muted := muted
	muted = true
	_bag[i] = null
	_equipment[slot] = incoming
	if displaced != null and not try_add(displaced):
		restore_from_snapshot(prior,false)
		muted = was_muted
		return false
	muted = was_muted
	_notify(slot)
	return true

func try_equip_direct(item: ItemInstance, slot: StringName) -> bool:
	if not _is_acceptable(item) or not _equipment.has(slot) or slot_for_category(_definition_for(item).category) != slot: return false
	var old: ItemInstance = _equipment[slot]
	var was_muted := muted
	muted = true
	_equipment[slot] = _copy_instance(item)
	if old != null and not try_add(old):
		_equipment[slot] = old
		muted = was_muted
		return false
	muted = was_muted
	_notify(slot)
	return true

func try_unequip_to_slot(id: String, index: int) -> bool:
	if index < 0 or index >= _bag.size(): return false
	return try_unequip(id,Vector2i(index % columns,index / columns),false)

func try_unequip(id: String, cell := Vector2i(-1,-1), rotated := false) -> bool:
	var slot := _find_equipped_slot(id)
	if slot == &"": return false
	var item: ItemInstance = _equipment[slot]
	var prior := get_snapshot()
	var was_muted := muted
	muted = true
	_equipment[slot] = null
	var ok := try_add(item) if cell.x < 0 else try_add_at(item,cell,rotated)
	if not ok: restore_from_snapshot(prior,false)
	muted = was_muted
	if ok: _notify(slot)
	return ok

func try_split(id: String) -> bool:
	var item := get_in_bag(id)
	if item == null or item.quantity < 2: return false
	var copy := _copy_instance(item)
	copy.quantity = item.quantity / 2
	copy.instance_id = id + "_split_" + str(Time.get_ticks_usec())
	var cell := InventoryGrid.first_fit(columns,rows,item_size(copy,copy.rotated),occupied())
	if cell.x < 0: return false
	item.quantity -= copy.quantity
	_bag[cell.y*columns+cell.x] = copy
	_notify()
	return true

func consume(id: String, amount := 1) -> bool:
	var i := _find_in_bag(id)
	if i < 0 or amount < 1 or _bag[i].quantity < amount: return false
	_bag[i].quantity -= amount
	if _bag[i].quantity == 0: _bag[i] = null
	_notify()
	return true

func take_from_bag(id: String) -> ItemInstance:
	var item := get_in_bag(id)
	if item == null: return null
	var copy := _copy_instance(item)
	consume(id,item.quantity)
	return copy

## v1 无空间坐标，按顺序重排；未知定义和溢出原样进入可领取的恢复仓储。
func restore_from_snapshot(snapshot: Dictionary, notify := true) -> void:
	var was_muted := muted
	muted = true
	_bag.fill(null)
	for slot in legal_slots(): _equipment[slot] = null
	recovery = snapshot.get("recovery",[]).duplicate(true)
	var equipment: Dictionary = snapshot.get("equipment",{})
	for slot in equipment:
		var entry: Dictionary = equipment[slot]
		var item := _instance_from_dictionary(entry)
		if item == null: continue
		var definition := _definition_for(item)
		if _equipment.has(slot) and definition != null and slot_for_category(definition.category) == StringName(slot) and not has_instance(item.instance_id):
			_equipment[slot] = item
		else: recovery.append(entry.duplicate(true))
	for entry in snapshot.get("bag",[]):
		var item := _instance_from_dictionary(entry)
		if item == null: continue
		if has_instance(item.instance_id): continue
		var placed := false
		if entry.has("x") and entry.has("y"):
			placed = try_add_at(item,Vector2i(int(entry.x),int(entry.y)),item.rotated)
		if not placed: placed = try_add(item)
		if not placed: recovery.append(entry.duplicate(true))
	muted = was_muted
	if notify: _notify(&"weapon")

func get_snapshot() -> Dictionary:
	var bag: Array[Dictionary] = []
	for i in _bag.size():
		var entry := instance_to_dictionary(_bag[i])
		if not entry.is_empty():
			entry.x = i % columns
			entry.y = i / columns
		bag.append(entry)
	var equipment := {}
	for slot in legal_slots(): equipment[slot] = instance_to_dictionary(_equipment[slot])
	return {"bag":bag,"equipment":equipment,"columns":columns,"rows":rows,"recovery":recovery.duplicate(true)}

func bag_used() -> int:
	var count := 0
	for item in _bag:
		if item != null: count += 1
	return count

func used_cells() -> int:
	var count := 0
	for area in occupied(): count += area.size.x*area.size.y
	return count

func is_bag_full() -> bool: return used_cells() >= columns*rows
func _definition_for(item: ItemInstance) -> ItemDefinition:
	return _catalog.definition(item.definition_id) if _catalog != null and item != null else null
func _is_acceptable(item: ItemInstance) -> bool:
	return item != null and not item.instance_id.is_empty() and item.quantity > 0 and _definition_for(item) != null and not has_instance(item.instance_id)
func _find_in_bag(id: String) -> int:
	for i in _bag.size():
		if _bag[i] != null and _bag[i].instance_id == id: return i
	return -1
func _find_equipped_slot(id: String) -> StringName:
	for slot in legal_slots():
		if _equipment[slot] != null and _equipment[slot].instance_id == id: return slot
	return &""
func _copy_instance(item: ItemInstance) -> ItemInstance: return _instance_from_dictionary(instance_to_dictionary(item))

static func _instance_from_dictionary(entry: Variant) -> ItemInstance:
	if not entry is Dictionary or entry.get("instance_id","").is_empty() or entry.get("definition_id","").is_empty(): return null
	var item := ItemInstance.new()
	item.instance_id = str(entry.instance_id)
	item.definition_id = StringName(entry.definition_id)
	item.rarity = int(entry.get("rarity",0))
	item.modifiers = ItemCatalog.duplicate_modifiers(entry.get("modifiers",{}))
	item.quantity = maxi(1,int(entry.get("quantity",1)))
	item.rotated = bool(entry.get("rotated",false))
	return item

static func instance_to_dictionary(item: ItemInstance) -> Dictionary:
	if item == null: return {}
	return {"instance_id":item.instance_id,"definition_id":str(item.definition_id),"rarity":item.rarity,"modifiers":ItemCatalog.duplicate_modifiers(item.modifiers),"quantity":item.quantity,"rotated":item.rotated}

## 返回库存内部实例供读取；更换装备应使用换装接口。
func get_equipped(slot: StringName) -> ItemInstance:
	return _equipment.get(slot)

## 返回已装备武器的参数；为空时由战斗控制器选择默认配置。
func equipped_weapon_profile() -> TacticalWeaponData:
	return weapon_profile_of(get_equipped(SLOT_WEAPON))

## 按物品定义查找武器参数；空物品、未知定义或未配置武器参数时返回 null。
func weapon_profile_of(item: ItemInstance) -> TacticalWeaponData:
	if item == null:
		return null
	var definition := _definition_for(item)
	return definition.weapon_profile if definition != null else null

## 按实例 ID 返回背包内物品供读取，未找到时返回 null。
func get_in_bag(instance_id: String) -> ItemInstance:
	var index := _find_in_bag(instance_id)
	return _bag[index] if index >= 0 else null

func has_instance(instance_id: String) -> bool:
	return _find_in_bag(instance_id) >= 0 or _find_equipped_slot(instance_id) != &""

## 从当前装备重新汇总属性加成，避免反复换装时在旧结果上累加。
func equipped_modifiers() -> Dictionary:
	var equipped: Array[ItemInstance] = []
	for slot in legal_slots():
		var entry: ItemInstance = _equipment[slot]
		if entry != null:
			equipped.append(entry)
	return ItemCatalog.sum_modifiers(equipped)

## 读取单件物品的指定属性加成；空物品或缺少该属性时返回 0。
static func modifier_total(item: ItemInstance, key: StringName) -> float:
	if item == null:
		return 0.0
	return float(item.modifiers.get(key, 0.0))
