extends Node3D
## 空间交互桥：距离/遮挡校验后打开容器或对话，剧情事实只归 expedition_state。
var player: CharacterBody3D
var progress: Node
var exit_point := Vector3.ZERO
var pickup_point := Vector3.ZERO
var accepted := false
var carried := false
var completed := false
var claimed := false
var first_reward := false
var hud: Label
var dialogue: CanvasLayer
var state: Node
var speaking := ""
var authored_map: Node3D
var interaction_nodes: Dictionary = {}
var spots: Dictionary = {}
var labels: Dictionary = {}
var message := ""
var message_time := 0.0
var trade_message := ""
var containers: Dictionary={}
var busy := false
var point_labels: CanvasLayer
const Region=preload("res://scripts/world/woodpath_region.gd")

func _ready() -> void:
	# 标签投影晚于镜头更新，文字保持屏幕字号，不随滚轮缩成几颗像素。
	process_priority=100
	point_labels=CanvasLayer.new()
	point_labels.layer=1
	add_child(point_labels)
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Label.new()
	hud.theme=preload("res://scripts/ui/pixel_style.gd").theme()
	hud.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	hud.position = Vector2(18,112)
	hud.add_theme_font_size_override("font_size",17)
	hud.add_theme_color_override("font_shadow_color",Color.BLACK)
	hud.add_theme_constant_override("shadow_offset_x",2)
	hud.add_theme_constant_override("shadow_offset_y",2)
	layer.add_child(hud)
	dialogue = preload("res://scripts/ui/story_dialogue.gd").new()
	dialogue.chosen.connect(choose)
	add_child(dialogue)

func bind_progress(value: Node) -> void:
	progress = value
	state = progress.expedition
	if authored_map!=null:
		# ID关联已有故事/存档，坐标只从真实场景节点取得；不再创建固定交互物。
		for node in authored_map.find_children("*","Node3D",true,false):
			var id: String=node.get_meta("interaction_id","")
			if id.is_empty(): continue
			if interaction_nodes.has(id):
				push_error("重复交互ID，请勿复制任务容器ID："+id)
				continue
			interaction_nodes[id]=node
			if id in ["steward","healer"]: node.camera=player.camera
			if id in ["chest","stash","cache","supply"]: containers[id]=node
		_refresh_spots()
	else:
		spots = Region.SPOTS.duplicate()
	var names := {"steward":"营地管事 · 奥伦", "healer":"井边药师 · 米菈","stash":"营地仓库","satchel":"信使遗留背包","chest":"驿站货箱","cache":"榆树根的藏匿处","trail":"倾覆药车 · 调查","sign":"旧林路路标 · 调查","memorial":"无名旅人的石堆 · 调查","supply":"遗迹中的药材箱"}
	for id in spots:
		var label := Label.new()
		label.text = names[id]
		label.theme=preload("res://scripts/ui/pixel_style.gd").theme()
		label.add_theme_font_size_override("font_size",17)
		label.add_theme_color_override("font_color",Color("ecd6a4"))
		label.add_theme_color_override("font_outline_color",Color("182019"))
		label.add_theme_constant_override("outline_size",4)
		label.mouse_filter=Control.MOUSE_FILTER_IGNORE
		point_labels.add_child(label)
		labels[id] = label
		if authored_map!=null: continue
		if id in ["steward","healer"]:
			var villager := preload("res://scripts/presentation/story_villager.gd").new()
			villager.position = spots[id]
			villager.camera = player.camera
			villager.asset_id=id
			add_child(villager)
		elif id in ["chest","stash","cache","supply"]:
			var chest:=preload("res://scripts/presentation/animated_container.gd").new()
			chest.position=spots[id]
			chest.name="HiddenCache" if id=="cache" else "Container_"+id
			add_child(chest)
			containers[id]=chest
		elif id=="satchel":
			var bag:=Node3D.new()
			bag.position=spots[id]
			add_child(bag)
			var art=preload("res://scripts/presentation/weapon_art.gd")
			art.block(bag,Vector3(.42,.28,.34),Vector3.UP*.14,"795b40")
			art.block(bag,Vector3(.08,.30,.36),Vector3.UP*.16,"b09060")
	progress.view.closed.connect(_close_containers)
	if not state.facts.get("woodpath_expanded",false):
		state.note("woodpath_expanded","林路重新开放。营地以东是废弃驿站；旧物品和委托结果仍保留。路标、倾覆药车与南侧石堆可调查。")

## 标签、距离和声音共用实时脚点；父节点整体平移也不会留下旧交互位置。
func _refresh_spots() -> void:
	if authored_map==null: return
	spots.clear()
	for id in interaction_nodes:
		var node=interaction_nodes[id]
		if is_instance_valid(node): spots[id]=node.global_position

