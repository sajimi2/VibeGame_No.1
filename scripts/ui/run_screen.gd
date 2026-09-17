extends CanvasLayer
## One attempt: contextual route hints and explicit death / hand-in results.
var player: CharacterBody3D
var objective: Node3D
var progression: Node
var hint_provider: Callable
var elapsed := 0.0
var finished := false
var showing := false
var won := false
var route_hint: Label
var panel: PanelContainer
var heading: Label
var details: Label
var retry_button: Button
var bag_button: Button
var continue_button: Button
var shade: ColorRect

func _ready() -> void:
	layer=30
	process_mode=Node.PROCESS_MODE_ALWAYS
	route_hint=Label.new()
	route_hint.position=Vector2(18,172)
	route_hint.add_theme_font_size_override("font_size",15)
	route_hint.add_theme_color_override("font_color",Color("cfceac"))
	route_hint.add_theme_color_override("font_shadow_color",Color.BLACK)
	route_hint.add_theme_constant_override("shadow_offset_x",1)
	route_hint.add_theme_constant_override("shadow_offset_y",1)
	add_child(route_hint)
	shade=ColorRect.new()
	shade.color=Color(0.03,0.06,0.08,0.70)
	shade.size=Vector2(1280,720)
	add_child(shade)
	panel=PanelContainer.new()
	panel.position=Vector2(355,215)
	panel.custom_minimum_size=Vector2(570,280)
	var style := StyleBoxFlat.new()
	style.bg_color=Color("17232a")
	style.border_color=Color("b5a574")
	style.set_border_width_all(2)
	style.content_margin_left=26
	style.content_margin_right=26
	style.content_margin_top=22
	style.content_margin_bottom=22
	panel.add_theme_stylebox_override("panel",style)
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",16)
	panel.add_child(column)
	heading=Label.new()
	heading.add_theme_font_size_override("font_size",28)
	heading.modulate=Color("eddbac")
	column.add_child(heading)
	details=Label.new()
	details.custom_minimum_size=Vector2(510,100)
	details.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	column.add_child(details)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation",12)
	column.add_child(buttons)
	retry_button=button(buttons,"重新出发 [R]",retry)
	bag_button=button(buttons,"查看装备 [I]",open_bag)
	continue_button=button(buttons,"继续逛逛 [Esc]",dismiss)
	panel.hide()
	shade.hide()

func button(parent: Node, text: String, action: Callable) -> Button:
	var item := Button.new()
	item.text=text
	item.custom_minimum_size.y=40
	item.pressed.connect(action)
	parent.add_child(item)
	return item

func _process(delta: float) -> void:
	if not get_tree().paused and not finished: elapsed+=delta
	if not showing:
		if player.hp<=0: present(false)
		elif objective.claimed and not finished: present(true)
	var quest=objective
	var position: Vector3=player.position
	if not hint_provider.call().is_empty():
		route_hint.text=hint_provider.call()
	elif quest.claimed: route_hint.text="委托已完成，可自由探索或重新出发。"
	elif quest.carried: route_hint.text="返回南侧营火旁，按 E 交付。道路两端都能返回营地。"
	elif position.distance_to(quest.exit_point)<2.5: route_hint.text="旧路：借矮墙绕盾接近守卫。东侧小径：穿过布帘，绕向高地。"
	elif position.x< -1.3 and position.z<5.5: route_hint.text="旧路守卫 · 正面盾挡箭；从矮墙侧面接近，抓挥刀后的破绽。"
	else: route_hint.text="密函高地 · 留意弓手两连射；用墙断开瞄准，再沿土坡逼近。"

func present(success: bool) -> void:
	if showing or (finished and success): return
	won=success
	finished=true
	showing=true
	if progression.open: progression.toggle()
	get_tree().paused=true
	heading.text="密函已交付" if success else "你倒在了哨站"
	var defeated := 0
	for enemy in get_tree().get_nodes_in_group("tactical_enemies"):
		if enemy.hp<=0: defeated+=1
	var time_text := "%02d:%02d" % [int(elapsed)/60,int(elapsed)%60]
	if success:
		details.text="用时 %s · 击败 %d / %d 名敌人（无需清场）\n" % [time_text,defeated,get_tree().get_nodes_in_group("tactical_enemies").size()]
		details.text+="首通奖励：大砍刀、60 经验；升至 2 级，生命上限 105。\n奖励已放入背包，可以立即换装。" if objective.first_reward else "本次委托完成。首通奖励此前已领取，本轮不重复发放。\n现有装备与成长已保留。"
	else:
		details.text="本次用时 %s。重新出发会重置敌人和密函。\n已获得的装备与成长保留，不扣物品。\n可试试借墙断开弓手瞄准，或从守卫侧后方进攻。" % time_text
	bag_button.visible=success
	continue_button.visible=success
	panel.show()
	shade.show()
	retry_button.grab_focus()

func dismiss() -> void:
	if not won: return
	showing=false
	panel.hide()
	shade.hide()
	get_tree().paused=false

func open_bag() -> void:
	if not won: return
	dismiss()
	progression.toggle()

func retry() -> void:
	get_tree().paused=false
	get_tree().reload_current_scene()

func _input(event: InputEvent) -> void:
	if not showing: return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode not in [KEY_R,KEY_I,KEY_ESCAPE]: return
		# Consume before reload removes this node from the scene tree.
		get_viewport().set_input_as_handled()
		if event.physical_keycode==KEY_R: retry()
		elif won and event.physical_keycode==KEY_I: open_bag()
		elif won and event.physical_keycode==KEY_ESCAPE: dismiss()

func setup(actor: CharacterBody3D, mission: Node3D, progress: Node, hint: Callable) -> void:
	player = actor
	objective = mission
	progression = progress
	hint_provider = hint
