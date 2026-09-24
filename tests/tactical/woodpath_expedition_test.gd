extends SceneTree
## 隔离验证格子库存、迁移、容器事务、输入与两种故事结果，不访问真实玩家进度。
var checks := 0
var failures := 0
var lab: Node3D
var catalog := ItemCatalog.build()
func _initialize() -> void: run.call_deferred()
func check(ok: bool, text: String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+text)
func frames(n: int) -> void:
	for i in n: await process_frame
func item(id: String, definition: String, quantity := 1) -> ItemInstance:
	var result := ItemInstance.new()
	result.instance_id=id
	result.definition_id=StringName(definition)
	result.quantity=quantity
	result.modifiers=catalog.definition(result.definition_id).base_modifiers.duplicate(true)
	return result
func inventory() -> ActorInventory:
	var result := ActorInventory.new()
	result.set_catalog(catalog)
	return result
func key(code: int) -> void:
	var event := InputEventKey.new()
	event.physical_keycode=code
	event.keycode=code
	event.pressed=true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
func mouse(at: Vector2, pressed: bool) -> void:
	if DisplayServer.get_name()!="headless": root.warp_mouse(at)
	var event := InputEventMouseButton.new()
	# Input入口接收窗口坐标；全屏1920×1080下要把1280×720设计坐标先映射过去。
	event.position=root.get_final_transform()*at
	event.global_position=event.position
	event.button_index=MOUSE_BUTTON_LEFT
	event.pressed=pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()