func can_reach(id: String) -> bool:
	_refresh_spots()
	if not spots.has(id) or player.hp<=0: return false
	var target: Vector3 = spots[id]
	if player.global_position.distance_to(target)>2.15: return false
	var ray := PhysicsRayQueryParameters3D.create(player.global_position+Vector3.UP*.8,target+Vector3.UP*.7,1|4)
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	return hit.is_empty() or (hit.position as Vector3).distance_to(target+Vector3.UP*.7)<.65

func nearest() -> String:
	_refresh_spots()
	var result := ""
	var distance := 2.15
	for id in spots.keys():
		if id=="cache" and not state.facts.get("cache_known",false): continue
		var d: float = player.global_position.distance_to(spots[id])
		if d<distance and can_reach(id):
			distance=d
			result=id
	return result

func interact() -> bool:
	if state==null or busy or get_tree().paused: return false
	var id := nearest()
	if id.is_empty(): return inform("靠近人物或容器，再按 E。墙壁会阻挡交互。")
	if id in ["steward","healer"]:
		trade_message=""
		speaking=id
		show_conversation()
	elif id in ["sign","trail","memorial"]:
		investigate(id)
	else:
		if containers.has(id):
			busy=true
			containers[id].set_open(true)
			player.effects.sound("chest_open",spots[id])
			await get_tree().create_timer(.24,false).timeout
			busy=false
			if not is_instance_valid(player) or not can_reach(id):
				containers[id].set_open(false)
				return false
		player.effects.sound("inventory",spots[id])
		progress.open_container(id)
	return true

## 地点调查给出可执行的线索，事实只记一次；重复查看不会刷奖励。
func investigate(id: String) -> void:
	speaking=id
	var text:=""
	match id:
		"sign":
			text="褪色的木牌指向东北：灰榆驿站。\n宽路上有新脚印；北侧窄径留下了一串车轮擦痕。\n\n正门更直接，林中小路可以绕到驿站西侧缺口。"
			state.note("sign_read","路标：东面大路通向有人把守的驿站正门；北侧小径通往西侧缺口。")
		"trail":
			text="车辙在这里突然转向。一只药瓶碎在泥里，破布上的榆叶纹样与你在营地见过的药袋相同。\n\n车底刻着一行字：『账目留在驿站，药先送出去。——埃文』\n这不像一场携款逃跑。药师可能知道更多。"
			state.note("trail_read","倾覆药车：埃文留下『账目在驿站，药先送出去』。这是可以向米菈追问的证据。")
			state.facts.cache_known=true
			state.note("tree_mark","药袋夹层的草图标着北侧小径中段、断树旁的榆树根。那里可能有补给。")
		"memorial":
			text="几块石头压住了一张褪色的渡船票。背面写着：『别信账本上那些名字；有人早在去年冬天就死了。』\n\n南侧林路可以绕回驿站前的大路。你将票上的印记抄进日志。"
			state.note("memorial_read","南侧石堆：渡船票上的记号与账目有关；部分收药人可能早已死亡。北方渡口值得继续调查。")
	player.effects.sound("read",spots[id])
	dialogue.display(labels[id].text,text,[["leave","记下线索，继续探索"]])

func _close_containers() -> void:
	for id in containers:
		if containers[id].opened:
			containers[id].set_open(false)
			player.effects.sound("chest_close",spots[id])

func show_conversation() -> void:
	var options: Array = []
	var text := ""
	var outcome: String = state.facts.get("outcome","")
	if speaking=="steward":
		text="信使埃文带走了营地的账目，最后有人在东面的灰榆驿站见过他。替我找回封蜡信。林路上有拦路人，你不必和每个人交手。\n出发前可以把多余装备放进身旁仓库。"
		if not state.facts.get("accepted",false): options.append(["accept","接下委托，询问信使最后的去向"])
		elif outcome.is_empty():
			text="从院门向东，循土路走到岔口。正门那条路近，北侧林径能绕过去。他的背包应该还在驿站庭院。把信原样带回来，我们就两清。"
			if not state.find_carried("sealed_letter").is_empty():
				options.append(["deliver","交出密信，领取40枚钱币（结束委托）"])
				if state.facts.get("letter_read",false) and state.facts.get("witness",false): options.append(["expose","拿账目与证词质问他，将证据交给药师（结束委托）"])
		else:
			text="报酬已经付了。信使的事，到此为止。" if outcome=="deliver" else "……那笔药款我会退回去。账目留在药师那里随你，别再当众提起我的名字。"
		if not state.find_carried("bronze_relic").is_empty(): options.append(["sell","出售一尊旧王铜像 · 获得25枚钱币"])
		options.append(["stash","打开身旁的营地仓库"])
		options.append(["buy_bandage","买一卷绷带 · 6枚钱币"])
		options.append(["buy_potion","买一瓶药剂 · 12枚钱币"])
		text+="\n\n身上钱币：%d" % state.coins
		if not trade_message.is_empty(): text+=" · "+trade_message
	else:
		text="米菈停下洗药草的手。\n「他管那孩子叫贼？我只见到一个想把药送到北方村子的人。但空口无凭，我不能把你的命也搭进去。」"
		if outcome=="deliver": text="「你已经把信给他了？」米菈望向营地的火光，不再继续说下去。"
		elif state.facts.get("witness",false): text="「榆树根下还有埃文留下的东西。把信看明白，再决定信谁。若你留下账目，我们至少还有说理的机会。」"
		elif not state.find_carried("signet_ring").is_empty() or state.facts.get("trail_read",false): options.append(["show_ring","出示戒指或药车调查记录，询问埃文"])
		else: text+="\n她提到，埃文一直戴着一枚榆叶戒指。"
	if speaking=="healer":
		if not state.find_carried("medicine_bundle").is_empty(): options.append(["sell_medicine","交回一包药材 · 获得20枚钱币"])
		text+="\n\n她愿用20枚钱币回收每包封装药材，原件留在驿站内屋。"
		if not trade_message.is_empty(): text+="\n"+trade_message
	options.append(["leave","暂时离开"])
	dialogue.display("奥伦 · 营地管事" if speaking=="steward" else "米菈 · 井边药师",text,options)

