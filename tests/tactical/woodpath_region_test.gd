extends SceneTree
## 实走主路、绕行和返程，并验证交互动画、独立NPC与新版UI；隔离真实进度。
const Region=preload("res://scripts/world/woodpath_region.gd")
var lab: Node3D
var checks:=0
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	checks+=1
	if not value: failures+=1
	print(("PASS " if value else "FAIL ")+message)
func frames(count: int) -> void:
	for i in count: await process_frame
func shot(id: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await frames(3)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://work/woodpath_v2/"+id+".png")
func walk(points: Array, label: String) -> void:
	var ok:=true
	for p in points:
		var target:=Vector3(p.x,0,p.y)
		var arrived:=false
		for i in 1000:
			var delta:=Vector2(target.x-lab.player.position.x,target.z-lab.player.position.z)
			if delta.length()<.30:
				arrived=true
				break
			lab.player.test_motion=delta.normalized()
			await physics_frame
		if not arrived:
			print("BLOCKED ",lab.player.position," -> ",target)
			ok=false
			break
	lab.player.test_motion=Vector2.ZERO
	check(ok,label)
func run() -> void:
	ProjectSettings.set_setting("tactical/testing",true)
	lab=load("res://scenes/courtyard_combat.tscn").instantiate()
	root.add_child(lab)
	current_scene=lab
	for i in 180:
		await physics_frame
		if is_instance_valid(lab.objective) and is_instance_valid(lab.objective.state): break
	lab.player.test_mode=true
	for i in 4: await physics_frame
	for enemy in get_nodes_in_group("tactical_enemies"):
		enemy.update_visuals(0)
		enemy.ai_enabled=false
	var story: Node=lab.objective
	check(not lab.progression.persist,"测试隔离存档")
	check(lab.player.safe_zone,"小院为安全营地")
	check(story.spots.satchel.distance_to(lab.player.position)>50,"主要目标离开营地")
	check(lab.region.props.size()>70,"新林地完成装配")
	for id in ["steward","healer"]:
		var node=story.interaction_nodes[id]
		check(node.visual.asset_id==id and node.visual.active,"NPC独立图集播放："+id)
	await shot("camp")
	lab.progression.toggle()
	await shot("equipment")
	check(lab.progression.view.equipment_root.find_children("*","Control",true,false).size()>7,"装备面板包含人形与七槽")
	lab.progression.toggle()
	story.speaking="steward"
	story.choose("accept")
	story.dialogue.close()
	await walk(Region.MAIN.slice(0,3),"实走营地到岔口")
	await shot("fork")
	lab.player.position=story.spots.sign+Vector3(0,.04,1)
	await frames(3)
	await story.interact()
	check(story.state.facts.get("sign_read",false),"路标调查解锁路线日志")
	story.dialogue.close()
	lab.player.position=Vector3(20,.04,10)
	await walk(Region.SIDE,"实走北侧林径到驿站")
	await shot("ruin")
	check(story.can_reach("satchel"),"到达遗留背包交互范围")
	await story.interact()
	check(lab.progression.open,"到达后实际打开搜刮界面")
	lab.progression.toggle()
	await walk([Vector2(61,-10),Vector2(61,-13),Vector2(61,-15.5)],"遗迹门洞保留可步行内部")
	await shot("ruin_inside")
	check(story.can_reach("supply"),"内屋药材箱可达")
	await story.interact()
	check(lab.progression.open,"内屋药材箱实际打开")
	await shot("medicine_container")
	lab.progression.toggle()
	lab.player.position=story.spots.chest+Vector3(0,.04,1.4)
	await frames(4)
	await story.interact()
	await create_timer(.4).timeout
	check(story.containers.chest.frame==3 and lab.progression.open,"宝箱打开动画完成并进入搜刮")
	await shot("chest_open")
	lab.progression.toggle()
	await create_timer(.4).timeout
	check(story.containers.chest.frame==0,"退出搜刮后箱盖关闭")
	lab.player.position=Vector3(60,.04,-7)
	await walk(Region.RETURN,"实走南侧环路返回大路")
	await shot("return_path")
	lab.player.position=story.spots.trail+Vector3(0,.04,1)
	await frames(3)
	await story.interact()
	check(story.state.facts.get("trail_read",false) and story.state.facts.get("cache_known",false),"药车提供证据和藏物位置")
	await shot("clue")
	story.dialogue.close()
	lab.player.position=Vector3(42,.04,-17)
	await walk([Vector2(42,-18.6)],"实走断树藏物接近点")
	check(story.can_reach("cache"),"隐藏容器可达")
	lab.player.position=Vector3(20,.04,10)
	await walk(Region.MAIN.slice(2),"实走正门主路进入驿站")
	check(lab.effects.streams.size()>=15,"实际采样覆盖移动战斗交互")
	for kind in lab.effects.streams:
		check(lab.effects.streams[kind].all(func(s):return s!=null and s.get_length()>0),"音频有效 "+kind)
	print("WOODPATH_REGION: %d checks, %d failures"%[checks,failures])
	lab.queue_free()
	await frames(4)
	quit(1 if failures else 0)