func capture(name: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://work/expedition/"+name+".png")
func walk_to(point: Vector3) -> bool:
	for i in 1000:
		var delta:=Vector2(point.x-lab.player.position.x,point.z-lab.player.position.z)
		if delta.length()<.22:
			lab.player.test_motion=Vector2.ZERO
			return true
		lab.player.test_motion=delta.normalized()
		await physics_frame
	lab.player.test_motion=Vector2.ZERO
	return false

func run() -> void:
	ProjectSettings.set_setting("tactical/testing",true)
	var bag := inventory()
	check(bag.try_add_at(item("sword","arming_sword"),Vector2i(0,0),false),"place vertical sword")
	check(not bag.try_add_at(item("knife","hunting_knife"),Vector2i(0,1),false),"occupied covered cell rejects overlap")
	var before := bag.get_snapshot()
	check(not bag.try_move("sword",Vector2i(7,5),false) and bag.get_snapshot()==before,"out of bounds keeps exact snapshot")
	check(bag.try_move("sword",Vector2i(2,1),true),"rotate and move horizontal sword")
	check(bag.used_cells()==3,"multi cell occupancy counts cells")
	check(bag.try_add(item("bandage1","bandage",3)) and bag.try_add(item("bandage2","bandage",2)),"merge compatible stack")
	check(bag.get_in_bag("bandage1").quantity==5 and bag.get_in_bag("bandage2")==null,"stack cap and quantity preserved")
	check(bag.try_split("bandage1") and bag.get_in_bag("bandage1").quantity==3,"split creates second placement")
	var split_entry: Dictionary=bag.get_snapshot().bag.filter(func(e):return e.get("instance_id","").begins_with("bandage1_split"))[0]
	var original: Dictionary=bag.get_snapshot().bag.filter(func(e):return e.get("instance_id","")=="bandage1")[0]
	check(bag.try_move(split_entry.instance_id,Vector2i(original.x,original.y),false) and bag.get_in_bag("bandage1").quantity==5,"drag stack merge keeps quantity")
	check(not bag.try_equip("bandage1",&"accessory"),"consumable cannot become accessory")
	check(bag.try_equip("sword",&"weapon") and bag.try_unequip("sword"),"equipment roundtrip retains instance")
	var full := inventory()
	full.try_equip_direct(item("large","great_cleaver"),&"weapon")
	full.try_add_at(item("small","hunting_knife"),Vector2i.ZERO,false)
	for y in 6:
		for x in 8:
			full.try_add_at(item("ring_%d_%d"%[x,y],"signet_ring"),Vector2i(x,y),false)
	before=full.get_snapshot()
	check(not full.try_equip("small",&"weapon") and full.get_snapshot()==before,"full bag cannot lose displaced big weapon")
	var legacy: Array = []
	for i in 20: legacy.append(ActorInventory.instance_to_dictionary(item("old_%d"%i,"great_cleaver")))
	var migrated := inventory()
	migrated.restore_from_snapshot({"bag":legacy,"equipment":{}})
	check(migrated.bag_used()+migrated.recovery.size()==20 and migrated.recovery.size()>0,"legacy overflow retained for recovery")
	var reclaim=load("res://scripts/progression/expedition_state.gd").new()
	root.add_child(reclaim)
	reclaim.setup(catalog,migrated,{})
	var recovery_id: String=migrated.recovery[0].instance_id
	check(not reclaim.recover(recovery_id),"full bag leaves recovery item intact")
	var first: Dictionary=migrated.get_snapshot().bag.filter(func(e):return not e.is_empty())[0]
	migrated.consume(first.instance_id)
	check(reclaim.recover(recovery_id) and migrated.has_instance(recovery_id),"recovery item can be claimed once space exists")
	reclaim.queue_free()
	var unknown := {"instance_id":"unknown","definition_id":"retired_item","rarity":1,"modifiers":{"armor":9}}
	migrated.restore_from_snapshot({"bag":[unknown],"equipment":{}})
	check(migrated.recovery.size()==1 and migrated.recovery[0]==unknown,"unknown definitions preserved verbatim")
	var save=load("res://scripts/persistence/tactical_save.gd")
	var path := "res://work/expedition/migration_"+str(Time.get_ticks_usec())+".json"
	check(save.write_snapshot(path,{"version":1,"inventory":{"bag":legacy}})==OK,"isolated v1 save created")
	check(save.write_snapshot(path,{"version":2,"inventory":migrated.get_snapshot()})==OK and FileAccess.file_exists(path+".v1.bak"),"v2 replacement preserves v1 backup")
	check(int(save.read_snapshot(path).version)==2,"v2 snapshot roundtrip")
	bag.free()
	full.free()
	migrated.free()
	lab=load("res://scenes/courtyard_combat.tscn").instantiate()
	root.add_child(lab)
	current_scene=lab
	while not is_instance_valid(lab.progression) or lab.objective.state==null: await frames(1)
	lab.player.test_mode=true
	for enemy in get_nodes_in_group("tactical_enemies"): enemy.ai_enabled=false
	await frames(10)
	var progress=lab.progression
	var state=progress.expedition
	var story=lab.objective
	var view=progress.view
	check(not progress.persist and lab.terrace_ground==null and lab.rolling_meadow==null,"new story isolated and rejected terrain disabled")
	check(progress.quick_slots().size()==5 and catalog.ids().size()==17,"new loot does not expand weapon quickbar")
	var before_cargo: Dictionary=progress.inventory.get_snapshot()
	var cargo: Dictionary=state.containers.supply.get_snapshot()
	check(state.containers.supply.used_cells()==27,"three medicine bundles occupy 27 cells")
	check(state.transfer("supply","bag","woodpath_supply_0"),"medicine cargo can be carried")
	check(state.sell_carried("medicine_bundle") and state.coins==20,"medicine sale consumes cargo and grants coins")
	check(not state.sell_carried("medicine_bundle") and state.coins==20,"medicine cannot be sold twice")
	# 填满剩余空间后搜刮失败必须保留原箱，玩家能回营腾出空间再来。
	for y in 6:
		for x in 8: progress.inventory.try_add_at(item("cargo_fill_%d_%d"%[x,y],"signet_ring"),Vector2i(x,y),false)
	check(not state.transfer("supply","bag","woodpath_supply_1") and state.containers.supply.has_instance("woodpath_supply_1"),"full bag leaves bulky cargo in source")
	progress.inventory.restore_from_snapshot(before_cargo,false)
	state.containers.supply.restore_from_snapshot(cargo,false)
	state.coins=0
	var tiny_target: ActorInventory=state.containers.stash
	var stash_before: Dictionary=tiny_target.get_snapshot()
	for y in 6:
		for x in 8: tiny_target.try_add_at(item("fill_%d_%d"%[x,y],"signet_ring"),Vector2i(x,y),false)
	var origin_before: Dictionary=progress.inventory.get_snapshot()
	var target_before: Dictionary=tiny_target.get_snapshot()
	check(not state.transfer("bag","stash","camp_sword") and progress.inventory.get_snapshot()==origin_before and tiny_target.get_snapshot()==target_before,"failed container transfer changes neither side")
	tiny_target.restore_from_snapshot(stash_before,false)
	check(story.can_reach("steward"),"spawn can reach steward")
	key(KEY_E)
	check(story.dialogue.open and paused,"E opens nearby conversation")
	story.choose("accept")
	check(state.facts.get("accepted",false),"accept option records quest")
	story.dialogue.close()
	var route_ok:=true
	for point in [Vector3(12,0,14),Vector3(20,0,10),Vector3(22,0,0),Vector3(30,0,-9),Vector3(42,0,-17),Vector3(54,0,-17),Vector3(60,0,-7)]:
		if not await walk_to(point):
			route_ok=false
			break
	check(route_ok and story.can_reach("satchel"),"actual movement through woodland side route reaches satchel")
	check(not story.can_reach("stash"),"distant container interaction refused")
	var initial_inventory: Dictionary=progress.inventory.get_snapshot()
	var initial_state: Dictionary=state.get_snapshot()
	var entry: Dictionary=state.containers.satchel.get_snapshot().bag.filter(func(e): return e.get("definition_id","")=="sealed_letter")[0]
	check(state.transfer("satchel","bag",entry.instance_id),"loot transaction transfers letter")
	check(not state.transfer("satchel","bag",entry.instance_id),"cannot take same letter twice")
	check(not progress.finish_story("expose"),"unearned evidence branch rejected")
	check(progress.finish_story("deliver") and state.coins==40 and state.find_carried("sealed_letter").is_empty(),"delivery consumes original and grants outcome")
	check(not progress.finish_story("deliver") and state.coins==40,"no repeated reward")
	progress.inventory.restore_from_snapshot(initial_inventory,false)
	state.facts=initial_state.facts.duplicate(true)
	state.coins=0
	state.journal=[]
	for id in state.containers: state.containers[id].restore_from_snapshot(initial_state.containers[id],false)
	progress.rewarded=false
	progress.level=1
	progress.xp=0
	check(state.take_all("satchel")==3,"loot satchel carries three distinct item stacks")
	var letter: String=state.find_carried("sealed_letter")
	check(state.read_item(letter) and state.facts.letter_read,"reading adds persistent fact")
	lab.player.position=story.spots.healer+Vector3(.7,.03,0)
	await frames(3)
	story.speaking="healer"
	story.choose("show_ring")
	check(state.facts.get("witness",false) and state.facts.cache_known and not state.find_carried("signet_ring").is_empty(),"showing ring unlocks testimony without consuming evidence")
	await capture("dialogue")
	story.dialogue.close()
	lab.player.position=story.spots.steward+Vector3(.8,.03,0)
	await frames(2)
	story.speaking="steward"
	story.show_conversation()
	await capture("merchant")
	check(story.dialogue.panel.get_global_rect().end.y<720,"merchant evidence and supply options remain within screen")
	story.dialogue.close()
	check(progress.finish_story("expose") and state.coins==20 and state.facts.outcome=="expose","evidence route commits distinct outcome")
	check(progress.inventory.has_instance("camp_reward_cleaver"),"first chapter reward added once")
	check(state.buy_supply("bandage") and state.coins==14,"loot income can buy supplies")
	check(state.buy_supply("healing_potion") and state.coins==2,"potion purchase deducts exact price")
	var trade_snapshot: Dictionary=progress.inventory.get_snapshot()
	check(not state.buy_supply("healing_potion") and state.coins==2 and progress.inventory.get_snapshot()==trade_snapshot,"insufficient funds changes neither coins nor items")
	check(state.take_all("chest")>0,"loot equipment from old chest")
	var empty_bag:=inventory()
	for definition in ["iron_helmet","leather_armor","leather_gloves","leather_boots","travel_cloak","amber_pendant"]:
		var gear:=item("gear_"+definition,definition)
		check(empty_bag.try_equip_direct(gear,ActorInventory.slot_for_category(catalog.definition(gear.definition_id).category)),"equipment category supported: "+definition)
	check(empty_bag.equipped_modifiers().armor==7 and empty_bag.equipped_modifiers().max_health==10,"gear sums armor and health once")
	empty_bag.free()
	var helmet: String=state.find_carried("iron_helmet")
	progress.handle_action("equip",{"id":helmet})
	check(progress.inventory.get_equipped(&"head")!=null and lab.player.equipment_armor==2,"body slot gear applies armor")
	lab.player.position=story.spots.healer+Vector3(.7,.03,0)
	var bandage: String=state.find_carried("bandage")
	lab.player.hp=45
	lab.player.safe_zone=false
	var quantity: int=progress.inventory.get_in_bag(bandage).quantity
	progress.handle_action("use",{"id":bandage})
	check(lab.player.hp==70 and progress.inventory.get_in_bag(bandage).quantity==quantity-1,"consumable heals and spends one item")
	progress.persist=true
	progress.save_path="res://work/expedition/story_save.json"
	progress.changed()
	var restored: Dictionary=save.read_snapshot(progress.save_path)
	check(restored.expedition.facts.outcome=="expose" and restored.expedition.containers.satchel.bag.all(func(e):return e.is_empty()),"story and emptied container saved together")
	progress.persist=false
	var reloaded=load("res://scripts/progression/expedition_state.gd").new()
	root.add_child(reloaded)
	reloaded.setup(catalog,progress.inventory,restored.expedition)
	check(reloaded.facts.outcome=="expose" and reloaded.containers.satchel.bag_used()==0,"restored state does not reseed emptied satchel")
	reloaded.queue_free()
	var carried_weapon: ItemInstance=progress.inventory.get_equipped(&"weapon")
	var weapon_id:=carried_weapon.instance_id
	check(progress.inventory.try_unequip(weapon_id),"equipped weapon can be stored in bag")
	check(not lab.combat.has_equipped_weapon and not lab.combat.attack(lab.player.position+Vector3.FORWARD),"empty weapon slot cannot attack with phantom knife")
	check(progress.equip(weapon_id) and lab.combat.has_equipped_weapon,"reequip restores weapon capability")
	progress.toggle()
	check(paused and view.open,"bag opens and pauses world")
	key(KEY_R)
	check(is_instance_valid(lab) and current_scene==lab,"R while browsing cannot restart level")
	await capture("inventory")
	var sword_entry: Dictionary=progress.inventory.get_snapshot().bag.filter(func(e):return e.get("definition_id","")=="arming_sword")[0]
	var start: Vector2=view.bag_grid.global_position+Vector2(sword_entry.x,sword_entry.y)*48+Vector2(20,20)
	mouse(start,true)
	await frames(2)
	check(not view.drag.is_empty(),"actual mouse press begins inventory drag")
	key(KEY_R)
	check(view.drag_rotated!=sword_entry.rotated,"R rotates drag preview")
	key(KEY_ESCAPE)
	check(view.drag.is_empty() and view.open and paused,"Escape cancels drag without closing bag")
	mouse(start,false)
	# 鼠标完成一次真实移动，再往占用格投放，确认失败不会覆盖原物品。
	mouse(start,true)
	await frames(2)
	# 内容增加后空位可能变化；用已独立验证的规则选空位，这里只验证真实UI输入链。
	var destination_cell:=Vector2i(-1,-1)
	for y in 6:
		for x in 8:
			var candidate:=Vector2i(x,y)
			if candidate!=Vector2i(sword_entry.x,sword_entry.y) and progress.inventory.can_place(progress.inventory.get_in_bag(sword_entry.instance_id),candidate,false,sword_entry.instance_id): destination_cell=candidate
	var destination: Vector2=view.bag_grid.global_position+Vector2(destination_cell)*48+Vector2(20,20)
	mouse(destination,false)
	await frames(2)
	var moved: Dictionary=progress.inventory.get_snapshot().bag.filter(func(e):return e.get("instance_id","")==sword_entry.instance_id)[0]
	check(Vector2i(moved.x,moved.y)==destination_cell and destination_cell.x>=0,"actual mouse release commits grid position")
	var unchanged: Dictionary=progress.inventory.get_snapshot()
	mouse(destination,true)
	var blocker: Dictionary=progress.inventory.get_snapshot().bag.filter(func(e):return e.get("definition_id","")=="hunting_bow")[0]
	mouse(view.bag_grid.global_position+Vector2(blocker.x,blocker.y)*48+Vector2(20,20),false)
	check(progress.inventory.get_snapshot()==unchanged,"invalid drop preserves all inventory data")
	key(KEY_ESCAPE)
	check(not view.open and not paused,"second Escape closes and restores pause state")
	progress.open_container("stash")
	check(view.open and view.external_root.visible,"container and backpack shown together")
	var store_weapon_id: String="camp_sword"
	check(state.transfer("bag","stash",store_weapon_id) and progress.quick_slots()[1].id.is_empty(),"stored weapon disappears from portable quickbar")
	check(state.transfer("stash","bag",store_weapon_id),"weapon can return from stash")
	var recovery_count: int=progress.inventory.recovery.size()
	check(recovery_count==0,"ordinary play produces no recovery overflow")
	await capture("container")
	progress.toggle()
	# 走到井边和西北藏物处，验证新交互点没有放进墙体或不可达区域。
	lab.player.position=Vector3(.8,.03,10)
	var healer_walk:=await walk_to(Vector3(-3.8,0,8.2))
	check(healer_walk and story.can_reach("healer"),"actual walk reaches healer")
	lab.player.position=Vector3(60,.03,-7)
	var chest_walk:=await walk_to(Vector3(62.5,0,-4))
	check(chest_walk and story.can_reach("chest"),"actual walk reaches painted chest")
	lab.player.position=Vector3(42,.03,-17)
	var cache_walk:=await walk_to(Vector3(42,0,-18.6))
	check(cache_walk and story.can_reach("cache"),"actual walk reaches revealed cache")
	await capture("world")
	var music_nodes: Array=[]
	for child in lab.get_children():
		if child is AudioStreamPlayer: music_nodes.append(child)
	check(music_nodes.size()==1 and music_nodes[0].stream.loop and music_nodes[0].playing,"BGM imported, looping and playing")
	lab.queue_free()
	await frames(3)
	print("%d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