## 选项执行时再检查条件，不信任过期界面；交易一次落盘，重复选择无额外奖励。
func choose(id: String) -> void:
	if id=="leave":
		dialogue.close()
		return
	if not can_reach(speaking):
		dialogue.close()
		return
	match id:
		"accept": state.note("accepted","奥伦委托：沿东面林路前往灰榆驿站，找回信使背包里的封蜡信。岔路路标与北侧药车值得调查。")
		"show_ring":
			if speaking=="healer" and (not state.find_carried("signet_ring").is_empty() or state.facts.get("trail_read",false)) and state.facts.get("outcome","")!="deliver":
				state.facts.cache_known=true
				state.note("witness","米菈认出了榆叶记号：埃文运的是救命药款，奥伦却想收回账目。她指出北侧林径断树旁的藏匿处。")
		"deliver", "expose":
			if speaking=="steward" and progress.finish_story(id):
				var ending: String = state.journal.back()
				dialogue.display("委托落定",ending+"\n\n记录已保存。可以继续搜查、整理物品，或回营地休息。",[["leave","继续探索"]])
				return
		"sell", "sell_medicine":
			var seller := "steward" if id=="sell" else "healer"
			var definition := "bronze_relic" if id=="sell" else "medicine_bundle"
			if speaking==seller and state.sell_carried(definition):
				trade_message="铜像已售出，获得25枚钱币。" if id=="sell" else "药材已交回，获得20枚钱币。"
				player.effects.sound("coins",spots[speaking])
		"buy_bandage", "buy_potion":
			if speaking=="steward":
				var ok: bool=state.buy_supply("bandage" if id=="buy_bandage" else "healing_potion")
				trade_message="补给已放入行囊。" if ok else "钱币不足或行囊装不下，未扣款。"
		"stash":
			if speaking=="steward":
				dialogue.close()
				containers.stash.set_open(true)
				player.effects.sound("chest_open",spots.stash)
				progress.open_container("stash")
				return
	show_conversation()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==KEY_E:
		interact()
		get_viewport().set_input_as_handled()

func _physics_process(delta: float) -> void:
	if state==null: return
	message_time=maxf(0,message_time-delta)
	accepted=state.facts.get("accepted",false)
	carried=not state.find_carried("sealed_letter").is_empty()
	completed=not state.facts.get("outcome","").is_empty()
	# 不触发旧取信结算页；篇章结果留在对话和日志里，仍可继续搜查。
	player.safe_zone=player.position.x<8 and player.position.z>5
	if player.safe_zone and player.hp>0: player.hp=player.max_hp
	var id:=nearest()
	if labels.has("cache"):
		labels.cache.visible=state.facts.get("cache_known",false)
		containers.cache.visible=labels.cache.visible
	hud.text="失踪信使 · 委托已落定，仍可探索林路秘密" if completed else "失踪信使 · 返回营地交信，或向药师求证" if carried else "失踪信使 · 沿东面林路调查灰榆驿站" if accepted else "失踪信使 · 靠近营地管事，按 E 交谈"
	if not id.is_empty(): hud.text+="\nE · "+labels[id].text
	if message_time>0: hud.text+="\n"+message

func inform(text: String) -> bool:
	message=text
	message_time=3.0
	return false

## 交互名称只显示附近已知地点；投影到2D层，保留世界脚点但不经过世界纹理采样。
func _process(_delta: float) -> void:
	if state==null or not is_instance_valid(player.camera): return
	_refresh_spots()
	for id in labels:
		var label:Label=labels[id]
		if not spots.has(id):
			label.hide()
			continue
		var anchor:Vector3=spots[id]+Vector3.UP*(2.15 if id in ["steward","healer"] else 1.1)
		label.visible=player.position.distance_to(spots[id])<9 and (id!="cache" or state.facts.get("cache_known",false)) and not player.camera.is_position_behind(anchor)
		if label.visible:
			label.position=(player.camera.unproject_position(anchor)-Vector2(label.size.x*.5,label.size.y)).round()
