class_name InventoryPanel
extends PanelContainer
signal item_dropped(item: ItemInstance)
signal notice(message: String)
## The bag and equipment UI. It only sends requests to the InventoryPort and renders what the port
## reports; it never computes stats, never moves items itself, and never awards anything.
##
## Layout is built in code: a 20-slot bag grid plus four equipment slots, with a detail line that
## compares the selected item against what is currently in its slot (TASKS.md T04 acceptance).

const BAG_COLUMNS := 5
const SLOT_LABELS := {
	&"weapon": "武器",
	&"head": "头部",
	&"body": "身体",
	&"accessory": "饰品",
}
const RARITY_NAMES := ["普通", "优质"]

@export var inventory_path: NodePath
@export var catalog_path: NodePath

var _inventory: ActorInventory
var _catalog: ItemCatalog
var _bag_buttons: Array[Button] = []
var _slot_buttons: Dictionary = {}
var _detail: Label
var _title: Label
var _selected_instance_id := ""

func _ready() -> void:
	_inventory = get_node_or_null(inventory_path) as ActorInventory
	_catalog = _resolve_catalog()
	_build_layout()
	if _inventory != null:
		_inventory.inventory_changed.connect(_refresh)
		_inventory.equipment_changed.connect(_on_equipment_changed)
	_refresh()

## The catalog lives with the loot spawner, which owns the drop rolls.
func _resolve_catalog() -> ItemCatalog:
	var spawner := get_node_or_null(catalog_path)
	if spawner != null and spawner.has_method("catalog"):
		return spawner.call("catalog") as ItemCatalog
	return ItemCatalog.build()

func _build_layout() -> void:
	custom_minimum_size = Vector2(300, 220)
	position.y = 44
	z_index = 10
	var background := StyleBoxFlat.new()
	background.bg_color = Color("202923")
	background.border_color = Color("84765a")
	background.set_border_width_all(1)
	background.content_margin_left = 8
	background.content_margin_right = 8
	background.content_margin_top = 6
	background.content_margin_bottom = 6
	add_theme_stylebox_override("panel", background)
	var root_box := VBoxContainer.new()
	add_child(root_box)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 13)
	root_box.add_child(_title)

	var equipment_row := HBoxContainer.new()
	root_box.add_child(equipment_row)
	for slot in ActorInventory.legal_slots():
		var column := VBoxContainer.new()
		equipment_row.add_child(column)
		var caption := Label.new()
		caption.text = SLOT_LABELS.get(slot, String(slot))
		caption.add_theme_font_size_override("font_size", 10)
		column.add_child(caption)
		var button := Button.new()
		button.custom_minimum_size = Vector2(66, 24)
		button.add_theme_font_size_override("font_size", 10)
		button.pressed.connect(_on_slot_pressed.bind(slot))
		column.add_child(button)
		_slot_buttons[slot] = button

	var separator := HSeparator.new()
	root_box.add_child(separator)

	var grid := GridContainer.new()
	grid.columns = BAG_COLUMNS
	root_box.add_child(grid)
	for index in ActorInventory.BAG_CAPACITY:
		var button := Button.new()
		button.custom_minimum_size = Vector2(52, 22)
		button.add_theme_font_size_override("font_size", 9)
		button.pressed.connect(_on_bag_pressed.bind(index))
		grid.add_child(button)
		_bag_buttons.append(button)

	_detail = Label.new()
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.custom_minimum_size = Vector2(0, 44)
	_detail.add_theme_font_size_override("font_size", 10)
	root_box.add_child(_detail)
	var actions := HBoxContainer.new()
	root_box.add_child(actions)
	for caption in ["装备", "卸下", "丢弃"]:
		var button := Button.new()
		button.text = caption
		button.add_theme_font_size_override("font_size", 11)
		button.pressed.connect(_perform_action.bind(caption))
		actions.add_child(button)

# --- interaction ---------------------------------------------------------------------------

func _on_bag_pressed(index: int) -> void:
	if _inventory == null:
		return
	var snapshot := _inventory.get_snapshot()
	var bag: Array = snapshot.get("bag", [])
	if index >= bag.size():
		return
	var entry: Dictionary = bag[index]
	if entry.is_empty():
		return
	var instance_id := String(entry.get("instance_id", ""))
	_selected_instance_id = instance_id
	_refresh()

func _on_slot_pressed(slot: StringName) -> void:
	if _inventory == null:
		return
	var equipped := _inventory.get_equipped(slot)
	if equipped == null:
		return
	_selected_instance_id = equipped.instance_id
	_refresh()

func _perform_action(action: String) -> void:
	if _inventory == null or _selected_instance_id.is_empty():
		return
	var port := _inventory.get_parent().get_node_or_null("ActorActionPort") as ActorCommandPort
	if port != null and not ActionRules.allows_locomotion(port.get_state()):
		_set_detail("动作结束后可换装")
		return
	var item := _inventory.get_in_bag(_selected_instance_id)
	if action == "装备":
		if item == null:
			return
		var definition := _catalog.definition(item.definition_id)
		if _inventory.try_equip(item.instance_id, ActorInventory.slot_for_category(definition.category)):
			notice.emit("已装备：" + definition.display_name)
		return
	if action == "丢弃":
		if item == null:
			_set_detail("请先卸下装备，再丢弃")
			return
		var removed := _inventory.take_from_bag(item.instance_id)
		if removed != null:
			item_dropped.emit(removed)
			_selected_instance_id = ""
			_refresh()
		return
	var equipped := _find_equipped(_selected_instance_id)
	if equipped == null:
		return
	## Unequipping swaps the item into the first free bag position; the displaced bag item (if the
	## bag is full, the last slot) goes back into the equipment slot, so the count never changes.
	var free_index := _first_free_bag_index()
	if free_index < 0:
		_set_detail("背包已满，无法卸下")
		return
	_inventory.try_unequip_to_slot(equipped.instance_id, free_index)

