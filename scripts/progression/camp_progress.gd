extends Node
## Equipment/reward controller. Depends only on the player, combat, inventory and save service.
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

func setup(actor: CharacterBody3D, combat_system: Node3D) -> void:
	player = actor
	combat = combat_system

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
	inventory.inventory_changed.connect(changed)
	view = InventoryView.new()
	view.equip_requested.connect(equip)
	view.refresh_requested.connect(refresh)
	add_child(view)
	changed()

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

func equip(id: String) -> bool:
	if player.hp <= 0 or combat.cooldown > 0:
		return false
	return inventory.try_equip(id, &"weapon")

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
		summaries.append("%s：%d 伤害 · %.2fm · %.2fs 间隔" % [definition.display_name, profile.damage, profile.reach, profile.interval])
	view.refresh({
		"level": level, "xp": xp,
		"equipped_name": catalog.definition(item.definition_id).display_name if item else "无",
		"weapon_summary": "\n".join(summaries), "slots": slots,
		"can_equip": player.hp > 0 and combat.cooldown <= 0, "attacking": combat.cooldown > 0,
	})

func toggle() -> void:
	view.toggle()
