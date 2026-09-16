extends Node
## Reuse the original inventory and item schema; keep the tactical save separate.
var save_path := "user://tactical_progress_v1.json"
var persist := true
var lab: Node3D
var inventory: ActorInventory
var catalog: ItemCatalog
var rewarded := false
var level := 1
var xp := 0
var panel: PanelContainer
var content: VBoxContainer
var open := false
func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	catalog=ItemCatalog.new()
	catalog.load_definitions([&"hunting_knife",&"great_cleaver"])
	inventory=ActorInventory.new()
	inventory.name="TacticalInventory"
	inventory.set_catalog(catalog)
	add_child(inventory)
	var starter := ItemInstance.new()
	starter.instance_id="camp_knife"
	starter.definition_id=&"hunting_knife"
	inventory.try_equip_direct(starter,&"weapon")
	if persist and FileAccess.file_exists(save_path):
		var data=JSON.parse_string(FileAccess.get_file_as_string(save_path))
		if data is Dictionary and data.get("version",0)==1:
			rewarded=bool(data.get("rewarded",false))
			level=clampi(int(data.get("level",1)),1,2)
			xp=clampi(int(data.get("xp",0)),0,60)
			if data.get("inventory") is Dictionary: inventory.restore_from_snapshot(data.inventory)
	inventory.inventory_changed.connect(changed)
	var layer := CanvasLayer.new()
	layer.layer=20
	add_child(layer)
	panel=PanelContainer.new()
	panel.position=Vector2(330,180)
	panel.custom_minimum_size=Vector2(620,360)
	var style := StyleBoxFlat.new()
	style.bg_color=Color("17232a")
	style.border_color=Color("b5a574")
	style.set_border_width_all(2)
	style.content_margin_left=20
	style.content_margin_right=20
	style.content_margin_top=16
	style.content_margin_bottom=16
	panel.add_theme_stylebox_override("panel",style)
	layer.add_child(panel)
	content=VBoxContainer.new()
	content.add_theme_constant_override("separation",12)
	panel.add_child(content)
	panel.hide()
	changed()
func grant_reward() -> bool:
	if rewarded: return false
	var reward := ItemInstance.new()
	reward.instance_id="camp_reward_cleaver"
	reward.definition_id=&"great_cleaver"
	if not inventory.has_instance(reward.instance_id) and not inventory.try_add(reward): return false
	rewarded=true
	xp=60
	level=2
	changed()
	return true
func changed() -> void:
	var equipped=inventory.get_equipped(&"weapon")
	var heavy: bool = equipped!=null and equipped.definition_id==&"great_cleaver"
	lab.combat.melee_range=2.45 if heavy else 1.45
	lab.combat.melee_damage=26 if heavy else 16
	lab.combat.attack_duration=0.48 if heavy else 0.24
	lab.combat.attack_interval=0.62 if heavy else 0.29
	lab.combat.weapon.scale=Vector3(1.4,1,1.3) if heavy else Vector3(0.85,1,0.76)
	lab.player.max_hp=100+(level-1)*5
	if persist:
		var file=FileAccess.open(save_path,FileAccess.WRITE)
		if file:
			file.store_string(JSON.stringify({"version":1,"inventory":inventory.get_snapshot(),"rewarded":rewarded,"level":level,"xp":xp}))
	if is_instance_valid(content): refresh()
func equip(id: String) -> bool:
	if lab.player.hp<=0 or lab.combat.cooldown>0: return false
	return inventory.try_equip(id,&"weapon")
func refresh() -> void:
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	var title := Label.new()
	title.text="背包 / 等级 %d · 累计经验 %d    [I / Esc 关闭]" % [level,xp]
	title.add_theme_font_size_override("font_size",22)
	content.add_child(title)
	var item=inventory.get_equipped(&"weapon")
	var current := Label.new()
	current.text="当前武器："+(catalog.definition(item.definition_id).display_name if item else "无")
	content.add_child(current)
	var detail := Label.new()
	detail.text="猎刀：16 伤害 · 1.45m · 0.29s 间隔\n大砍刀：26 伤害 · 2.45m · 0.62s 间隔\n任意地点点击物品换装；攻击结束后可换。旧武器返回背包。"
	content.add_child(detail)
	var grid := GridContainer.new()
	grid.columns=5
	content.add_child(grid)
	for entry in inventory.get_snapshot().bag:
		var button := Button.new()
		button.custom_minimum_size=Vector2(108,36)
		button.text="—" if entry.is_empty() else catalog.definition(StringName(entry.definition_id)).display_name
		button.disabled=entry.is_empty() or lab.player.hp<=0 or lab.combat.cooldown>0
		if lab.combat.cooldown>0: button.tooltip_text="请先关闭背包，待攻击结束后换装"
		if not entry.is_empty(): button.pressed.connect(func(): equip(entry.instance_id))
		grid.add_child(button)
func toggle() -> void:
	open=not open
	panel.visible=open
	get_tree().paused=open
	if open: refresh()
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode==KEY_I or (open and event.physical_keycode==KEY_ESCAPE):
			toggle()
			get_viewport().set_input_as_handled()