func _on_equipment_changed(_slot: StringName, _instance_id: String) -> void:
	_refresh()

# --- rendering -----------------------------------------------------------------------------

func _refresh() -> void:
	if _inventory == null:
		return
	var snapshot := _inventory.get_snapshot()
	var bag: Array = snapshot.get("bag", [])
	for index in _bag_buttons.size():
		var button := _bag_buttons[index]
		if index >= bag.size():
			button.text = "--"
			continue
		var entry: Dictionary = bag[index]
		button.text = _short_label(entry)
	var equipment: Dictionary = snapshot.get("equipment", {})
	for slot in _slot_buttons.keys():
		var button: Button = _slot_buttons[slot]
		var entry: Dictionary = equipment.get(slot, {})
		button.text = _short_label(entry)
	if _title != null:
		_title.text = "背包 %d/%d" % [_inventory.bag_used(), ActorInventory.BAG_CAPACITY]
	_refresh_detail(bag, equipment)

func _refresh_detail(bag: Array, equipment: Dictionary) -> void:
	if _detail == null:
		return
	if _selected_instance_id.is_empty():
		_detail.text = "选择物品查看对比，再点击装备、卸下或丢弃。"
		return
	var selected: Dictionary = {}
	for entry in bag:
		if not entry.is_empty() and String(entry.get("instance_id", "")) == _selected_instance_id:
			selected = entry
	if selected.is_empty():
		for slot in equipment.keys():
			var entry: Dictionary = equipment.get(slot, {})
			if not entry.is_empty() and String(entry.get("instance_id", "")) == _selected_instance_id:
				selected = entry
	if selected.is_empty():
		_detail.text = ""
		return
	_detail.text = _comparison_text(selected, equipment)

## Shows the candidate's modifiers next to what is currently equipped in its slot, so the choice
## can be made without doing arithmetic.
func _comparison_text(selected: Dictionary, equipment: Dictionary) -> String:
	var definition := _definition_of(selected)
	if definition == null:
		return ""
	var slot := ActorInventory.slot_for_category(definition.category)
	var current: Dictionary = equipment.get(slot, {})
	var lines: Array[String] = []
	lines.append("%s（%s）" % [definition.display_name, RARITY_NAMES[mini(int(selected.get("rarity", 0)), RARITY_NAMES.size() - 1)]])
	var keys := _modifier_keys(selected, current)
	for key in keys:
		var candidate := float((selected.get("modifiers", {}) as Dictionary).get(key, 0.0))
		var worn := float((current.get("modifiers", {}) as Dictionary).get(key, 0.0)) if not current.is_empty() else 0.0
		var delta := candidate - worn
		var sign_text := "+" if delta >= 0.0 else ""
		lines.append("  %s %+.0f（当前 %+.0f，%s%.0f）" % [_stat_label(key), candidate, worn, sign_text, delta])
	return "\n".join(lines)

static func _modifier_keys(a: Dictionary, b: Dictionary) -> Array[String]:
	var keys: Array[String] = []
	for key in (a.get("modifiers", {}) as Dictionary).keys():
		keys.append(String(key))
	for key in (b.get("modifiers", {}) as Dictionary).keys():
		if not keys.has(String(key)):
			keys.append(String(key))
	keys.sort()
	return keys

static func _stat_label(key: String) -> String:
	match key:
		"attack": return "攻击"
		"armor": return "护甲"
		"max_health": return "生命"
		"max_stamina": return "体力"
		"move_speed": return "移速"
		_: return key

func _short_label(entry: Dictionary) -> String:
	if entry.is_empty():
		return "--"
	var definition := _definition_of(entry)
	var name := definition.display_name if definition != null else String(entry.get("definition_id", "?"))
	var rarity := int(entry.get("rarity", 0))
	if rarity > 0:
		return "★%s" % name
	return name

func _definition_of(entry: Dictionary) -> ItemDefinition:
	if _catalog == null or entry.is_empty():
		return null
	return _catalog.definition(StringName(String(entry.get("definition_id", ""))))

# --- small helpers -------------------------------------------------------------------------

func _first_free_bag_index() -> int:
	var bag: Array = _inventory.get_snapshot().get("bag", [])
	for index in bag.size():
		if (bag[index] as Dictionary).is_empty():
			return index
	return -1

func _find_equipped(instance_id: String) -> ItemInstance:
	for slot in ActorInventory.legal_slots():
		var item := _inventory.get_equipped(slot)
		if item != null and item.instance_id == instance_id:
			return item
	return null

func _slot_of(instance_id: String) -> StringName:
	for slot in ActorInventory.legal_slots():
		var item := _inventory.get_equipped(slot)
		if item != null and item.instance_id == instance_id:
			return slot
	return &""

func _set_detail(text: String) -> void:
	if _detail != null:
		_detail.text = text
